# Guía de Permisos Granulares de Claves

##  Resumen

Sistema de permisos de dos niveles implementado en DigSigna:

1. **Nivel 1: RBAC del Tenant** - Permisos generales por rol
2. **Nivel 2: Permisos de Clave** - Control granular por clave específica

##  Principio de Seguridad: Defense in Depth

```
Usuario tiene rol "Signing User"
    ↓
Tiene permiso general "document:sign"
    ↓
Debe tener permiso SIGN en la clave específica
    ↓
Permiso debe estar activo (no revocado, dentro de ventana de validez)
    ↓
[x] PERMITIDO
```

##  Tipos de Permisos

| Permiso | Bitmap | Descripción | Caso de Uso |
|---------|--------|-------------|-------------|
| `SIGN` | 1 | Firmar documentos | Firmas digitales |
| `ENCRYPT` | 2 | Cifrar datos | Protección de datos |
| `DECRYPT` | 4 | Descifrar datos | Lectura de datos cifrados |
| `VERIFY` | 8 | Verificar firmas | Auditoría, validación |
| `MANAGE` | 16 | Gestionar clave | Rotación, configuración |
| `REVOKE` | 32 | Revocar certificados | Administración PKI |
| `DELEGATE` | 64 | Delegar permisos | Subdelegación temporal |
| `EXPORT` | 128 | Exportar clave pública | Distribución de certs |
| `BACKUP` | 256 | Crear backup | DR y continuidad |

##  Casos de Uso - Municipio de Celaya

### Escenario 1: Jerarquía de Permisos

```sql
-- María González (Admin Municipal)
-- [x] Puede: SIGN, MANAGE, DELEGATE en ambas claves
-- [x] Puede otorgar permisos a otros usuarios

-- Carlos Ramírez (Director Desarrollo Urbano)
-- [x] Puede: SIGN, MANAGE, DELEGATE en KEY_PERMISOS_CONSTRUCCION
-- [x] Puede: VERIFY (solo lectura) en KEY_FIRMA_NOMINA
-- [ ] NO puede: Firmar nóminas

-- Ana Martínez (Encargado Permisos)
-- [x] Puede: SIGN en KEY_PERMISOS_CONSTRUCCION (temporal hasta 2026-12-31)
-- [ ] NO puede: Gestionar la clave ni delegar permisos
-- [ ] NO tiene: Acceso a KEY_FIRMA_NOMINA

-- Luis Pérez (Asistente)
-- [x] Puede: VERIFY, EXPORT en KEY_PERMISOS_CONSTRUCCION
-- [ ] NO puede: Firmar ni gestionar
```

### Escenario 2: Delegación Temporal

```sql
-- Carlos delega permiso a Ana por 1 año
INSERT INTO key_permissions (
    key_id, user_id, permission_type,
    granted_by, valid_from, valid_to,
    metadata
)
VALUES (
    'key_construccion',
    'ana_martinez',
    'SIGN',
    'carlos_ramirez',  -- Delegado por Carlos
    '2026-01-01',
    '2026-12-31',  -- Expira automáticamente
    '{"restriction": "solo_permisos_menores", "max_amount": 100000}'
);
```

### Escenario 3: Revocación de Emergencia

```sql
-- Detectamos acceso sospechoso de Ana
UPDATE key_permissions
SET 
    revoked_by = 'maria_gonzalez',
    revoked_at = NOW(),
    revocation_reason = 'Actividad sospechosa detectada - Investigación en curso'
WHERE user_id = 'ana_martinez'
  AND key_id = 'key_construccion'
  AND permission_type = 'SIGN'
  AND revoked_at IS NULL;

-- Ana pierde acceso INMEDIATAMENTE
-- Su rol de Tenant sigue activo (puede usar otras claves)
-- Auditoría completa: quién revocó, cuándo, por qué
```

## 🚀 Queries de Performance

### Query 1: Verificar permiso (usando cache)

```sql
-- Verificación ultra-rápida con bitwise operations
SELECT 
    (permissions_bitmap & 1) AS can_sign,
    (permissions_bitmap & 2) AS can_encrypt,
    (permissions_bitmap & 4) AS can_decrypt,
    (permissions_bitmap & 8) AS can_verify,
    (permissions_bitmap & 16) AS can_manage
FROM key_permissions_cache
WHERE user_id = ? 
  AND key_id = ?
  AND (earliest_expiry IS NULL OR earliest_expiry > NOW());
```

### Query 2: Listar permisos activos de un usuario

```sql
-- Permisos activos con información de la clave
SELECT 
    k.name AS key_name,
    k.alias AS key_alias,
    kp.permission_type,
    kp.valid_from,
    kp.valid_to,
    u_granted.email AS granted_by_email,
    kp.metadata
FROM key_permissions kp
JOIN crypto_keys k ON kp.key_id = k.id
LEFT JOIN users u_granted ON kp.granted_by = u_granted.id
WHERE kp.user_id = ?
  AND kp.revoked_at IS NULL
  AND kp.valid_from <= NOW()
  AND (kp.valid_to IS NULL OR kp.valid_to > NOW())
ORDER BY k.name, kp.permission_type;
```

### Query 3: Auditoría de permisos (incluye revocados)

```sql
-- Historial completo de permisos de una clave
SELECT 
    u.email AS user_email,
    u.first_name,
    u.last_name,
    kp.permission_type,
    kp.granted_by,
    kp.created_at,
    kp.revoked_by,
    kp.revoked_at,
    kp.revocation_reason,
    CASE 
        WHEN kp.revoked_at IS NOT NULL THEN 'REVOKED'
        WHEN kp.valid_to < NOW() THEN 'EXPIRED'
        WHEN kp.valid_from > NOW() THEN 'PENDING'
        ELSE 'ACTIVE'
    END AS status
FROM key_permissions kp
JOIN users u ON kp.user_id = u.id
WHERE kp.key_id = ?
ORDER BY kp.created_at DESC;
```

## 🔄 Mantenimiento del Cache

### Trigger para actualizar cache automáticamente

```sql
DELIMITER //

CREATE TRIGGER trg_refresh_key_permissions_cache
AFTER INSERT ON key_permissions
FOR EACH ROW
BEGIN
    -- Calcular bitmap de permisos activos
    INSERT INTO key_permissions_cache (user_id, key_id, permissions_bitmap, earliest_expiry)
    SELECT 
        NEW.user_id,
        NEW.key_id,
        SUM(
            CASE permission_type
                WHEN 'SIGN' THEN 1
                WHEN 'ENCRYPT' THEN 2
                WHEN 'DECRYPT' THEN 4
                WHEN 'VERIFY' THEN 8
                WHEN 'MANAGE' THEN 16
                WHEN 'REVOKE' THEN 32
                WHEN 'DELEGATE' THEN 64
                WHEN 'EXPORT' THEN 128
                WHEN 'BACKUP' THEN 256
            END
        ) AS permissions_bitmap,
        MIN(valid_to) AS earliest_expiry
    FROM key_permissions
    WHERE user_id = NEW.user_id
      AND key_id = NEW.key_id
      AND revoked_at IS NULL
      AND valid_from <= NOW()
      AND (valid_to IS NULL OR valid_to > NOW())
    GROUP BY user_id, key_id
    ON DUPLICATE KEY UPDATE
        permissions_bitmap = VALUES(permissions_bitmap),
        earliest_expiry = VALUES(earliest_expiry);
END//

DELIMITER ;
```

## 📈 Ventajas del Diseño

### 1. Auditoría Completa
- ✅ Cada permiso es un registro independiente
- ✅ Historial completo: quién otorgó, quién revocó, cuándo, por qué
- ✅ Cumplimiento con ISO 27001, SOC 2, NOM-151

### 2. Flexibilidad
- ✅ Permisos temporales con expiración automática
- ✅ Delegación de permisos (granted_by)
- ✅ Revocación suave (soft delete con revoked_at)
- ✅ Metadata JSON para condiciones adicionales

### 3. Performance
- ✅ Cache materializada con bitmap para queries frecuentes
- ✅ Índices optimizados para cada tipo de consulta
- ✅ Una sola query para verificar todos los permisos

### 4. Seguridad
- ✅ Principio de Least Privilege
- ✅ Defense in Depth (dos niveles de autorización)
- ✅ Ventanas de validez automáticas
- ✅ Revocación inmediata en caso de emergencia

## 🎓 Mejores Prácticas

### DO ✅
- Usar permisos temporales para delegaciones
- Revocar permisos cuando ya no se necesiten
- Documentar razones de revocación
- Revisar periódicamente permisos activos
- Usar metadata para condiciones adicionales

### DON'T ❌
- NO otorgar MANAGE/DELEGATE sin necesidad
- NO usar valid_to = NULL para permisos temporales
- NO eliminar registros (usar revoked_at)
- NO confiar solo en RBAC del tenant
- NO ignorar earliest_expiry en el cache

## 📞 Soporte

Para dudas sobre el sistema de permisos, contactar:
- Equipo de Seguridad: security@digsigna.com
- Documentación: https://docs.digsigna.com/key-permissions

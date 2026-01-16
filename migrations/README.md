# Estructura de Migraciones - DigSigna Platform

## Organización Modular

Las migraciones han sido divididas en módulos pequeños y manejables para facilitar el mantenimiento y comprensión del esquema de base de datos.

### Módulos Core (001-006)

#### **001_base_tables.up.sql** (~300 líneas)
**Descripción:** Tablas base del sistema
- `tenants` - Modelo híbrido (MANAGED/INDEPENDENT)
- `organizations` - Municipios, empresas, colegios, etc.
- `roles` - Sistema de roles
- `permissions` - Permisos granulares
- `role_permissions` - Relación roles-permisos
- `users` - Usuarios del sistema
- `user_roles` - Relación usuarios-roles
- `user_permissions` - Permisos directos de usuarios
- `user_sessions` - Sesiones de usuario
- `identity_documents` - Documentos de identidad

**Orden de ejecución:** 1  
**Dependencias:** Ninguna

---

#### **002_crypto_pki.up.sql** (~300 líneas)
**Descripción:** Infraestructura PKI (Claves y Certificados)
- `crypto_keys` - Claves criptográficas con jerarquía PKI
- `key_metadata` - Metadata de claves
- `key_operations` - Auditoría de operaciones con claves
- `key_permissions` - **Permisos granulares por clave** (diseño normalizado con auditoría completa)
- `key_permissions_cache` - Cache materializada para performance (bitmap de permisos)
- `certificates` - Certificados digitales con cadena de confianza

**Sistema de Permisos:** Ver [KEY_PERMISSIONS_GUIDE.md](../KEY_PERMISSIONS_GUIDE.md) para detalles completos del sistema de permisos de dos niveles (RBAC + permisos granulares).

**Orden de ejecución:** 2  
**Dependencias:** 001_base_tables (tenants, organizations, users)

---

#### **003_signing_workflow.up.sql** (~150 líneas)
**Descripción:** Flujo de trabajo de firma digital
- `signing_requests` - Solicitudes de firma
- `signatures` - Firmas digitales generadas
- `verifications` - Verificaciones de firmas

**Orden de ejecución:** 3  
**Dependencias:** 002_crypto_pki (crypto_keys, certificates)

---

#### **004_audit_quotas.up.sql** (~250 líneas)
**Descripción:** Auditoría y sistema de cuotas
- `audit_logs` - Logs de auditoría del sistema
- `audit_metadata` - Metadata adicional de auditoría
- `tenant_quotas` - Cuotas y límites por tenant
- `tenant_usage` - Consumo en tiempo real
- `tenant_usage_history` - Historial de consumo

**Orden de ejecución:** 4  
**Dependencias:** 001_base_tables (tenants, organizations, users)

---

#### **005_pki_triggers.up.sql** (~350 líneas)
**Descripción:** Triggers de validación de integridad PKI
- `trg_validate_certificate_hierarchy_before_insert` - Validar jerarquía de certificados
- `trg_validate_certificate_hierarchy_before_update` - Prevenir cambios críticos
- `trg_prevent_delete_ca_with_children` - Prevenir eliminación de CAs con hijos
- `trg_validate_crypto_key_before_insert` - Validar jerarquía de claves (modo híbrido)
- `trg_validate_organization_for_key` - Validar organización activa
- `trg_prevent_delete_key_with_children` - Prevenir eliminación de claves con hijos

**Orden de ejecución:** 5  
**Dependencias:** 002_crypto_pki (crypto_keys, certificates)

---

#### **006_rollback_all.down.sql**
**Descripción:** Rollback completo de todas las tablas y triggers
- Elimina todos los triggers PKI
- Elimina todas las tablas en orden inverso
- Útil para ambiente de desarrollo

**Orden de ejecución:** N/A (solo para rollback)

---

### Módulos Adicionales (007-011)

#### **007_views.up/down.sql**
Vistas de base de datos

#### **008_procedures.up/down.sql**
Procedimientos almacenados

#### **009_events.up/down.sql**
Eventos programados

#### **010_users_permissions.up/down.sql**
Configuración adicional de usuarios y permisos

#### **011_seed.up/down.sql**
Datos iniciales (seeds):
- Permisos del sistema
- Tenant plataforma (MANAGED, hsm_slot=0)
- Roles: Tenant Administrator, Organization Manager, Signing User
- Usuarios de prueba
- Cuotas iniciales

---

## Orden de Ejecución

```
1. 001_base_tables.up.sql
2. 002_crypto_pki.up.sql
3. 003_signing_workflow.up.sql
4. 004_audit_quotas.up.sql
5. 005_pki_triggers.up.sql
6. 007_views.up.sql
7. 008_procedures.up.sql
8. 009_events.up.sql
9. 010_users_permissions.up.sql
10. 011_seed.up.sql
```

---

## Estadísticas

| Archivo | Líneas | Tablas | Triggers | Descripción |
|---------|--------|--------|----------|-------------|
| 001_base_tables | ~300 | 10 | 0 | Usuarios, roles, organizaciones |
| 002_crypto_pki | ~300 | 7 | 0 | Claves, permisos granulares, PKI |
| 003_signing_workflow | ~150 | 3 | 0 | Firmas y verificaciones |
| 004_audit_quotas | ~250 | 5 | 0 | Auditoría y límites |
| 005_pki_triggers | ~350 | 0 | 6 | Validaciones PKI |
| 006_billing_plans | ~350 | 6 | 0 | Planes y facturación |
| 011_seed | ~850 | 0 | 0 | Datos iniciales + Celaya |
| **TOTAL CORE** | **~2,550** | **31** | **6** | **Sistema completo** |

---

## Ventajas de la Estructura Modular

1. **Mantenibilidad**: Archivos de ~150-350 líneas son más fáciles de revisar
2. **Granularidad**: Rollback selectivo por módulo
3. **Claridad**: Cada archivo tiene una responsabilidad clara
4. **Colaboración**: Menos conflictos en PRs
5. **Testing**: Se pueden probar módulos independientemente
6. **Documentación**: Más fácil de documentar y entender

---

## Rollback

### Rollback completo (desarrollo):
```sql
SOURCE 006_rollback_all.down.sql
```

### Rollback selectivo (producción):
```sql
-- Eliminar solo triggers
DROP TRIGGER IF EXISTS trg_validate_certificate_hierarchy_before_insert;
DROP TRIGGER IF EXISTS trg_validate_certificate_hierarchy_before_update;
...

-- Eliminar solo módulo de firma
DROP TABLE IF EXISTS verifications;
DROP TABLE IF EXISTS signatures;
DROP TABLE IF EXISTS signing_requests;
```

---

## Notas Importantes

- **SET FOREIGN_KEY_CHECKS = 0/1**: Usado para permitir creación de tablas con FKs circulares
- **UUID() Default**: Genera IDs únicos automáticamente
- **TIMESTAMP(6)**: Precisión de microsegundos para auditoría
- **ON DELETE CASCADE/RESTRICT**: Integridad referencial explícita
- **Índices incluidos**: Todos los índices necesarios están en el mismo archivo de tabla

---

## Desarrollo

### Agregar nueva tabla:
1. Determinar el módulo correcto (base, crypto, signing, audit)
2. Agregar al archivo `.up.sql` correspondiente
3. Agregar DROP en `006_rollback_all.down.sql`
4. Actualizar este README

### Modificar tabla existente:
1. Crear nuevo archivo `0XX_alter_<table>.up.sql`
2. Incluir migraciones reversibles
3. Documentar cambios

---

**Versión:** 2.0.0  
**Fecha:** 2026-01-15  

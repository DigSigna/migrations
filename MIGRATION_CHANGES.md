# Cambios en el Esquema de Base de Datos - Jerarquía PKI y Organizaciones

## Resumen de Cambios

Se ha refactorizado el esquema de base de datos para soportar:
1. **Jerarquía de claves y certificados (PKI)** - Cadena de confianza explícita
2. **Organizaciones flexibles** - Reemplazo de `departments` por `organizations` polimórficas
3. **Referencias de auditoría mejoradas** - Tracking de organizaciones en operaciones

---

## Tablas Modificadas

### 1. **`departments` → `organizations`**
**Antes:**
```sql
CREATE TABLE departments (
    id CHAR(36),
    tenant_id CHAR(36),
    name VARCHAR(255),
    description TEXT
);
```

**Después:**
```sql
CREATE TABLE organizations (
    id CHAR(36),
    tenant_id CHAR(36),
    parent_id CHAR(36),              -- ✨ NUEVO: Auto-referencia para jerarquía
    type VARCHAR(50),                -- ✨ NUEVO: 'DEPARTMENT', 'COMPANY', 'SCHOOL', etc.
    name VARCHAR(255),
    legal_name VARCHAR(255),         -- ✨ NUEVO
    description TEXT,
    level INT DEFAULT 0,             -- ✨ NUEVO: Profundidad en jerarquía
    status ENUM(...),                -- ✨ NUEVO
    metadata JSON                    -- ✨ NUEVO: Datos específicos por tipo
);
```

**Cambios clave:**
- [x] Soporte para cualquier tipo de entidad (empresa, colegio, división, etc.)
- [x] Jerarquía auto-referenciada con `parent_id`
- [x] Campo `level` para navegación eficiente
- [x] Metadata JSON para extensibilidad

---

### 2. **`users`**
**Cambios:**
```sql
-- Antes:
department_id CHAR(36)
FOREIGN KEY (department_id) REFERENCES departments(id)

-- Después:
organization_id CHAR(36)
FOREIGN KEY (organization_id) REFERENCES organizations(id)
```

---

### 3. **`crypto_keys` - Jerarquía PKI**
**Nuevos campos:**
```sql
owner_type ENUM('TENANT', 'ORGANIZATION', 'USER')  --  Propietario polimórfico
owner_id CHAR(36)                                   --  ID del propietario
parent_key_id CHAR(36)                              --  Clave padre en PKI
cert_level INT DEFAULT 0                            --  0=master, 1=intermediate, 2=end-entity
```

**Flujo de jerarquía:**
```
Tenant Master Key (level=0, parent=NULL)
  └─> Organization Key (level=1, parent=master_key_id)
      └─> User Key (level=2, parent=org_key_id)
```

**Foreign Key:**
```sql
FOREIGN KEY (parent_key_id) REFERENCES crypto_keys(id) ON DELETE RESTRICT
```

---

### 4. **`certificates` - Cadena de certificación**
**Nuevos campos:**
```sql
owner_type ENUM('TENANT', 'ORGANIZATION', 'USER')  --  Propietario polimórfico
owner_id CHAR(36)                                   --  ID del propietario
issuer_key_id CHAR(36)                              --  Clave que firmó el CSR
cert_level INT DEFAULT 0                            --  Nivel en jerarquía
path_length INT                                     --  Profundidad máxima de sub-CAs
```

**Cadena de confianza:**
```sql
-- Certificado raíz
owner_type='TENANT', issuer_certificate_id=NULL, issuer_key_id=NULL, cert_level=0

-- Certificado intermedio (empresa)
owner_type='ORGANIZATION', issuer_certificate_id=root_cert, issuer_key_id=master_key, cert_level=1

-- Certificado end-entity (usuario)
owner_type='USER', issuer_certificate_id=org_cert, issuer_key_id=org_key, cert_level=2
```

---

### 5. **`audit_logs`**
**Nuevo campo:**
```sql
organization_id CHAR(36)  --  Organización relacionada con la operación
```

---

### 6. **`key_operations`**
**Nuevo campo:**
```sql
organization_id CHAR(36)  --  Organización asociada
FOREIGN KEY (organization_id) REFERENCES organizations(id)
```

---

### 7. **`signing_requests`**
**Nuevo campo:**
```sql
organization_id CHAR(36)  --  Organización que solicita
FOREIGN KEY (organization_id) REFERENCES organizations(id)
```

---

## 🔍 Índices Nuevos

### Organizations:
```sql
idx_organizations_tenant (tenant_id, type)
idx_organizations_parent (parent_id)
idx_organizations_level (level)
idx_organizations_status (tenant_id, status)
```

### Crypto Keys (PKI):
```sql
idx_crypto_keys_owner (owner_type, owner_id)
idx_crypto_keys_parent (parent_key_id)
idx_crypto_keys_hierarchy (tenant_id, cert_level)
```

### Certificates (PKI):
```sql
idx_certificates_owner (owner_type, owner_id)
idx_certificates_issuer_cert (issuer_certificate_id)
idx_certificates_issuer_key (issuer_key_id)
idx_certificates_hierarchy (tenant_id, cert_level)
```

### Audit Logs:
```sql
idx_audit_organization (organization_id, created_at DESC)
```

### Users:
```sql
idx_users_organization (organization_id)
```

---

## 📝 Seeds Actualizados

### Permisos:
```sql
-- Antes: 'department:manage'
-- Después: 'organization:manage'
```

### Roles:
```sql
-- Antes: 'Department Head'
-- Después: 'Organization Manager'
```

### Datos iniciales:
```sql
-- Organización por defecto (tipo DEPARTMENT)
INSERT INTO organizations (id, tenant_id, type, name, level)
VALUES ('...', '...', 'DEPARTMENT', 'Default Department', 0);

-- Usuarios con organization_id
INSERT INTO users (..., organization_id) VALUES (...);
```

---

## Casos de Uso Soportados

### 1. **Jerarquía Simple (Tenant → Usuario)**
```
Tenant (Master Key)
  └─> User (End-entity Key)
```

### 2. **Jerarquía con Departamentos**
```
Tenant (Master Key)
  └─> Department (Intermediate Key)
      ├─> User A (End-entity Key)
      └─> User B (End-entity Key)
```

### 3. **Jerarquía Compleja (Empresa → Sucursales → Departamentos)**
```
Tenant (Master Key)
  └─> Company A (Level 1 Key)
      ├─> Branch 1 (Level 2 Key)
      │   ├─> Dept HR (Level 3 Key)
      │   │   └─> User Alice (Level 4 Key)
      │   └─> Dept IT (Level 3 Key)
      └─> Branch 2 (Level 2 Key)
```

### 4. **Colegio (Institución Educativa)**
```
Tenant (Master Key)
  └─> School "X" (Level 1 Key)
      ├─> Grade 1 (Level 2 Key)
      │   └─> Student John (Level 3 Key)
      └─> Grade 2 (Level 2 Key)
```

---

##  Integridad Referencial

### Claves y Certificados:
- **ON DELETE RESTRICT** para `parent_key_id` - Evita eliminar claves padres con hijos
- **ON DELETE SET NULL** para `issuer_key_id` - Permite auditoría histórica

### Organizaciones:
- **ON DELETE CASCADE** de `parent_id` - Elimina jerarquía completa
- **ON DELETE SET NULL** en usuarios - Usuario sin organización sigue válido

---

## Consultas Útiles

### Obtener jerarquía de organización:
```sql
WITH RECURSIVE org_tree AS (
    SELECT id, tenant_id, parent_id, name, level, type
    FROM organizations
    WHERE id = 'org_id'
    
    UNION ALL
    
    SELECT o.id, o.tenant_id, o.parent_id, o.name, o.level, o.type
    FROM organizations o
    INNER JOIN org_tree t ON o.parent_id = t.id
)
SELECT * FROM org_tree ORDER BY level;
```

### Cadena de certificación:
```sql
WITH RECURSIVE cert_chain AS (
    SELECT id, owner_type, owner_id, issuer_certificate_id, cert_level
    FROM certificates
    WHERE id = 'cert_id'
    
    UNION ALL
    
    SELECT c.id, c.owner_type, c.owner_id, c.issuer_certificate_id, c.cert_level
    FROM certificates c
    INNER JOIN cert_chain cc ON c.id = cc.issuer_certificate_id
)
SELECT * FROM cert_chain ORDER BY cert_level;
```

### Verificar propietario de clave:
```sql
SELECT 
    ck.id,
    ck.name,
    ck.owner_type,
    CASE ck.owner_type
        WHEN 'TENANT' THEN t.name
        WHEN 'ORGANIZATION' THEN o.name
        WHEN 'USER' THEN CONCAT(u.first_name, ' ', u.last_name)
    END AS owner_name
FROM crypto_keys ck
LEFT JOIN tenants t ON ck.owner_type = 'TENANT' AND ck.owner_id = t.id
LEFT JOIN organizations o ON ck.owner_type = 'ORGANIZATION' AND ck.owner_id = o.id
LEFT JOIN users u ON ck.owner_type = 'USER' AND ck.owner_id = u.id
WHERE ck.tenant_id = 'tenant_id';
```

---

## Breaking Changes

1. **Tabla `departments` eliminada** → Usar `organizations`
2. **Campo `department_id` en users** → Ahora es `organization_id`
3. **Permiso `department:manage`** → Ahora es `organization:manage`
4. **Rol `Department Head`** → Ahora es `Organization Manager`

---

## Migración de Datos Existentes

Si tienes datos existentes, ejecuta este script **ANTES** de aplicar la migración:

```sql
-- Backup de departments existentes
CREATE TABLE departments_backup AS SELECT * FROM departments;

-- Migrar departments a organizations
INSERT INTO organizations (id, tenant_id, parent_id, type, name, description, level, status)
SELECT 
    id,
    tenant_id,
    NULL,
    'DEPARTMENT',
    name,
    description,
    0,
    'ACTIVE'
FROM departments_backup;

-- Actualizar users (si la columna aún existe)
-- UPDATE users SET organization_id = department_id WHERE department_id IS NOT NULL;
```

---

## Validación Post-Migración

```sql
-- Verificar estructura de organizations
SELECT COUNT(*) FROM organizations;

-- Verificar usuarios con organizaciones
SELECT COUNT(*) FROM users WHERE organization_id IS NOT NULL;

-- Verificar jerarquía de claves
SELECT owner_type, cert_level, COUNT(*) 
FROM crypto_keys 
GROUP BY owner_type, cert_level;

-- Verificar cadena de certificados
SELECT cert_level, COUNT(*) 
FROM certificates 
GROUP BY cert_level;
```

---

## Referencias

- PKI Hierarchy: [RFC 5280](https://tools.ietf.org/html/rfc5280)
- Polymorphic Associations: [Martin Fowler - PoEAA](https://martinfowler.com/eaaCatalog/classTableInheritance.html)
- Closure Tables: [Bill Karwin - SQL Antipatterns](https://pragprog.com/titles/bksqla/)

---

**Fecha:** 2026-01-14  
**Versión:** 2.0.0  
**Autor:** GitHub Copilot & User

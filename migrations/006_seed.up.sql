USE digsigna;

-- ============================================
-- DATOS INICIALES (SEED)
-- ============================================

-- 1. Permisos globales (no dependen de tenant)
INSERT INTO permissions (code, description, module) VALUES
-- Módulo de Usuario
('user:create', 'Crear nuevos usuarios', 'User'),
('user:read',   'Ver información de usuarios', 'User'),
('user:update', 'Actualizar usuarios', 'User'),
('user:delete', 'Eliminar usuarios', 'User'),
-- Módulo de Departamento
('department:manage', 'Gestionar departamentos', 'Department'),
-- Módulo de HSM y Firma
('hsm:key:generate', 'Generar nuevas claves HSM', 'HSM'),
('document:sign',    'Firmar documentos', 'Document'),
('document:verify',  'Verificar firmas', 'Document'),
-- Módulo de Administración de Tenant
('tenant:configure', 'Configurar parámetros del tenant', 'Tenant'),
('role:assign',      'Asignar roles a usuarios', 'Role')
ON DUPLICATE KEY UPDATE 
    description = VALUES(description),
    module = VALUES(module);

-- 2. Tenant por defecto (debe existir ANTES de crear roles)
INSERT INTO tenants (id, name, contact_email, plan_type, status, hsm_slot, configuration)
VALUES (
    'TEN00000-0000-0000-0000-000000000001',
    'DigSigna Platform',
    'admin@digsigna.com',
    'enterprise',
    'active',
    0,
    '{"max_users": 100, "max_keys": 1000, "features": ["hsm", "audit", "multi_tenant"]}'
) ON DUPLICATE KEY UPDATE 
    name = VALUES(name),
    contact_email = VALUES(contact_email),
    plan_type = VALUES(plan_type),
    status = VALUES(status),
    hsm_slot = VALUES(hsm_slot),
    configuration = VALUES(configuration);

-- 3. Roles para el tenant por defecto (ahora usamos valores fijos)
-- Rol: Tenant Administrator
INSERT INTO roles (id, tenant_id, name, description, is_system_role)
VALUES (
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    'TEN00000-0000-0000-0000-000000000001',
    'Tenant Administrator',
    'Administrador con control total sobre el tenant y sus usuarios.',
    TRUE
) ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    description = VALUES(description);

-- Rol: Department Head  
INSERT INTO roles (id, tenant_id, name, description, is_system_role)
VALUES (
    'b1ffc99-9c0b-4ef8-bb6d-6bb9bd380a22',
    'TEN00000-0000-0000-0000-000000000001',
    'Department Head',
    'Usuario con permisos para gestionar departamentos y sus usuarios.',
    FALSE
) ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    description = VALUES(description);

-- Rol: Signing User
INSERT INTO roles (id, tenant_id, name, description, is_system_role)
VALUES (
    'c2eecc99-9c0b-4ef8-bb6d-6bb9bd380a33',
    'TEN00000-0000-0000-0000-000000000001',
    'Signing User',
    'Usuario estándar que puede firmar y verificar documentos.',
    FALSE
) ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    description = VALUES(description);

-- 4. Asignar permisos a los roles (versión MySQL pura)
-- Para Tenant Administrator: todos los permisos
INSERT INTO role_permissions (role_id, permission_id)
SELECT 
    r.id,
    p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'Tenant Administrator' 
    AND r.tenant_id = 'TEN00000-0000-0000-0000-000000000001'
ON DUPLICATE KEY UPDATE role_id = VALUES(role_id);

-- Para Department Head: permisos específicos
INSERT INTO role_permissions (role_id, permission_id)
SELECT 
    r.id,
    p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'Department Head' 
    AND r.tenant_id = 'TEN00000-0000-0000-0000-000000000001'
    AND p.code IN ('department:manage', 'user:read', 'user:create', 'user:update', 'document:sign', 'document:verify')
ON DUPLICATE KEY UPDATE role_id = VALUES(role_id);

-- Para Signing User: permisos básicos
INSERT INTO role_permissions (role_id, permission_id)
SELECT 
    r.id,
    p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'Signing User' 
    AND r.tenant_id = 'TEN00000-0000-0000-0000-000000000001'
    AND p.code IN ('document:sign', 'document:verify', 'user:read')
ON DUPLICATE KEY UPDATE role_id = VALUES(role_id);

-- 5. Departamento por defecto
INSERT INTO departments (id, tenant_id, name, description)
VALUES (
    'DEP00000-0000-0000-0000-000000000001',
    'TEN00000-0000-0000-0000-000000000001',
    'Default Department',
    'Departamento predeterminado para usuarios sin asignación específica.'
) ON DUPLICATE KEY UPDATE 
    name = VALUES(name),
    description = VALUES(description);

-- 6. Usuario tenant administrador
INSERT INTO users (
    id, tenant_id, email, password_hash, 
    first_name, last_name, status, mfa_enabled
)
VALUES (
    'USR00000-0000-0000-0000-000000000001',
    'TEN00000-0000-0000-0000-000000000001',
    'admin@digsigna.com',
    -- Contraseña: 'Admin123!' (bcrypt)
    '$2a$10$N9qo8uLOickgx2ZMRZoMye3Y6l7dFg7/7gZ8J5J5J5J5J5J5J5J5J5',
    'System',
    'Administrator',
    'ACTIVE',
    FALSE
) ON DUPLICATE KEY UPDATE 
    email = VALUES(email),
    first_name = VALUES(first_name),
    last_name = VALUES(last_name),
    status = VALUES(status);

-- 7. Asignar rol de Tenant Administrator al usuario administrador
INSERT INTO user_roles (user_id, role_id)
VALUES (
    'USR00000-0000-0000-0000-000000000001',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'
) ON DUPLICATE KEY UPDATE
    user_id = VALUES(user_id);

-- 8. Usuario Jefe de Departamento
INSERT INTO users (
    id, tenant_id, email, password_hash, 
    first_name, last_name, status, mfa_enabled, department_id
)
VALUES (
    'USR00000-0000-0000-0000-000000000002',
    'TEN00000-0000-0000-0000-000000000001',
    'admindep@signa.com',
    -- Contraseña: 'Admin123!' (bcrypt)
    '$2a$10$N9qo8uLOickgx2ZMRZoMye3Y6l7dFg7/7gZ8J5J5J5J5J5J5J5J5J5',
    'Department',
    'Administrator',
    'ACTIVE',
    FALSE,
    'DEP00000-0000-0000-0000-000000000001'
) ON DUPLICATE KEY UPDATE 
    email = VALUES(email),
    first_name = VALUES(first_name),
    last_name = VALUES(last_name),
    department_id = VALUES(department_id);

-- 9. Asignar rol de Department Head al usuario jefe de departamento
INSERT INTO user_roles (user_id, role_id)
VALUES (
    'USR00000-0000-0000-0000-000000000002',
    'b1ffc99-9c0b-4ef8-bb6d-6bb9bd380a22'
) ON DUPLICATE KEY UPDATE
    user_id = VALUES(user_id);

-- 10. Usuario Signing User (sin departamento asignado - ejemplo flat hierarchy)
INSERT INTO users (
    id, tenant_id, email, password_hash, 
    first_name, last_name, status, mfa_enabled
)
VALUES (
    'USR00000-0000-0000-0000-000000000003',
    'TEN00000-0000-0000-0000-000000000001',
    'signer@example.com',
    -- Contraseña: 'User123!' (bcrypt)
    '$2a$10$N9qo8uLOickgx2ZMRZoMye3Y6l7dFg7/7gZ8J5J5J5J5J5J5J5J5J5',
    'John',
    'Signer',
    'ACTIVE',
    FALSE
) ON DUPLICATE KEY UPDATE 
    email = VALUES(email),
    first_name = VALUES(first_name),
    last_name = VALUES(last_name);

-- 11. Asignar rol de Signing User
INSERT INTO user_roles (user_id, role_id)
VALUES (
    'USR00000-0000-0000-0000-000000000003',
    'c2eecc99-9c0b-4ef8-bb6d-6bb9bd380a33'
) ON DUPLICATE KEY UPDATE
    user_id = VALUES(user_id);
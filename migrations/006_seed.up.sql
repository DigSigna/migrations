USE digsigna;

-- ============================================
-- DATOS INICIALES (SEED)
-- ============================================

-- Tenant por defecto
INSERT INTO tenants (id, name, contact_email, plan_type, status, configuration)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'DigSigna Platform',
    'admin@digsigna.com',
    'enterprise',
    'active',
    '{"max_users": 100, "max_keys": 1000, "features": ["hsm", "audit", "multi_tenant"]}'
) ON DUPLICATE KEY UPDATE 
    name = VALUES(name),
    contact_email = VALUES(contact_email),
    plan_type = VALUES(plan_type),
    status = VALUES(status),
    configuration = VALUES(configuration);

-- Usuario administrador
INSERT INTO users (
    id, tenant_id, email, password_hash, 
    first_name, last_name, role, status, mfa_enabled
)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    'admin@digsigna.com',
    -- Contraseña: 'Admin123!' (bcrypt)
    '$2a$10$N9qo8uLOickgx2ZMRZoMye3Y6l7dFg7/7gZ8J5J5J5J5J5J5J5J5J5',
    'System',
    'Administrator',
    'SUPER_ADMIN',
    'ACTIVE',
    FALSE
) ON DUPLICATE KEY UPDATE 
    email = VALUES(email),
    first_name = VALUES(first_name),
    last_name = VALUES(last_name),
    role = VALUES(role);
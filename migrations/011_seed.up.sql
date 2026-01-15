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
-- Módulo de Organización
('organization:manage', 'Gestionar organizaciones', 'Organization'),
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

-- 2. Tenant Platform (MANAGED - modo=MANAGED, hsm_slot=0)
INSERT INTO tenants (id, name, contact_email, mode, plan_type, status, hsm_slot, parent_tenant_id, configuration)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'DigSigna Platform',
    'admin@digsigna.com',
    'MANAGED',
    'enterprise',
    'active',
    0,
    NULL,  -- Es el tenant raíz
    '{"max_users": -1, "max_keys": -1, "features": ["hsm", "audit", "multi_tenant", "pki_hierarchy"]}'
) ON DUPLICATE KEY UPDATE 
    name = VALUES(name),
    contact_email = VALUES(contact_email),
    mode = VALUES(mode),
    plan_type = VALUES(plan_type),
    status = VALUES(status),
    hsm_slot = VALUES(hsm_slot),
    configuration = VALUES(configuration);

-- 3. Roles para el tenant por defecto (ahora usamos valores fijos)
-- Rol: Tenant Administrator
INSERT INTO roles (id, tenant_id, name, description, is_system_role)
VALUES (
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    '00000000-0000-0000-0000-000000000001',
    'Tenant Administrator',
    'Administrador con control total sobre el tenant y sus usuarios.',
    TRUE
) ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    description = VALUES(description);

-- Rol: Organization Manager
INSERT INTO roles (id, tenant_id, name, description, is_system_role)
VALUES (
    'b1ffc99-9c0b-4ef8-bb6d-6bb9bd380a22',
    '00000000-0000-0000-0000-000000000001',
    'Organization Manager',
    'Usuario con permisos para gestionar organizaciones y sus usuarios.',
    FALSE
) ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    description = VALUES(description);

-- Rol: Signing User
INSERT INTO roles (id, tenant_id, name, description, is_system_role)
VALUES (
    'c2eecc99-9c0b-4ef8-bb6d-6bb9bd380a33',
    '00000000-0000-0000-0000-000000000001',
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
    AND r.tenant_id = '00000000-0000-0000-0000-000000000001'
ON DUPLICATE KEY UPDATE role_id = VALUES(role_id);

-- Para Organization Manager: permisos específicos
INSERT INTO role_permissions (role_id, permission_id)
SELECT 
    r.id,
    p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'Organization Manager' 
    AND r.tenant_id = '00000000-0000-0000-0000-000000000001'
    AND p.code IN ('organization:manage', 'user:read', 'user:create', 'user:update', 'document:sign', 'document:verify')
ON DUPLICATE KEY UPDATE role_id = VALUES(role_id);

-- Para Signing User: permisos básicos
INSERT INTO role_permissions (role_id, permission_id)
SELECT 
    r.id,
    p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.name = 'Signing User' 
    AND r.tenant_id = '00000000-0000-0000-0000-000000000001'
    AND p.code IN ('document:sign', 'document:verify', 'user:read')
ON DUPLICATE KEY UPDATE role_id = VALUES(role_id);

-- 5. Organización por defecto (tipo DEPARTMENT)
INSERT INTO organizations (id, tenant_id, parent_id, type, name, legal_name, description, level, status)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    NULL,
    'DEPARTMENT',
    'Default Department',
    'Default Department',
    'Organización predeterminada para usuarios sin asignación específica.',
    0,
    'ACTIVE'
) ON DUPLICATE KEY UPDATE 
    name = VALUES(name),
    description = VALUES(description);

-- 6. Usuario tenant administrador
INSERT INTO users (
    id, tenant_id, email, password_hash, 
    first_name, last_name, status, mfa_enabled
)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
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
    '00000000-0000-0000-0000-000000000001',
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11'
) ON DUPLICATE KEY UPDATE
    user_id = VALUES(user_id);

-- 8. Usuario Gestor de Organización
INSERT INTO users (
    id, tenant_id, organization_id, email, password_hash, 
    first_name, last_name, status, mfa_enabled
)
VALUES (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    'admindep@signa.com',
    -- Contraseña: 'Admin123!' (bcrypt)
    '$2a$10$N9qo8uLOickgx2ZMRZoMye3Y6l7dFg7/7gZ8J5J5J5J5J5J5J5J5J5',
    'Organization',
    'Manager',
    'ACTIVE',
    FALSE
) ON DUPLICATE KEY UPDATE 
    email = VALUES(email),
    first_name = VALUES(first_name),
    last_name = VALUES(last_name),
    organization_id = VALUES(organization_id);

-- 9. Asignar rol de Organization Manager al usuario gestor
INSERT INTO user_roles (user_id, role_id)
VALUES (
    '00000000-0000-0000-0000-000000000002',
    'b1ffc99-9c0b-4ef8-bb6d-6bb9bd380a22'
) ON DUPLICATE KEY UPDATE
    user_id = VALUES(user_id);

-- 10. Usuario Signing User (sin organización asignada - ejemplo flat hierarchy)
INSERT INTO users (
    id, tenant_id, email, password_hash, 
    first_name, last_name, status, mfa_enabled
)
VALUES (
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000001',
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
    '00000000-0000-0000-0000-000000000003',
    'c2eecc99-9c0b-4ef8-bb6d-6bb9bd380a33'
) ON DUPLICATE KEY UPDATE
    user_id = VALUES(user_id);
-- ============================================
-- 12. CUOTAS DEL TENANT POR DEFECTO (Enterprise)
-- ============================================
INSERT INTO tenant_quotas (tenant_id, quota_type, max_limit, warning_threshold, reset_period)
VALUES 
    -- Sin l�mites para plan enterprise
    ('00000000-0000-0000-0000-000000000001', 'USERS', -1, 0, 'NONE'),
    ('00000000-0000-0000-0000-000000000001', 'KEYS', -1, 0, 'NONE'),
    ('00000000-0000-0000-0000-000000000001', 'SIGNATURES', -1, 0, 'NONE'),
    ('00000000-0000-0000-0000-000000000001', 'VERIFICATIONS', -1, 0, 'NONE'),
    ('00000000-0000-0000-0000-000000000001', 'STORAGE_MB', -1, 0, 'NONE'),
    ('00000000-0000-0000-0000-000000000001', 'API_CALLS', -1, 0, 'NONE'),
    ('00000000-0000-0000-0000-000000000001', 'CERTIFICATES', -1, 0, 'NONE')
ON DUPLICATE KEY UPDATE
    max_limit = VALUES(max_limit),
    warning_threshold = VALUES(warning_threshold),
    reset_period = VALUES(reset_period);

-- ============================================
-- 13. INICIALIZAR CONTADORES DE USO
-- ============================================
INSERT INTO tenant_usage (tenant_id, quota_type, current_usage, period_usage)
VALUES 
    ('00000000-0000-0000-0000-000000000001', 'USERS', 3, 3),           -- 3 usuarios creados
    ('00000000-0000-0000-0000-000000000001', 'KEYS', 0, 0),
    ('00000000-0000-0000-0000-000000000001', 'SIGNATURES', 0, 0),
    ('00000000-0000-0000-0000-000000000001', 'VERIFICATIONS', 0, 0),
    ('00000000-0000-0000-0000-000000000001', 'STORAGE_MB', 0, 0),
    ('00000000-0000-0000-0000-000000000001', 'API_CALLS', 0, 0),
    ('00000000-0000-0000-0000-000000000001', 'CERTIFICATES', 0, 0)
ON DUPLICATE KEY UPDATE
    current_usage = VALUES(current_usage),
    period_usage = VALUES(period_usage);

-- ============================================
-- PLANES DE SUSCRIPCIÓN
-- ============================================

-- 14. Plan FREE (Prueba básica)
INSERT INTO plans (
    id, code, name, plan_type, target_audience,
    price, currency, billing_period, trial_days,
    max_users, max_keys, max_signatures, max_storage_mb, max_api_calls, max_certificates,
    features, is_active, is_public, description
)
VALUES (
    '10000000-1000-1000-1000-000000000001',
    'FREE',
    'Plan Gratuito',
    'FREE',
    'SMALL_BUSINESS',
    0.00,
    'MXN',
    'MONTHLY',
    0,
    5,      -- max_users
    10,     -- max_keys
    100,    -- max_signatures/mes
    100,    -- max_storage_mb
    1000,   -- max_api_calls/mes
    10,     -- max_certificates
    '{"audit_retention_days": 30, "support": "community", "sla": "none"}',
    TRUE,
    TRUE,
    'Plan gratuito ideal para pruebas y proyectos pequeños'
) ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    price = VALUES(price);

-- 15. Plan BASIC (Pequeñas empresas)
INSERT INTO plans (
    id, code, name, plan_type, target_audience,
    price, currency, billing_period, trial_days,
    max_users, max_keys, max_signatures, max_storage_mb, max_api_calls, max_certificates,
    features, is_active, is_public, description
)
VALUES (
    '10000000-1000-1000-1000-000000000002',
    'BASIC',
    'Plan Básico',
    'PAID',
    'SMALL_BUSINESS',
    1499.00,
    'MXN',
    'MONTHLY',
    14,
    25,     -- max_users
    50,     -- max_keys
    1000,   -- max_signatures/mes
    500,    -- max_storage_mb
    10000,  -- max_api_calls/mes
    50,     -- max_certificates
    '{"audit_retention_days": 90, "support": "email", "sla": "standard", "custom_branding": false}',
    TRUE,
    TRUE,
    'Plan básico para pequeñas empresas con necesidades moderadas de firma'
) ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    price = VALUES(price);

-- 16. Plan PROFESSIONAL (Empresas medianas)
INSERT INTO plans (
    id, code, name, plan_type, target_audience,
    price, currency, billing_period, trial_days,
    max_users, max_keys, max_signatures, max_storage_mb, max_api_calls, max_certificates,
    features, is_active, is_public, description
)
VALUES (
    '10000000-1000-1000-1000-000000000003',
    'PROFESSIONAL',
    'Plan Profesional',
    'PAID',
    'SMALL_BUSINESS',
    5999.00,
    'MXN',
    'MONTHLY',
    30,
    100,    -- max_users
    500,    -- max_keys
    10000,  -- max_signatures/mes
    5000,   -- max_storage_mb (5GB)
    100000, -- max_api_calls/mes
    200,    -- max_certificates
    '{"audit_retention_days": 365, "support": "priority", "sla": "business", "custom_branding": true, "api_access": true, "webhooks": true}',
    TRUE,
    TRUE,
    'Plan profesional con soporte prioritario y funciones avanzadas'
) ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    price = VALUES(price);

-- 17. Plan ENTERPRISE (Grandes organizaciones)
INSERT INTO plans (
    id, code, name, plan_type, target_audience,
    price, currency, billing_period, trial_days,
    max_users, max_keys, max_signatures, max_storage_mb, max_api_calls, max_certificates,
    features, is_active, is_public, description
)
VALUES (
    '10000000-1000-1000-1000-000000000004',
    'ENTERPRISE',
    'Plan Enterprise',
    'PAID',
    'ENTERPRISE',
    24999.00,
    'MXN',
    'MONTHLY',
    30,
    -1,     -- ilimitados
    -1,     -- ilimitados
    -1,     -- ilimitadas
    -1,     -- ilimitado
    -1,     -- ilimitadas
    -1,     -- ilimitados
    '{"audit_retention_days": -1, "support": "24/7", "sla": "enterprise", "custom_branding": true, "api_access": true, "webhooks": true, "dedicated_hsm": false, "custom_integrations": true}',
    TRUE,
    TRUE,
    'Plan enterprise con recursos ilimitados y soporte 24/7'
) ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    price = VALUES(price);

-- 18. Plan WHITE_LABEL (Revendedores)
INSERT INTO plans (
    id, code, name, plan_type, target_audience,
    price, currency, billing_period, trial_days,
    max_users, max_keys, max_signatures, max_storage_mb, max_api_calls, max_certificates,
    features, is_active, is_public, description
)
VALUES (
    '10000000-1000-1000-1000-000000000005',
    'WHITE_LABEL',
    'Plan White Label',
    'PAID',
    'RESELLER',
    49999.00,
    'MXN',
    'MONTHLY',
    0,
    -1,     -- ilimitados
    -1,     -- ilimitados
    -1,     -- ilimitadas
    -1,     -- ilimitado
    -1,     -- ilimitadas
    -1,     -- ilimitados
    '{"audit_retention_days": -1, "support": "dedicated", "sla": "premium", "custom_branding": true, "api_access": true, "webhooks": true, "dedicated_hsm": true, "white_label": true, "custom_integrations": true, "reseller_portal": true}',
    TRUE,
    FALSE,  -- No público, requiere contacto
    'Plan White Label para revendedores con marca propia y HSM dedicado'
) ON DUPLICATE KEY UPDATE
    name = VALUES(name),
    price = VALUES(price);

-- ============================================
-- EJEMPLO: MUNICIPIO DE CELAYA
-- ============================================

-- 19. Tenant: Municipio de Celaya (MANAGED mode)
INSERT INTO tenants (
    id, name, contact_email, mode, plan_type, status, 
    hsm_slot, parent_tenant_id, configuration
)
VALUES (
    '20000000-2000-2000-2000-000000000001',
    'Municipio de Celaya',
    'sistemas@celaya.gob.mx',
    'MANAGED',
    'professional',
    'active',
    0,  -- MANAGED usa slot compartido 0
    NULL,
    '{"timezone": "America/Mexico_City", "locale": "es_MX", "logo_url": "https://celaya.gob.mx/logo.png"}'
) ON DUPLICATE KEY UPDATE 
    name = VALUES(name),
    contact_email = VALUES(contact_email);

-- 20. Suscripción activa para Celaya (Plan Professional)
INSERT INTO tenant_subscriptions (
    id, tenant_id, plan_id, status,
    started_at, trial_ends_at, current_period_start, current_period_end,
    next_billing_date, auto_renew,
    custom_max_users, custom_max_keys, custom_max_signatures
)
VALUES (
    '30000000-3000-3000-3000-000000000001',
    '20000000-2000-2000-2000-000000000001',  -- Celaya
    '10000000-1000-1000-1000-000000000003',  -- Plan Professional
    'ACTIVE',
    '2025-12-01 00:00:00',
    '2025-12-31 23:59:59',  -- Trial de 30 días
    '2026-01-01 00:00:00',  -- Primer periodo de pago
    '2026-01-31 23:59:59',
    '2026-02-01 00:00:00',
    TRUE,
    NULL,  -- Usa límites del plan
    NULL,
    NULL
) ON DUPLICATE KEY UPDATE
    status = VALUES(status);

-- 21. Historial de suscripción - Creación
INSERT INTO subscription_history (
    tenant_id, subscription_id, event_type,
    from_plan_id, to_plan_id, reason, performed_by,
    before_state, after_state
)
VALUES (
    '20000000-2000-2000-2000-000000000001',
    '30000000-3000-3000-3000-000000000001',
    'CREATED',
    NULL,
    '10000000-1000-1000-1000-000000000003',  -- Professional
    'Suscripción inicial durante periodo de prueba',
    '00000000-0000-0000-0000-000000000001',  -- Admin platform
    NULL,
    '{"status": "TRIALING", "plan": "PROFESSIONAL"}'
) ON DUPLICATE KEY UPDATE
    event_type = VALUES(event_type);

-- 22. Historial de suscripción - Activación post-trial
INSERT INTO subscription_history (
    tenant_id, subscription_id, event_type,
    from_plan_id, to_plan_id, reason, performed_by,
    before_state, after_state
)
VALUES (
    '20000000-2000-2000-2000-000000000001',
    '30000000-3000-3000-3000-000000000001',
    'RENEWED',
    '10000000-1000-1000-1000-000000000003',
    '10000000-1000-1000-1000-000000000003',
    'Fin del periodo de prueba - Activación de pago',
    '00000000-0000-0000-0000-000000000001',
    '{"status": "TRIALING", "trial_ends_at": "2025-12-31"}',
    '{"status": "ACTIVE", "current_period_start": "2026-01-01"}'
) ON DUPLICATE KEY UPDATE
    event_type = VALUES(event_type);

-- 23. Factura de Enero 2026 (PAGADA)
INSERT INTO invoices (
    id, tenant_id, subscription_id, invoice_number,
    subtotal, tax, discount, total, currency,
    status, issued_at, due_date, paid_at,
    billing_name, billing_email, billing_address, tax_id,
    line_items, notes
)
VALUES (
    '40000000-4000-4000-4000-000000000001',
    '20000000-2000-2000-2000-000000000001',
    '30000000-3000-3000-3000-000000000001',
    'INV-CEL-2026-0001',
    5999.00,
    959.84,   -- 16% IVA
    0.00,
    6958.84,
    'MXN',
    'PAID',
    '2026-01-01 09:00:00',
    '2026-01-15 23:59:59',
    '2026-01-05 14:23:45',
    'Municipio de Celaya',
    'tesoreria@celaya.gob.mx',
    'Plaza de Armas S/N, Centro, 38000 Celaya, Guanajuato',
    'MCE-870101-AA1',
    '[{"description": "Plan Profesional - Enero 2026", "quantity": 1, "unit_price": 5999.00, "total": 5999.00}]',
    'Pago correspondiente al periodo 2026-01-01 al 2026-01-31'
) ON DUPLICATE KEY UPDATE
    status = VALUES(status);

-- 24. Pago de la factura (STRIPE - COMPLETADO)
INSERT INTO payments (
    id, tenant_id, invoice_id, amount, currency,
    payment_method, payment_gateway, transaction_id,
    status, processed_at, payment_details
)
VALUES (
    '50000000-5000-5000-5000-000000000001',
    '20000000-2000-2000-2000-000000000001',
    '40000000-4000-4000-4000-000000000001',
    6958.84,
    'MXN',
    'CREDIT_CARD',
    'STRIPE',
    'ch_3QXwZy2eZvKYlo2C1p4F5K6m',
    'COMPLETED',
    '2026-01-05 14:23:45',
    '{"card_brand": "visa", "card_last4": "4242", "receipt_url": "https://pay.stripe.com/receipts/xxx"}'
) ON DUPLICATE KEY UPDATE
    status = VALUES(status);

-- 25. Organización: Municipio de Celaya (nivel 0 - MUNICIPALITY)
INSERT INTO organizations (
    id, tenant_id, parent_id, type, name, legal_name,
    tax_id, country_code, billing_email, description, level, status
)
VALUES (
    '20000000-2000-2000-2000-000000000011',
    '20000000-2000-2000-2000-000000000001',
    NULL,  -- Es el nivel raíz
    'MUNICIPALITY',
    'Celaya',
    'Municipio de Celaya',
    'MCE-870101-AA1',
    'MX',
    'tesoreria@celaya.gob.mx',
    'Gobierno Municipal de Celaya, Guanajuato',
    0,
    'ACTIVE'
) ON DUPLICATE KEY UPDATE 
    name = VALUES(name);

-- 26. Organización: Desarrollo Urbano (nivel 1 - DEPARTMENT, hijo de Celaya)
INSERT INTO organizations (
    id, tenant_id, parent_id, type, name, legal_name,
    tax_id, country_code, billing_email, description, level, status
)
VALUES (
    '20000000-2000-2000-2000-000000000012',
    '20000000-2000-2000-2000-000000000001',
    '20000000-2000-2000-2000-000000000011',  -- Parent: Celaya
    'DEPARTMENT',
    'Desarrollo Urbano',
    'Dirección de Desarrollo Urbano - Municipio de Celaya',
    'MCE-870101-AA1',  -- Mismo RFC que el municipio
    'MX',
    'urbano@celaya.gob.mx',
    'Dirección encargada de permisos de construcción, licencias y planeación urbana',
    1,
    'ACTIVE'
) ON DUPLICATE KEY UPDATE 
    name = VALUES(name);

-- 27. Usuario Admin de Celaya (Organization Manager del municipio)
INSERT INTO users (
    id, tenant_id, organization_id, email, password_hash, 
    first_name, last_name, status, mfa_enabled
)
VALUES (
    '20000000-2000-2000-2000-000000000101',
    '20000000-2000-2000-2000-000000000001',
    '20000000-2000-2000-2000-000000000011',  -- Celaya
    'admin@celaya.gob.mx',
    '$2a$10$N9qo8uLOickgx2ZMRZoMye3Y6l7dFg7/7gZ8J5J5J5J5J5J5J5J5J5',
    'María',
    'González Hernández',
    'ACTIVE',
    TRUE
) ON DUPLICATE KEY UPDATE 
    email = VALUES(email);

-- 28. Asignar rol Organization Manager al admin de Celaya
INSERT INTO user_roles (user_id, role_id)
VALUES (
    '20000000-2000-2000-2000-000000000101',
    'b1ffc99-9c0b-4ef8-bb6d-6bb9bd380a22'  -- Organization Manager
) ON DUPLICATE KEY UPDATE
    user_id = VALUES(user_id);

-- 29. Usuario: Director de Desarrollo Urbano
INSERT INTO users (
    id, tenant_id, organization_id, email, password_hash, 
    first_name, last_name, status, mfa_enabled
)
VALUES (
    '20000000-2000-2000-2000-000000000102',
    '20000000-2000-2000-2000-000000000001',
    '20000000-2000-2000-2000-000000000012',  -- Desarrollo Urbano
    'director.urbano@celaya.gob.mx',
    '$2a$10$N9qo8uLOickgx2ZMRZoMye3Y6l7dFg7/7gZ8J5J5J5J5J5J5J5J5J5',
    'Carlos',
    'Ramírez López',
    'ACTIVE',
    TRUE
) ON DUPLICATE KEY UPDATE 
    email = VALUES(email);

-- 30. Asignar rol Organization Manager al director de Desarrollo Urbano
INSERT INTO user_roles (user_id, role_id)
VALUES (
    '20000000-2000-2000-2000-000000000102',
    'b1ffc99-9c0b-4ef8-bb6d-6bb9bd380a22'  -- Organization Manager
) ON DUPLICATE KEY UPDATE
    user_id = VALUES(user_id);

-- 31. Usuario: Encargado de permisos (Signing User)
INSERT INTO users (
    id, tenant_id, organization_id, email, password_hash, 
    first_name, last_name, status, mfa_enabled
)
VALUES (
    '20000000-2000-2000-2000-000000000103',
    '20000000-2000-2000-2000-000000000001',
    '20000000-2000-2000-2000-000000000012',  -- Desarrollo Urbano
    'permisos@celaya.gob.mx',
    '$2a$10$N9qo8uLOickgx2ZMRZoMye3Y6l7dFg7/7gZ8J5J5J5J5J5J5J5J5J5',
    'Ana',
    'Martínez García',
    'ACTIVE',
    FALSE
) ON DUPLICATE KEY UPDATE 
    email = VALUES(email);

-- 32. Asignar rol Signing User
INSERT INTO user_roles (user_id, role_id)
VALUES (
    '20000000-2000-2000-2000-000000000103',
    'c2eecc99-9c0b-4ef8-bb6d-6bb9bd380a33'  -- Signing User
) ON DUPLICATE KEY UPDATE
    user_id = VALUES(user_id);

-- 33. Usuario: Asistente administrativo (Signing User)
INSERT INTO users (
    id, tenant_id, organization_id, email, password_hash, 
    first_name, last_name, status, mfa_enabled
)
VALUES (
    '20000000-2000-2000-2000-000000000104',
    '20000000-2000-2000-2000-000000000001',
    '20000000-2000-2000-2000-000000000012',  -- Desarrollo Urbano
    'asistente.urbano@celaya.gob.mx',
    '$2a$10$N9qo8uLOickgx2ZMRZoMye3Y6l7dFg7/7gZ8J5J5J5J5J5J5J5J5J5',
    'Luis',
    'Pérez Moreno',
    'ACTIVE',
    FALSE
) ON DUPLICATE KEY UPDATE 
    email = VALUES(email);

-- 34. Asignar rol Signing User
INSERT INTO user_roles (user_id, role_id)
VALUES (
    '20000000-2000-2000-2000-000000000104',
    'c2eecc99-9c0b-4ef8-bb6d-6bb9bd380a33'  -- Signing User
) ON DUPLICATE KEY UPDATE
    user_id = VALUES(user_id);

-- 35. Cuotas para Celaya (Plan Professional)
INSERT INTO tenant_quotas (tenant_id, quota_type, max_limit, warning_threshold, reset_period)
VALUES 
    ('20000000-2000-2000-2000-000000000001', 'USERS', 100, 90, 'NONE'),
    ('20000000-2000-2000-2000-000000000001', 'KEYS', 500, 450, 'NONE'),
    ('20000000-2000-2000-2000-000000000001', 'SIGNATURES', 10000, 9000, 'MONTHLY'),
    ('20000000-2000-2000-2000-000000000001', 'VERIFICATIONS', 10000, 9000, 'MONTHLY'),
    ('20000000-2000-2000-2000-000000000001', 'STORAGE_MB', 5000, 4500, 'NONE'),
    ('20000000-2000-2000-2000-000000000001', 'API_CALLS', 100000, 90000, 'MONTHLY'),
    ('20000000-2000-2000-2000-000000000001', 'CERTIFICATES', 200, 180, 'NONE')
ON DUPLICATE KEY UPDATE
    max_limit = VALUES(max_limit);

-- 36. Uso actual de Celaya (datos de ejemplo)
INSERT INTO tenant_usage (tenant_id, quota_type, current_usage, period_usage, last_reset_at)
VALUES 
    ('20000000-2000-2000-2000-000000000001', 'USERS', 4, 4, NULL),              -- 4 usuarios creados
    ('20000000-2000-2000-2000-000000000001', 'KEYS', 8, 8, NULL),               -- 8 claves generadas
    ('20000000-2000-2000-2000-000000000001', 'SIGNATURES', 127, 127, '2026-01-01'),  -- 127 firmas en enero
    ('20000000-2000-2000-2000-000000000001', 'VERIFICATIONS', 89, 89, '2026-01-01'), -- 89 verificaciones
    ('20000000-2000-2000-2000-000000000001', 'STORAGE_MB', 234, 234, NULL),     -- 234 MB usados
    ('20000000-2000-2000-2000-000000000001', 'API_CALLS', 1842, 1842, '2026-01-01'), -- 1,842 llamadas API
    ('20000000-2000-2000-2000-000000000001', 'CERTIFICATES', 8, 8, NULL)        -- 8 certificados
ON DUPLICATE KEY UPDATE
    current_usage = VALUES(current_usage),
    period_usage = VALUES(period_usage);

-- 37. Historial de uso - Evento inicial de activación
INSERT INTO tenant_usage_history (
    tenant_id, quota_type, change_type, change_amount, 
    previous_usage, new_usage, reference_type, reference_id, reason
)
VALUES 
    ('20000000-2000-2000-2000-000000000001', 'USERS', 'INCREMENT', 4, 0, 4, 
     'USER', '20000000-2000-2000-2000-000000000104', 'Creación inicial de usuarios del municipio'),
    ('20000000-2000-2000-2000-000000000001', 'KEYS', 'INCREMENT', 8, 0, 8, 
     'KEY', NULL, 'Generación de claves iniciales para departamentos'),
    ('20000000-2000-2000-2000-000000000001', 'SIGNATURES', 'INCREMENT', 127, 0, 127, 
     'SIGNATURE', NULL, 'Firmas de permisos de construcción - Enero 2026'),
    ('20000000-2000-2000-2000-000000000001', 'CERTIFICATES', 'INCREMENT', 8, 0, 8, 
     'CERTIFICATE', NULL, 'Emisión de certificados para departamentos')
ON DUPLICATE KEY UPDATE
    new_usage = VALUES(new_usage);

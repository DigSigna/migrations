USE digsigna;

-- Eliminar en orden inverso (dependencias)

-- Eliminar contadores de uso
DELETE FROM tenant_usage 
WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

-- Eliminar cuotas
DELETE FROM tenant_quotas 
WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

-- Eliminar roles de usuarios
DELETE FROM user_roles 
WHERE user_id IN (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000003'
);

-- Eliminar usuarios
DELETE FROM users 
WHERE id IN (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000003'
);

-- Eliminar departamento
DELETE FROM departments 
WHERE id = '00000000-0000-0000-0000-000000000001';

-- Eliminar permisos de roles
DELETE FROM role_permissions;

-- Eliminar roles
DELETE FROM roles 
WHERE tenant_id = '00000000-0000-0000-0000-000000000001';

-- Eliminar tenant
DELETE FROM tenants 
WHERE id = '00000000-0000-0000-0000-000000000001';

-- Eliminar permisos
DELETE FROM permissions;

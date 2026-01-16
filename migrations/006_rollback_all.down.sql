-- ============================================
-- ROLLBACK: Eliminar todas las tablas
-- ============================================

SET FOREIGN_KEY_CHECKS = 0;

USE digsigna;

-- Eliminar triggers
DROP TRIGGER IF EXISTS trg_validate_certificate_hierarchy_before_insert;
DROP TRIGGER IF EXISTS trg_validate_certificate_hierarchy_before_update;
DROP TRIGGER IF EXISTS trg_prevent_delete_ca_with_children;
DROP TRIGGER IF EXISTS trg_validate_crypto_key_before_insert;
DROP TRIGGER IF EXISTS trg_validate_organization_for_key;
DROP TRIGGER IF EXISTS trg_prevent_delete_key_with_children;

-- Eliminar tablas en orden inverso
DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS invoices;
DROP TABLE IF EXISTS subscription_history;
DROP TABLE IF EXISTS tenant_subscriptions;
DROP TABLE IF EXISTS plan_features;
DROP TABLE IF EXISTS plans;
DROP TABLE IF EXISTS tenant_usage_history;
DROP TABLE IF EXISTS tenant_usage;
DROP TABLE IF EXISTS tenant_quotas;
DROP TABLE IF EXISTS audit_metadata;
DROP TABLE IF EXISTS audit_logs;
DROP TABLE IF EXISTS verifications;
DROP TABLE IF EXISTS signatures;
DROP TABLE IF EXISTS signing_requests;
DROP TABLE IF EXISTS certificates;
DROP TABLE IF EXISTS key_permissions_cache;
DROP TABLE IF EXISTS key_permissions;
DROP TABLE IF EXISTS key_operations;
DROP TABLE IF EXISTS key_metadata;
DROP TABLE IF EXISTS crypto_keys;
DROP TABLE IF EXISTS identity_documents;
DROP TABLE IF EXISTS user_sessions;
DROP TABLE IF EXISTS user_permissions;
DROP TABLE IF EXISTS user_roles;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS role_permissions;
DROP TABLE IF EXISTS permissions;
DROP TABLE IF EXISTS roles;
DROP TABLE IF EXISTS organizations;
DROP TABLE IF EXISTS tenants;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Todas las tablas eliminadas correctamente' AS message;

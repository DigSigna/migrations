USE digsigna;

-- ============================================
-- ROLLBACK: Eliminar tablas de consumo
-- ============================================

-- Orden inverso por Foreign Keys
DROP TABLE IF EXISTS tenant_usage_history;
DROP TABLE IF EXISTS tenant_usage;
DROP TABLE IF EXISTS tenant_quotas;

USE digsigna;

-- ============================================
-- VISTAS ÚTILES
-- ============================================

-- Vista: Claves activas por tenant
CREATE OR REPLACE VIEW vw_active_keys AS
SELECT 
    t.id AS tenant_id,
    t.name AS tenant_name,
    COUNT(ck.id) AS total_keys,
    SUM(CASE WHEN ck.algorithm = 'RSA' THEN 1 ELSE 0 END) AS rsa_keys,
    SUM(CASE WHEN ck.algorithm = 'ECC' THEN 1 ELSE 0 END) AS ecc_keys,
    SUM(CASE WHEN ck.purpose = 'SIGNING' THEN 1 ELSE 0 END) AS signing_keys,
    SUM(CASE WHEN ck.purpose = 'ENCRYPTION' THEN 1 ELSE 0 END) AS encryption_keys
FROM tenants t
LEFT JOIN crypto_keys ck ON t.id = ck.tenant_id AND ck.is_active = TRUE
GROUP BY t.id, t.name;

-- Vista: Auditoría reciente
CREATE OR REPLACE VIEW vw_recent_audit AS
SELECT 
    DATE(created_at) AS audit_date,
    service_name,
    event_action,
    COUNT(*) AS total_events,
    SUM(CASE WHEN success = TRUE THEN 1 ELSE 0 END) AS success_events,
    SUM(CASE WHEN success = FALSE THEN 1 ELSE 0 END) AS failed_events
FROM audit_logs
WHERE created_at >= DATE_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
GROUP BY DATE(created_at), service_name, event_action
ORDER BY audit_date DESC, total_events DESC;
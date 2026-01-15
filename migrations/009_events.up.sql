USE digsigna;

-- ============================================
-- EVENTOS PROGRAMADOS (Mantenimiento automático)
-- ============================================

-- Evento: Rotación diaria de claves (ejecuta a las 2 AM)
CREATE EVENT IF NOT EXISTS ev_daily_key_rotation
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE, '02:00:00')
DO
    CALL sp_rotate_expired_keys();

-- Evento: Limpieza de sesiones cada hora
CREATE EVENT IF NOT EXISTS ev_hourly_session_cleanup
ON SCHEDULE EVERY 1 HOUR
DO
    CALL sp_cleanup_expired_sessions();

-- Evento: Backup de auditoría (mantiene solo 90 días)
-- CREATE EVENT IF NOT EXISTS ev_audit_log_cleanup
-- ON SCHEDULE EVERY 1 DAY
-- STARTS TIMESTAMP(CURRENT_DATE, '03:00:00')
-- DO
--     DELETE FROM audit_logs 
--     WHERE created_at < DATE_SUB(NOW(6), INTERVAL 90 DAY);

-- ============================================
-- EVENT: Resetear contadores mensuales
-- ============================================
DROP EVENT IF EXISTS ev_reset_monthly_quotas;

CREATE EVENT ev_reset_monthly_quotas
ON SCHEDULE EVERY 1 DAY
STARTS CURRENT_TIMESTAMP
DO
    UPDATE tenant_usage u
    INNER JOIN tenant_quotas q 
        ON u.tenant_id = q.tenant_id 
        AND u.quota_type = q.quota_type
    SET u.period_usage = 0,
        q.last_reset_at = CURRENT_TIMESTAMP(6),
        q.next_reset_at = DATE_ADD(CURRENT_TIMESTAMP(6), INTERVAL 1 MONTH)
    WHERE q.reset_period = 'MONTHLY'
        AND (q.next_reset_at IS NULL OR q.next_reset_at <= CURRENT_TIMESTAMP(6));
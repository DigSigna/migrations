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
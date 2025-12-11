USE digsigna;
-- ============================================
-- PROCEDIMIENTOS ALMACENADOS ÚTILES
-- ============================================

-- Procedimiento: Rotación automática de claves
DROP PROCEDURE IF EXISTS sp_rotate_expired_keys;

CREATE PROCEDURE sp_rotate_expired_keys()
BEGIN
    DECLARE rows_affected INT DEFAULT 0;
    
    UPDATE crypto_keys 
    SET is_active = FALSE, 
        updated_at = CURRENT_TIMESTAMP(6)
    WHERE expiration_date <= CURDATE() 
      AND is_active = TRUE;
    
    SET rows_affected = ROW_COUNT();
    
    IF rows_affected > 0 THEN
        INSERT INTO audit_logs (
            service_name, event_type, event_action,
            actor_type, actor_id, success,
            metadata
        ) VALUES (
            'hsm-service', 'SYSTEM', 'KEY_ROTATED',
            'SYSTEM', 'auto-rotation', TRUE,
            JSON_OBJECT('keys_rotated', rows_affected)
        );
    END IF;
END;

-- Procedimiento: Limpieza de sesiones expiradas
DROP PROCEDURE IF EXISTS sp_cleanup_expired_sessions;

CREATE PROCEDURE sp_cleanup_expired_sessions()
BEGIN
    DECLARE rows_affected INT DEFAULT 0;
    
    DELETE FROM user_sessions 
    WHERE revoked_at IS NULL 
      AND expires_at < CURRENT_TIMESTAMP(6);
    
    SET rows_affected = ROW_COUNT();
    
    IF rows_affected > 0 THEN
        INSERT INTO audit_logs (
            service_name, event_type, event_action,
            actor_type, actor_id, success,
            metadata
        ) VALUES (
            'auth-service', 'SYSTEM', 'SESSION_CLEANUP',
            'SYSTEM', 'cleanup-job', TRUE,
            JSON_OBJECT('sessions_cleaned', rows_affected)
        );
    END IF;
END;
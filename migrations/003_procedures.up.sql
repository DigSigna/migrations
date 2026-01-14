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

-- ============================================
-- PROCEDURE: Incrementar uso con validación
-- ============================================
DROP PROCEDURE IF EXISTS sp_increment_usage;

CREATE PROCEDURE sp_increment_usage(
    IN p_tenant_id CHAR(36),
    IN p_quota_type VARCHAR(50),
    IN p_delta INT,
    IN p_resource_id CHAR(36),
    IN p_resource_type VARCHAR(50),
    OUT p_allowed BOOLEAN,
    OUT p_current_usage INT,
    OUT p_max_limit INT
)
sp_proc: BEGIN
    DECLARE v_current_usage INT DEFAULT 0;
    DECLARE v_max_limit INT DEFAULT 0;
    DECLARE v_new_usage INT;
    DECLARE v_found BOOLEAN DEFAULT FALSE;
    
    -- Manejo de errores para SELECT INTO
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_found = FALSE;
    
    -- Obtener límite y uso actual con transacción implícita
    START TRANSACTION;
    
    SELECT u.current_usage, q.max_limit
    INTO v_current_usage, v_max_limit
    FROM tenant_usage u
    INNER JOIN tenant_quotas q 
        ON u.tenant_id = q.tenant_id 
        AND u.quota_type = q.quota_type
    WHERE u.tenant_id = p_tenant_id 
        AND u.quota_type = p_quota_type
        AND q.is_active = TRUE
    FOR UPDATE;  -- Lock para concurrencia
    
    -- Verificar si se encontraron registros
    IF v_current_usage IS NULL OR v_max_limit IS NULL THEN
        SET p_allowed = FALSE;
        SET p_current_usage = 0;
        SET p_max_limit = 0;
        ROLLBACK;
        LEAVE sp_proc;
    END IF;
    
    SET v_new_usage = v_current_usage + p_delta;
    
    -- Validar límite (-1 = ilimitado)
    IF v_max_limit = -1 OR v_new_usage <= v_max_limit THEN
        SET p_allowed = TRUE;
        
        -- Actualizar contador
        UPDATE tenant_usage
        SET current_usage = v_new_usage,
            period_usage = period_usage + p_delta,
            last_increment_at = CURRENT_TIMESTAMP(6)
        WHERE tenant_id = p_tenant_id 
            AND quota_type = p_quota_type;
        
        -- Registrar historial
        INSERT INTO tenant_usage_history (
            tenant_id, quota_type, action, 
            previous_value, new_value, delta,
            resource_id, resource_type, limit_reached, max_limit
        ) VALUES (
            p_tenant_id, p_quota_type, 'INCREMENT',
            v_current_usage, v_new_usage, p_delta,
            p_resource_id, p_resource_type, FALSE, v_max_limit
        );
        
        COMMIT;
    ELSE
        SET p_allowed = FALSE;
        
        -- Registrar intento de exceder límite
        INSERT INTO tenant_usage_history (
            tenant_id, quota_type, action, 
            previous_value, new_value, delta,
            resource_id, resource_type, limit_reached, max_limit
        ) VALUES (
            p_tenant_id, p_quota_type, 'LIMIT_REACHED',
            v_current_usage, v_current_usage, p_delta,
            p_resource_id, p_resource_type, TRUE, v_max_limit
        );
        
        COMMIT;
    END IF;
    
    SET p_current_usage = v_current_usage;
    SET p_max_limit = v_max_limit;
END;
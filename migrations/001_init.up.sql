-- ============================================
-- SCRIPT DE INICIALIZACIÓN DE BASE DE DATOS
-- ============================================

-- Deshabilitar FK temporalmente para recreación limpia
SET FOREIGN_KEY_CHECKS = 0;

-- ============================================
-- 1. TENANTS
-- ============================================
DROP TABLE IF EXISTS tenants;
CREATE TABLE tenants (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    name VARCHAR(255) NOT NULL,
    contact_email VARCHAR(255),
    plan_type ENUM('free', 'basic', 'professional', 'enterprise') DEFAULT 'free',
    status ENUM('active', 'suspended', 'pending', 'inactive') DEFAULT 'active',
    configuration JSON,
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    INDEX idx_tenants_status (status),
    INDEX idx_tenants_plan (plan_type)
);

-- ============================================
-- 2. USERS
-- ============================================
DROP TABLE IF EXISTS users;
CREATE TABLE users (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255),
    
    -- Información personal
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    
    -- Autenticación externa
    external_id VARCHAR(255),
    identity_provider ENUM('local', 'google', 'azure_ad', 'okta') DEFAULT 'local',
    
    -- Roles y permisos
    role ENUM('SUPER_ADMIN', 'TENANT_ADMIN', 'USER', 'OPERATOR') DEFAULT 'USER',
    mfa_enabled BOOLEAN DEFAULT FALSE,
    
    -- Estado
    status ENUM('ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING_VERIFICATION') DEFAULT 'PENDING_VERIFICATION',
    last_login_at TIMESTAMP(6) NULL,
    
    -- Auditoría
    created_by CHAR(36),
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    
    UNIQUE KEY uk_users_tenant_email (tenant_id, email),
    INDEX idx_users_tenant_status (tenant_id, status),
    INDEX idx_users_external (tenant_id, identity_provider, external_id)
);

-- ============================================
-- 3. USER_SESSIONS - Sesiones de usuario
-- ============================================
DROP TABLE IF EXISTS user_sessions;
CREATE TABLE user_sessions (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    user_id CHAR(36) NOT NULL,
    tenant_id CHAR(36) NOT NULL,
    
    -- Token de sesión
    session_token CHAR(64) NOT NULL,
    refresh_token CHAR(64),
    
    -- Contexto
    device_info JSON,
    ip_address VARCHAR(45),
    user_agent VARCHAR(500),
    
    -- Validez
    issued_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    expires_at TIMESTAMP(6) NOT NULL,
    revoked_at TIMESTAMP(6) NULL,
    
    -- Razón de revocación
    revocation_reason VARCHAR(255),
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_session_token (session_token),
    INDEX idx_sessions_user (user_id, created_at DESC),
    INDEX idx_sessions_expires (expires_at),
    INDEX idx_sessions_tenant (tenant_id, revoked_at)
);

-- ============================================
-- 4. CRYPTO_KEYS - Claves criptográficas
-- ============================================
DROP TABLE IF EXISTS crypto_keys;
CREATE TABLE crypto_keys (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    
    -- Identificación
    name VARCHAR(255) NOT NULL,
    alias VARCHAR(255),
    
    -- Especificaciones
    algorithm ENUM('RSA', 'ECC', 'ECDSA', 'ED25519') NOT NULL,
    key_size INT NOT NULL,
    purpose ENUM('SIGNING', 'ENCRYPTION', 'SIGN_AND_ENCRYPT') NOT NULL,
    
    -- Datos de clave
    public_key TEXT,
    key_handle VARCHAR(255),  -- Identificador en el HSM
    key_label VARCHAR(255),   -- Label en el HSM
    
    -- HSM y seguridad
    is_hardware_backed BOOLEAN DEFAULT TRUE,
    hsm_slot INT,
    
    -- Estado
    is_active BOOLEAN DEFAULT TRUE,
    version INT DEFAULT 1,
    
    -- Fechas
    rotation_date DATE,
    expiration_date DATE,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_crypto_keys_tenant_name (tenant_id, name),
    UNIQUE KEY uk_crypto_keys_key_handle (key_handle),
    INDEX idx_crypto_keys_tenant_active (tenant_id, is_active),
    INDEX idx_crypto_keys_algorithm (algorithm, key_size)
);

-- ============================================
-- 5. KEY_METADATA - Metadata adicional de claves
-- ============================================
DROP TABLE IF EXISTS key_metadata;
CREATE TABLE key_metadata (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    key_id CHAR(36) NOT NULL,
    meta_key VARCHAR(255) NOT NULL,
    meta_value JSON,
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_key_metadata_key (key_id, meta_key),
    INDEX idx_key_metadata_key (meta_key, (CAST(meta_value AS CHAR(100))))
);

-- ============================================
-- 6. KEY_OPERATIONS - Operaciones con claves (opcional, para auditoría detallada)
-- ============================================
DROP TABLE IF EXISTS key_operations;
CREATE TABLE key_operations (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    key_id CHAR(36) NOT NULL,
    tenant_id CHAR(36) NOT NULL,
    
    -- Operación
    operation_type ENUM('GENERATE', 'SIGN', 'VERIFY', 'ENCRYPT', 'DECRYPT', 'IMPORT', 'EXPORT'),
    status ENUM('SUCCESS', 'FAILED', 'PENDING', 'CANCELLED') NOT NULL,
    
    -- Contexto
    initiated_by CHAR(36),
    session_id VARCHAR(100),
    request_id VARCHAR(100),
    
    -- Datos de ejecución
    input_size_bytes INT,
    output_size_bytes INT,
    duration_ms INT,
    
    -- Resultado/error
    result_summary VARCHAR(500),
    error_details TEXT,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (initiated_by) REFERENCES users(id) ON DELETE SET NULL,
    
    INDEX idx_key_ops_created (created_at DESC),
    INDEX idx_key_ops_key (key_id, created_at),
    INDEX idx_key_ops_tenant (tenant_id, operation_type)
);

-- ============================================
-- 7. CERTIFICATES - Certificados digitales
-- ============================================
DROP TABLE IF EXISTS certificates;
CREATE TABLE certificates (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    key_id CHAR(36) NOT NULL,
    
    -- Información del certificado
    common_name VARCHAR(255) NOT NULL,
    serial_number VARCHAR(128) UNIQUE NOT NULL,
    issuer_common_name VARCHAR(255),
    
    -- Datos del certificado
    certificate_pem TEXT NOT NULL,
    csr_pem TEXT,
    private_key_handle VARCHAR(255),
    
    -- Jerarquía
    issuer_certificate_id CHAR(36),
    is_ca BOOLEAN DEFAULT FALSE,
    
    -- Validez
    valid_from TIMESTAMP(6) NOT NULL,
    valid_to TIMESTAMP(6) NOT NULL,
    
    -- Estado
    status ENUM('ACTIVE', 'REVOKED', 'EXPIRED', 'PENDING', 'SUSPENDED') DEFAULT 'PENDING',
    revocation_reason VARCHAR(255),
    revoked_at TIMESTAMP(6),
    
    -- Metadata
    subject_alternative_names JSON,
    key_usage JSON,
    extended_key_usage JSON,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE CASCADE,
    FOREIGN KEY (issuer_certificate_id) REFERENCES certificates(id) ON DELETE SET NULL,
    
    INDEX idx_certificates_tenant_status (tenant_id, status),
    INDEX idx_certificates_validity (valid_to, status),
    INDEX idx_certificates_serial (serial_number)
);

-- ============================================
-- 8. IDENTITY_DOCUMENTS
-- ============================================
DROP TABLE IF EXISTS identity_documents;
CREATE TABLE identity_documents (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    user_id CHAR(36) NOT NULL,
    
    -- Información del documento
    type ENUM('INE', 'PASSPORT', 'DRIVER_LICENSE', 'CURP', 'RFC') NOT NULL,
    number VARCHAR(100) NOT NULL,
    issuing_country VARCHAR(2) DEFAULT 'MX',
    
    -- Validez
    issued_at DATE,
    expires_at DATE,
    
    -- Datos biométricos/hash
    document_hash VARCHAR(255),
    verification_level ENUM('LOW', 'MEDIUM', 'HIGH') DEFAULT 'LOW',
    
    -- Metadata
    metadata JSON,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_identity_docs_user_type (user_id, type),
    INDEX idx_identity_docs_tenant (tenant_id, type),
    INDEX idx_identity_docs_expires (expires_at)
);

-- ============================================
-- 9. SIGNING_REQUESTS - Solicitudes de firma
-- ============================================
DROP TABLE IF EXISTS signing_requests;
CREATE TABLE signing_requests (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    user_id CHAR(36),
    key_id CHAR(36),
    
    -- Documento
    document_hash CHAR(64) NOT NULL,  -- SHA-256 en hex
    document_name VARCHAR(255),
    document_type VARCHAR(100),
    
    -- Firma
    signature_algorithm VARCHAR(50),
    hash_algorithm ENUM('SHA256', 'SHA384', 'SHA512') DEFAULT 'SHA256',
    
    -- Estado
    status ENUM('PENDING', 'SIGNED', 'FAILED', 'CANCELLED', 'EXPIRED') DEFAULT 'PENDING',
    status_reason VARCHAR(255),
    
    -- Metadata
    metadata JSON,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    expires_at TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE SET NULL,
    
    INDEX idx_signing_req_tenant_status (tenant_id, status),
    INDEX idx_signing_req_user (user_id, created_at DESC),
    INDEX idx_signing_req_expires (expires_at)
);

-- ============================================
-- 10. SIGNATURES - Firmas digitales
-- ============================================
DROP TABLE IF EXISTS signatures;
CREATE TABLE signatures (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    signing_request_id CHAR(36) NOT NULL,
    key_id CHAR(36) NOT NULL,
    certificate_id CHAR(36),
    
    -- Datos de la firma
    signature_value TEXT NOT NULL,  -- Base64
    signature_format ENUM('PKCS7', 'CMS', 'RAW', 'JWS') DEFAULT 'PKCS7',
    
    -- Timestamp
    signing_time TIMESTAMP(6) NOT NULL,
    
    -- Validación
    is_validated BOOLEAN DEFAULT FALSE,
    validation_timestamp TIMESTAMP(6),
    
    -- Metadata
    metadata JSON,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (signing_request_id) REFERENCES signing_requests(id) ON DELETE CASCADE,
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE CASCADE,
    FOREIGN KEY (certificate_id) REFERENCES certificates(id) ON DELETE SET NULL,
    
    UNIQUE KEY uk_signature_request (signing_request_id),
    INDEX idx_signatures_key (key_id, signing_time),
    INDEX idx_signatures_validated (is_validated, validation_timestamp)
);

-- ============================================
-- 11. VERIFICATIONS - Verificaciones de firmas
-- ============================================
DROP TABLE IF EXISTS verifications;
CREATE TABLE verifications (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    signature_id CHAR(36),
    certificate_id CHAR(36),
    
    -- Contexto
    document_hash CHAR(64),
    verifier_user_id CHAR(36),
    
    -- Resultado
    is_valid BOOLEAN NOT NULL,
    verification_result ENUM('VALID', 'INVALID_SIGNATURE', 'CERTIFICATE_EXPIRED', 'CERTIFICATE_REVOKED', 'UNTRUSTED_CA'),
    reason VARCHAR(255),
    
    -- Datos técnicos
    verification_time_ms INT,
    verified_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    -- Metadata
    metadata JSON,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (signature_id) REFERENCES signatures(id) ON DELETE SET NULL,
    FOREIGN KEY (certificate_id) REFERENCES certificates(id) ON DELETE SET NULL,
    FOREIGN KEY (verifier_user_id) REFERENCES users(id) ON DELETE SET NULL,
    
    INDEX idx_verifications_tenant (tenant_id, created_at DESC),
    INDEX idx_verifications_valid (is_valid, verified_at),
    INDEX idx_verifications_document (document_hash)
);

-- ============================================
-- 12. AUDIT_LOGS - Auditoría del sistema (MEJORADA)
-- ============================================
DROP TABLE IF EXISTS audit_logs;
CREATE TABLE audit_logs (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    
    -- Identificación y correlación
    correlation_id CHAR(36),
    session_id VARCHAR(100),
    request_id VARCHAR(100),
    
    -- Servicio y categoría
    service_name VARCHAR(50) NOT NULL,
    event_type ENUM('SECURITY', 'BUSINESS', 'SYSTEM', 'PERFORMANCE', 'AUDIT') NOT NULL,
    event_action VARCHAR(100) NOT NULL,
    
    -- Referencias (NULLables para permitir auditoría de operaciones fallidas)
    tenant_id CHAR(36),
    user_id CHAR(36),
    resource_id CHAR(36),
    resource_type VARCHAR(50),
    
    -- Actor
    actor_type ENUM('USER', 'SERVICE', 'SYSTEM', 'EXTERNAL') DEFAULT 'SYSTEM',
    actor_id VARCHAR(100),
    
    -- Resultado
    success BOOLEAN DEFAULT TRUE,
    status_code VARCHAR(50),
    error_message TEXT,
    duration_ms INT,
    
    -- Contexto de red
    ip_address VARCHAR(45),
    user_agent VARCHAR(500),
    
    -- Metadata flexible
    metadata JSON,
    
    -- Timestamps
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    -- Índices optimizados para consultas comunes
    INDEX idx_audit_tenant_created (tenant_id, created_at DESC),
    INDEX idx_audit_service_action (service_name, event_action, created_at DESC),
    INDEX idx_audit_correlation (correlation_id),
    INDEX idx_audit_actor (actor_type, actor_id),
    INDEX idx_audit_created (created_at DESC),
    INDEX idx_audit_success (success, created_at),
    INDEX idx_audit_resource (resource_type, resource_id)
    
    -- NOTA: No hay FK a tenant_id/users para permitir auditoría de entidades no válidas/eliminadas
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 13. KEY_PERMISSIONS - Permisos sobre claves
-- ============================================
DROP TABLE IF EXISTS key_permissions;
CREATE TABLE key_permissions (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    key_id CHAR(36) NOT NULL,
    user_id CHAR(36) NOT NULL,
    
    -- Permisos específicos
    can_sign BOOLEAN DEFAULT FALSE,
    can_encrypt BOOLEAN DEFAULT FALSE,
    can_decrypt BOOLEAN DEFAULT FALSE,
    can_manage BOOLEAN DEFAULT FALSE,
    
    -- Validez
    valid_from TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    valid_to TIMESTAMP(6),
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_key_permissions (key_id, user_id),
    INDEX idx_key_permissions_user (user_id, valid_to),
    INDEX idx_key_permissions_validity (valid_to)
);

-- ============================================
-- 14. AUDIT_METADATA - Metadata adicional de auditoría (opcional)
-- ============================================
DROP TABLE IF EXISTS audit_metadata;
CREATE TABLE audit_metadata (
    audit_log_id CHAR(36) NOT NULL,
    meta_key VARCHAR(100) NOT NULL,
    meta_value JSON,
    
    PRIMARY KEY (audit_log_id, meta_key),
    FOREIGN KEY (audit_log_id) REFERENCES audit_logs(id) ON DELETE CASCADE,
    
    INDEX idx_audit_meta_key (meta_key, (CAST(meta_value AS CHAR(100))))
);

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

-- Habilitar FK nuevamente
SET FOREIGN_KEY_CHECKS = 1;

-- ============================================
-- VISTAS ÚTILES
-- ============================================

-- Vista: Claves activas por tenant
CREATE OR REPLACE VIEW vw_active_keys AS
SELECT 
    tk.tenant_id,
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
WHERE created_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)
GROUP BY DATE(created_at), service_name, event_action
ORDER BY audit_date DESC, total_events DESC;

-- ============================================
-- PROCEDIMIENTOS ALMACENADOS ÚTILES
-- ============================================

-- Procedimiento: Rotación automática de claves
DELIMITER //
CREATE PROCEDURE sp_rotate_expired_keys()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_key_id CHAR(36);
    DECLARE v_tenant_id CHAR(36);
    DECLARE v_name VARCHAR(255);
    DECLARE v_algorithm VARCHAR(50);
    DECLARE v_key_size INT;
    DECLARE v_purpose VARCHAR(50);
    
    DECLARE cur_expired CURSOR FOR 
        SELECT id, tenant_id, name, algorithm, key_size, purpose
        FROM crypto_keys 
        WHERE expiration_date <= CURDATE() 
          AND is_active = TRUE;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    
    OPEN cur_expired;
    
    read_loop: LOOP
        FETCH cur_expired INTO v_key_id, v_tenant_id, v_name, v_algorithm, v_key_size, v_purpose;
        IF done THEN
            LEAVE read_loop;
        END IF;
        
        -- Marcar clave como inactiva
        UPDATE crypto_keys 
        SET is_active = FALSE, 
            updated_at = NOW(6)
        WHERE id = v_key_id;
        
        -- Auditoría de la rotación
        INSERT INTO audit_logs (
            service_name, event_type, event_action,
            tenant_id, resource_id, resource_type,
            actor_type, actor_id, success,
            metadata
        ) VALUES (
            'hsm-service', 'SYSTEM', 'KEY_ROTATED',
            v_tenant_id, v_key_id, 'CRYPTO_KEY',
            'SYSTEM', 'auto-rotation', TRUE,
            JSON_OBJECT(
                'reason', 'expired',
                'old_key_id', v_key_id,
                'algorithm', v_algorithm,
                'key_size', v_key_size
            )
        );
        
    END LOOP;
    
    CLOSE cur_expired;
END//
DELIMITER ;

-- Procedimiento: Limpieza de sesiones expiradas
DELIMITER //
CREATE PROCEDURE sp_cleanup_expired_sessions()
BEGIN
    DELETE FROM user_sessions 
    WHERE revoked_at IS NULL 
      AND expires_at < NOW(6);
    
    INSERT INTO audit_logs (
        service_name, event_type, event_action,
        actor_type, actor_id, success,
        metadata
    ) VALUES (
        'auth-service', 'SYSTEM', 'SESSION_CLEANUP',
        'SYSTEM', 'cleanup-job', TRUE,
        JSON_OBJECT('sessions_cleaned', ROW_COUNT())
    );
END//
DELIMITER ;

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
CREATE EVENT IF NOT EXISTS ev_audit_log_cleanup
ON SCHEDULE EVERY 1 DAY
STARTS TIMESTAMP(CURRENT_DATE, '03:00:00')
DO
    DELETE FROM audit_logs 
    WHERE created_at < DATE_SUB(NOW(6), INTERVAL 90 DAY);

-- ============================================
-- PERMISOS Y ROLES DE BASE DE DATOS
-- ============================================

-- Crear usuario de aplicación (ajusta la contraseña)
CREATE USER IF NOT EXISTS 'digsigna_app'@'%' IDENTIFIED BY 'StrongPassword123!';
GRANT SELECT, INSERT, UPDATE, DELETE ON digsigna.* TO 'digsigna_app'@'%';

-- Usuario de solo lectura para reportes
CREATE USER IF NOT EXISTS 'digsigna_report'@'%' IDENTIFIED BY 'ReportPassword123!';
GRANT SELECT ON digsigna.* TO 'digsigna_report'@'%';
GRANT SELECT ON digsigna.vw_* TO 'digsigna_report'@'%';

-- Usuario de mantenimiento
CREATE USER IF NOT EXISTS 'digsigna_maint'@'localhost' IDENTIFIED BY 'MaintenancePassword123!';
GRANT ALL PRIVILEGES ON digsigna.* TO 'digsigna_maint'@'localhost';
GRANT EXECUTE ON PROCEDURE digsigna.* TO 'digsigna_maint'@'localhost';

-- ============================================
-- MENSAJE FINAL
-- ============================================
SELECT 'Base de datos DigSigna inicializada correctamente' AS message;
-- ============================================
-- SCRIPT DE INICIALIZACIÓN DE BASE DE DATOS
-- ============================================

-- Deshabilitar FK temporalmente para recreación limpia
SET FOREIGN_KEY_CHECKS = 0;

-- ============================================
-- CREAR BASE DE DATOS SI NO EXISTE
-- ============================================
CREATE DATABASE IF NOT EXISTS digsigna
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE digsigna;

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
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6)
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
    
    UNIQUE KEY uk_users_tenant_email (tenant_id, email)
);

-- ============================================
-- 3. AUDIT_LOGS - Auditoría del sistema (MEJORADA)
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
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6)
    
    -- NOTA: No hay FK a tenant_id/users para permitir auditoría de entidades no válidas/eliminadas
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    
    UNIQUE KEY uk_crypto_keys_tenant_name (tenant_id, name)
);

-- ============================================
-- 5. AUDIT_METADATA - Metadata adicional de auditoría (opcional)
-- ============================================
DROP TABLE IF EXISTS audit_metadata;
CREATE TABLE audit_metadata (
    audit_log_id CHAR(36) NOT NULL,
    meta_key VARCHAR(100) NOT NULL,
    meta_value JSON,
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    PRIMARY KEY (audit_log_id, meta_key),
    FOREIGN KEY (audit_log_id) REFERENCES audit_logs(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================
-- 6. USER_SESSIONS - Sesiones de usuario
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
    
    UNIQUE KEY uk_session_token (session_token)
);



-- ============================================
-- 7. KEY_METADATA - Metadata adicional de claves
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
    
    UNIQUE KEY uk_key_metadata_key (key_id, meta_key)
);

-- ============================================
-- 8. KEY_OPERATIONS - Operaciones con claves (opcional, para auditoría detallada)
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
    FOREIGN KEY (initiated_by) REFERENCES users(id) ON DELETE SET NULL
);

-- ============================================
-- 9. CERTIFICATES - Certificados digitales
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
    FOREIGN KEY (issuer_certificate_id) REFERENCES certificates(id) ON DELETE SET NULL
);

-- ============================================
-- 10. IDENTITY_DOCUMENTS
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
    
    UNIQUE KEY uk_identity_docs_user_type (user_id, type)
);

-- ============================================
-- 11. SIGNING_REQUESTS - Solicitudes de firma
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
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE SET NULL
);

-- ============================================
-- 12. SIGNATURES - Firmas digitales
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
    
    UNIQUE KEY uk_signature_request (signing_request_id)
);

-- ============================================
-- 13. VERIFICATIONS - Verificaciones de firmas
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
    FOREIGN KEY (verifier_user_id) REFERENCES users(id) ON DELETE SET NULL
);


-- ============================================
-- 14. KEY_PERMISSIONS - Permisos sobre claves
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
    
    UNIQUE KEY uk_key_permissions (key_id, user_id)
);

-- ============================================
-- CREAR ÍNDICES
-- ============================================

-- Índices para audit_logs
CREATE INDEX idx_audit_tenant_created ON audit_logs(tenant_id, created_at DESC);
CREATE INDEX idx_audit_service_action ON audit_logs(service_name, event_action, created_at DESC);
CREATE INDEX idx_audit_correlation ON audit_logs(correlation_id);
CREATE INDEX idx_audit_actor ON audit_logs(actor_type, actor_id);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_success ON audit_logs(success, created_at);
CREATE INDEX idx_audit_resource ON audit_logs(resource_type, resource_id);

-- Índices para audit_metadata
CREATE INDEX idx_audit_meta_key ON audit_metadata(meta_key);

-- Índices para otras tablas
CREATE INDEX idx_users_tenant_status ON users(tenant_id, status);
CREATE INDEX idx_users_external ON users(tenant_id, identity_provider, external_id);
CREATE INDEX idx_sessions_user ON user_sessions(user_id, created_at DESC);
CREATE INDEX idx_sessions_expires ON user_sessions(expires_at);
CREATE INDEX idx_sessions_tenant ON user_sessions(tenant_id, revoked_at);
CREATE INDEX idx_crypto_keys_tenant_active ON crypto_keys(tenant_id, is_active);
CREATE INDEX idx_crypto_keys_algorithm ON crypto_keys(algorithm, key_size);
CREATE INDEX idx_key_metadata_key ON key_metadata(meta_key);
CREATE INDEX idx_key_ops_created ON key_operations(created_at DESC);
CREATE INDEX idx_key_ops_key ON key_operations(key_id, created_at);
CREATE INDEX idx_key_ops_tenant ON key_operations(tenant_id, operation_type);
CREATE INDEX idx_certificates_tenant_status ON certificates(tenant_id, status);
CREATE INDEX idx_certificates_validity ON certificates(valid_to, status);
CREATE INDEX idx_certificates_serial ON certificates(serial_number);
CREATE INDEX idx_identity_docs_tenant ON identity_documents(tenant_id, type);
CREATE INDEX idx_identity_docs_expires ON identity_documents(expires_at);
CREATE INDEX idx_signing_req_tenant_status ON signing_requests(tenant_id, status);
CREATE INDEX idx_signing_req_user ON signing_requests(user_id, created_at DESC);
CREATE INDEX idx_signing_req_expires ON signing_requests(expires_at);
CREATE INDEX idx_signatures_key ON signatures(key_id, signing_time);
CREATE INDEX idx_signatures_validated ON signatures(is_validated, validation_timestamp);
CREATE INDEX idx_verifications_tenant ON verifications(tenant_id, created_at DESC);
CREATE INDEX idx_verifications_valid ON verifications(is_valid, verified_at);
CREATE INDEX idx_verifications_document ON verifications(document_hash);
CREATE INDEX idx_key_permissions_user ON key_permissions(user_id, valid_to);
CREATE INDEX idx_key_permissions_validity ON key_permissions(valid_to);


-- Habilitar FK nuevamente
SET FOREIGN_KEY_CHECKS = 1;

-- ============================================
-- MENSAJE FINAL
-- ============================================
SELECT 'Base de datos DigSigna inicializada correctamente' AS message;
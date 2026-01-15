-- ============================================
-- FLUJO DE FIRMA: Requests, Signatures, Verifications
-- ============================================

SET FOREIGN_KEY_CHECKS = 0;

USE digsigna;

-- ============================================
-- 1. SIGNING_REQUESTS - Solicitudes de firma
-- ============================================
DROP TABLE IF EXISTS signing_requests;
CREATE TABLE signing_requests (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    organization_id CHAR(36),
    user_id CHAR(36),
    key_id CHAR(36),
    
    -- Documento
    document_hash CHAR(64) NOT NULL,
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
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE SET NULL,
    
    INDEX idx_signing_req_tenant_status (tenant_id, status),
    INDEX idx_signing_req_organization (organization_id),
    INDEX idx_signing_req_user (user_id, created_at DESC),
    INDEX idx_signing_req_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 2. SIGNATURES - Firmas digitales
-- ============================================
DROP TABLE IF EXISTS signatures;
CREATE TABLE signatures (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    signing_request_id CHAR(36) NOT NULL,
    key_id CHAR(36) NOT NULL,
    certificate_id CHAR(36),
    
    -- Datos de la firma
    signature_value BLOB NOT NULL,
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 3. VERIFICATIONS - Verificaciones de firmas
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Tablas de flujo de firma creadas correctamente' AS message;

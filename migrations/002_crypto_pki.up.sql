-- ============================================
-- PKI: Claves Criptográficas y Certificados
-- ============================================

SET FOREIGN_KEY_CHECKS = 0;

USE digsigna;

-- ============================================
-- 1. CRYPTO_KEYS - Claves con jerarquía PKI
-- ============================================
DROP TABLE IF EXISTS crypto_keys;
CREATE TABLE crypto_keys (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    
    -- Propietario polimórfico
    owner_type ENUM('TENANT', 'ORGANIZATION', 'USER') NOT NULL,
    owner_id CHAR(36) NOT NULL,
    
    -- Jerarquía PKI
    parent_key_id CHAR(36),
    cert_level INT NOT NULL DEFAULT 0,
    
    -- Identificación
    name VARCHAR(255) NOT NULL,
    alias VARCHAR(255),
    
    -- Especificaciones
    algorithm ENUM('RSA', 'ECC', 'ECDSA', 'ED25519') NOT NULL,
    key_size INT NOT NULL,
    purpose ENUM('SIGNING', 'ENCRYPTION', 'SIGN_AND_ENCRYPT') NOT NULL,
    
    -- Datos de clave
    public_key BLOB,
    key_handle VARCHAR(255),
    key_label VARCHAR(255),
    
    -- HSM y seguridad
    is_hardware_backed BOOLEAN DEFAULT TRUE,
    -- Referencia al slot HSM en la nueva tabla hsm_slots (nullable; FK se añade en migraciones posteriores)
    hsm_slot_id CHAR(36),
    
    -- Estado
    is_active BOOLEAN DEFAULT TRUE,
    version INT DEFAULT 1,
    
    -- Fechas
    rotation_date DATE,
    expiration_date DATE,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (parent_key_id) REFERENCES crypto_keys(id) ON DELETE RESTRICT,
    
    UNIQUE KEY uk_crypto_keys_tenant_name (tenant_id, name),
    INDEX idx_crypto_keys_tenant_active (tenant_id, is_active),
    INDEX idx_crypto_keys_owner (owner_type, owner_id),
    INDEX idx_crypto_keys_parent (parent_key_id),
    INDEX idx_crypto_keys_hierarchy (tenant_id, cert_level),
    INDEX idx_crypto_keys_hsm_slot_id (hsm_slot_id),
    INDEX idx_crypto_keys_algorithm (algorithm, key_size)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 2. KEY_METADATA
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
    INDEX idx_key_metadata_key (meta_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 3. KEY_OPERATIONS - Auditoría de operaciones
-- ============================================
DROP TABLE IF EXISTS key_operations;
CREATE TABLE key_operations (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    key_id CHAR(36) NOT NULL,
    tenant_id CHAR(36) NOT NULL,
    organization_id CHAR(36),
    
    operation_type ENUM('GENERATE', 'ROTATE', 'DELETE', 'SIGN', 'VERIFY', 'ENCRYPT', 'DECRYPT', 'IMPORT', 'EXPORT'),
    status ENUM('SUCCESS', 'FAILED', 'PENDING', 'CANCELLED') NOT NULL,
    level ENUM('LOW', 'MEDIUM', 'HIGH') DEFAULT 'LOW',
    
    initiated_by CHAR(36),
    session_id VARCHAR(100),
    request_id VARCHAR(100),
    
    input_size_bytes INT,
    output_size_bytes INT,
    duration_ms INT,
    
    result_summary VARCHAR(500),
    error_details TEXT,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL,
    FOREIGN KEY (initiated_by) REFERENCES users(id) ON DELETE SET NULL,
    
    INDEX idx_key_ops_created (created_at DESC),
    INDEX idx_key_ops_key (key_id, created_at),
    INDEX idx_key_ops_tenant (tenant_id, operation_type),
    INDEX idx_key_ops_organization (organization_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 4. KEY_PERMISSIONS - Permisos granulares por clave
-- ============================================
-- Diseño normalizado: un registro por permiso para auditoría completa
DROP TABLE IF EXISTS key_permissions;
CREATE TABLE key_permissions (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    key_id CHAR(36) NOT NULL,
    user_id CHAR(36) NOT NULL,
    
    -- Tipo de permiso específico
    permission_type ENUM(
        'SIGN',         -- Firmar con esta clave
        'ENCRYPT',      -- Cifrar con esta clave
        'DECRYPT',      -- Descifrar con esta clave
        'VERIFY',       -- Verificar firmas
        'MANAGE',       -- Gestionar permisos de la clave
        'REVOKE',       -- Revocar certificados
        'DELEGATE',     -- Delegar permisos a otros usuarios
        'EXPORT',       -- Exportar clave pública
        'BACKUP'        -- Crear backup de la clave
    ) NOT NULL,
    
    -- Auditoría completa
    granted_by CHAR(36),      -- Usuario que otorgó el permiso (NULL = sistema)
    revoked_by CHAR(36),      -- Usuario que revocó el permiso
    revoked_at TIMESTAMP(6),  -- Fecha de revocación (soft delete)
    revocation_reason TEXT,   -- Motivo de revocación
    
    -- Ventana de validez
    valid_from TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    valid_to TIMESTAMP(6),    -- NULL = sin expiración
    
    -- Metadatos adicionales
    metadata JSON,            -- Condiciones adicionales, restricciones, etc.
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (granted_by) REFERENCES users(id) ON DELETE SET NULL,
    FOREIGN KEY (revoked_by) REFERENCES users(id) ON DELETE SET NULL,
    
    -- Índices para queries frecuentes
    INDEX idx_key_perms_user_active (user_id, permission_type, revoked_at, valid_to),
    INDEX idx_key_perms_key (key_id, permission_type, revoked_at),
    INDEX idx_key_perms_validity (valid_from, valid_to),
    INDEX idx_key_perms_revoked (revoked_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 4B. KEY_PERMISSIONS_CACHE - Cache para performance
-- ============================================
-- Tabla materializada para evitar JOINs en operaciones críticas
DROP TABLE IF EXISTS key_permissions_cache;
CREATE TABLE key_permissions_cache (
    user_id CHAR(36) NOT NULL,
    key_id CHAR(36) NOT NULL,
    
    -- Bitmap de permisos activos (bitwise operations)
    -- 1=SIGN, 2=ENCRYPT, 4=DECRYPT, 8=VERIFY, 16=MANAGE, 32=REVOKE, 64=DELEGATE, 128=EXPORT, 256=BACKUP
    permissions_bitmap INT NOT NULL DEFAULT 0,
    
    -- Expiración más cercana de todos los permisos
    earliest_expiry TIMESTAMP(6),
    
    -- Última actualización del cache
    cache_updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    PRIMARY KEY (user_id, key_id),
    INDEX idx_cache_expiry (earliest_expiry),
    INDEX idx_cache_user (user_id),
    INDEX idx_cache_key (key_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 5. CERTIFICATES - Certificados digitales
-- ============================================
DROP TABLE IF EXISTS certificates;
CREATE TABLE certificates (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    key_id CHAR(36) NOT NULL,
    
    -- Propietario polimórfico
    owner_type ENUM('TENANT', 'ORGANIZATION', 'USER') NOT NULL,
    owner_id CHAR(36) NOT NULL,
    
    -- Información del certificado
    common_name VARCHAR(255) NOT NULL,
    serial_number VARCHAR(128) UNIQUE NOT NULL,
    issuer_common_name VARCHAR(255),
    
    -- Datos del certificado
    certificate_pem TEXT NOT NULL,
    csr_pem TEXT,
    private_key_handle VARCHAR(255),
    
    -- Cadena de certificación PKI
    issuer_certificate_id CHAR(36),
    issuer_key_id CHAR(36),
    is_ca BOOLEAN DEFAULT FALSE,
    path_length INT,
    cert_level INT NOT NULL DEFAULT 0,
    
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
    FOREIGN KEY (issuer_key_id) REFERENCES crypto_keys(id) ON DELETE SET NULL,
    
    INDEX idx_certificates_tenant_status (tenant_id, status),
    INDEX idx_certificates_owner (owner_type, owner_id),
    INDEX idx_certificates_issuer_cert (issuer_certificate_id),
    INDEX idx_certificates_issuer_key (issuer_key_id),
    INDEX idx_certificates_hierarchy (tenant_id, cert_level),
    INDEX idx_certificates_validity (valid_to, status),
    INDEX idx_certificates_serial (serial_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Tablas PKI creadas correctamente' AS message;

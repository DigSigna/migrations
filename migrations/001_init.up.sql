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
-- 1. TENANTS - Modelo Híbrido (Managed + Independent)
-- ============================================
DROP TABLE IF EXISTS tenants;
CREATE TABLE tenants (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    name VARCHAR(255) NOT NULL,
    contact_email VARCHAR(255),
    
    -- Modo de operación (HÍBRIDO)
    mode ENUM('MANAGED', 'INDEPENDENT') DEFAULT 'MANAGED' COMMENT 'MANAGED: CA bajo DigSigna Root (slot 0). INDEPENDENT: Root CA propio (slot dedicado)',
    
    -- Plan y tipo
    plan_type ENUM('free', 'basic', 'professional', 'enterprise', 'white_label', 'custom') DEFAULT 'free',
    status ENUM('active', 'suspended', 'pending', 'inactive') DEFAULT 'active',
    
    -- HSM Slot
    -- MANAGED: usa slot 0 (compartido)
    -- INDEPENDENT: usa slot > 0 (dedicado)
    hsm_slot INT NOT NULL,
    
    -- Relación con tenant padre (solo para INDEPENDENT)
    parent_tenant_id CHAR(36) COMMENT 'Referencia al tenant plataforma. NULL para platform root, valor para white-label',
    
    -- Configuración
    configuration JSON,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (parent_tenant_id) REFERENCES tenants(id) ON DELETE RESTRICT,
    
    INDEX idx_tenants_mode (mode),
    INDEX idx_tenants_parent (parent_tenant_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- Tabla de Organizaciones (Municipios, Empresas, Colegios, Plataformas revendedoras, etc.)
-- ============================================
DROP TABLE IF EXISTS organizations;
CREATE TABLE organizations (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    parent_id CHAR(36), -- Auto-referencia para jerarquía
    
    -- Tipo y datos básicos
    type VARCHAR(50) NOT NULL, -- 'MUNICIPALITY', 'COMPANY', 'SCHOOL', 'DEPARTMENT', 'BRANCH', 'DIVISION', 'RESELLER', etc.
    name VARCHAR(255) NOT NULL,
    legal_name VARCHAR(255),
    description TEXT,
    
    -- Identificación fiscal/legal (para facturación)
    tax_id VARCHAR(50), -- RFC para México, NIT para otros países
    country_code VARCHAR(2) DEFAULT 'MX',
    
    -- Jerarquía
    level INT NOT NULL DEFAULT 0, -- 0=cliente directo, 1=departamento, 2=subdepartamento, etc.
    
    -- Estado y suspensión
    status ENUM('ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING_ACTIVATION') DEFAULT 'PENDING_ACTIVATION',
    suspended_reason VARCHAR(255),
    suspended_at TIMESTAMP(6),
    
    -- Plan y facturación (heredado del parent si es null)
    plan_type ENUM('free', 'basic', 'professional', 'enterprise', 'custom'),
    billing_email VARCHAR(255),
    
    -- Metadata flexible para datos específicos por tipo
    metadata JSON,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (parent_id) REFERENCES organizations(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_organizations_tenant_name (tenant_id, name),
    INDEX idx_organizations_tax_id (tax_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Tabla de Roles
CREATE TABLE roles (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_system_role BOOLEAN DEFAULT FALSE, -- Para roles como 'Super Admin' del sistema
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    UNIQUE(tenant_id, name) -- Nombre de rol único por tenant
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabla de Permisos
CREATE TABLE permissions (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    code VARCHAR(100) NOT NULL UNIQUE, -- Ej: 'document:sign', 'user:create'
    description TEXT NOT NULL,
    module VARCHAR(50) NOT NULL -- Agrupa permisos: 'HSM', 'Document', 'User', etc.
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabla de relación Rol-Permiso
CREATE TABLE role_permissions (
    role_id CHAR(36) NOT NULL,
    permission_id CHAR(36) NOT NULL,
    granted_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (role_id, permission_id),
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
    FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 2. USERS
-- ============================================
DROP TABLE IF EXISTS users;
CREATE TABLE users (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    organization_id CHAR(36), -- Organización a la que pertenece
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255),
    
    -- Información personal
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    
    -- Autenticación externa
    external_id VARCHAR(255),
    identity_provider ENUM('local', 'google', 'azure_ad', 'okta') DEFAULT 'local',
    
    mfa_enabled BOOLEAN DEFAULT FALSE,
    
    -- Estado
    status ENUM('ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING_VERIFICATION') DEFAULT 'PENDING_VERIFICATION',
    last_login_at TIMESTAMP(6) NULL,
    
    -- Auditoría
    created_by CHAR(36),
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),

    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    
    UNIQUE KEY uk_users_tenant_email (tenant_id, email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabla de relación Usuario-Rol
CREATE TABLE user_roles (
    user_id CHAR(36) NOT NULL,
    role_id CHAR(36) NOT NULL,
    assigned_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    assigned_by CHAR(36), -- ID del usuario que asignó el rol
    PRIMARY KEY (user_id, role_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
    FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Tabla de relación directa Usuario-Permiso (para sobreescribir)
CREATE TABLE user_permissions (
    user_id CHAR(36) NOT NULL,
    permission_id CHAR(36) NOT NULL,
    is_granted BOOLEAN NOT NULL DEFAULT TRUE, -- TRUE=grant, FALSE=deny
    granted_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (user_id, permission_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    event_type ENUM('SECURITY', 'BUSINESS', 'SYSTEM', 'PERFORMANCE', 'AUDIT', 'HSM_OPERATION') NOT NULL,
    event_action VARCHAR(100) NOT NULL,
    
    -- Referencias (NULLables para permitir auditoría de operaciones fallidas)
    tenant_id CHAR(36),
    organization_id CHAR(36), -- Organización relacionada con la operación
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
-- 4. CRYPTO_KEYS - Claves criptográficas con jerarquía PKI
-- ============================================
DROP TABLE IF EXISTS crypto_keys;
CREATE TABLE crypto_keys (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    
    -- Propietario de la clave (polimórfico)
    owner_type ENUM('TENANT', 'ORGANIZATION', 'USER') NOT NULL,
    owner_id CHAR(36) NOT NULL, -- ID de tenant, organization o user
    
    -- Jerarquía PKI
    parent_key_id CHAR(36), -- Clave que firmó el CSR de esta clave
    cert_level INT NOT NULL DEFAULT 0, -- 0=master/root, 1=intermediate, 2=end-entity
    
    -- Identificación
    name VARCHAR(255) NOT NULL,
    alias VARCHAR(255),
    
    -- Especificaciones
    algorithm ENUM('RSA', 'ECC', 'ECDSA', 'ED25519') NOT NULL,
    key_size INT NOT NULL,
    purpose ENUM('SIGNING', 'ENCRYPTION', 'SIGN_AND_ENCRYPT') NOT NULL,
    
    -- Datos de clave
    public_key BLOB,
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
    FOREIGN KEY (parent_key_id) REFERENCES crypto_keys(id) ON DELETE RESTRICT,
    
    UNIQUE KEY uk_crypto_keys_tenant_name (tenant_id, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;



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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 8. KEY_OPERATIONS - Operaciones con claves (opcional, para auditoría detallada)
-- ============================================
DROP TABLE IF EXISTS key_operations;
CREATE TABLE key_operations (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    key_id CHAR(36) NOT NULL,
    tenant_id CHAR(36) NOT NULL,
    organization_id CHAR(36), -- Organización asociada a la operación
    
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
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL,
    FOREIGN KEY (initiated_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 9. CERTIFICATES - Certificados digitales con cadena PKI
-- ============================================
DROP TABLE IF EXISTS certificates;
CREATE TABLE certificates (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    key_id CHAR(36) NOT NULL,
    
    -- Propietario del certificado (polimórfico)
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
    
    -- Cadena de certificación y jerarquía PKI
    issuer_certificate_id CHAR(36), -- Certificado que firmó este
    issuer_key_id CHAR(36),         -- Clave que firmó este CSR
    is_ca BOOLEAN DEFAULT FALSE,
    path_length INT,                 -- Máxima profundidad de certificados que puede firmar
    cert_level INT NOT NULL DEFAULT 0, -- 0=root, 1=intermediate, 2=end-entity
    
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
    FOREIGN KEY (issuer_key_id) REFERENCES crypto_keys(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 11. SIGNING_REQUESTS - Solicitudes de firma
-- ============================================
DROP TABLE IF EXISTS signing_requests;
CREATE TABLE signing_requests (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    organization_id CHAR(36), -- Organización que solicita la firma
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
    FOREIGN KEY (organization_id) REFERENCES organizations(id) ON DELETE SET NULL,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    signature_value BLOB NOT NULL,  -- Firma en binario
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ============================================
-- TENANT_QUOTAS - Cuotas y límites por tenant
-- ============================================
CREATE TABLE tenant_quotas (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    
    -- Tipo de cuota
    quota_type ENUM(
        'USERS',           -- Máximo de usuarios
        'KEYS',            -- Máximo de claves criptográficas
        'SIGNATURES',      -- Firmas permitidas
        'VERIFICATIONS',   -- Verificaciones permitidas
        'STORAGE_MB',      -- Almacenamiento en MB
        'API_CALLS',       -- Llamadas a API
        'CERTIFICATES'     -- Certificados activos
    ) NOT NULL,
    
    -- Límites
    max_limit INT NOT NULL,           -- Límite máximo (-1 = ilimitado)
    warning_threshold INT DEFAULT 0,   -- Umbral de advertencia (80% por ejemplo)
    
    -- Control de periodo (para planes por tiempo)
    reset_period ENUM('NONE', 'DAILY', 'MONTHLY', 'YEARLY') DEFAULT 'NONE',
    last_reset_at TIMESTAMP(6),
    next_reset_at TIMESTAMP(6),
    
    -- Estado
    is_active BOOLEAN DEFAULT TRUE,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_tenant_quota_type (tenant_id, quota_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- TENANT_USAGE - Consumo en tiempo real
-- ============================================
CREATE TABLE tenant_usage (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    quota_type ENUM(
        'USERS', 'KEYS', 'SIGNATURES', 'VERIFICATIONS',
        'STORAGE_MB', 'API_CALLS', 'CERTIFICATES'
    ) NOT NULL,
    
    -- Contadores
    current_usage INT DEFAULT 0,       -- Uso actual
    period_usage INT DEFAULT 0,        -- Uso en el periodo (si reset_period != NONE)
    
    -- Metadata
    last_increment_at TIMESTAMP(6),
    last_decrement_at TIMESTAMP(6),
    
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_tenant_usage_type (tenant_id, quota_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- TENANT_USAGE_HISTORY - Auditoría de consumo
-- ============================================
CREATE TABLE tenant_usage_history (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    quota_type ENUM(
        'USERS', 'KEYS', 'SIGNATURES', 'VERIFICATIONS',
        'STORAGE_MB', 'API_CALLS', 'CERTIFICATES'
    ) NOT NULL,
    
    -- Cambio
    action ENUM('INCREMENT', 'DECREMENT', 'RESET', 'LIMIT_REACHED') NOT NULL,
    previous_value INT NOT NULL,
    new_value INT NOT NULL,
    delta INT NOT NULL,  -- Diferencia (+/-)
    
    -- Contexto
    resource_id CHAR(36),      -- ID del recurso que causó el cambio
    resource_type VARCHAR(50), -- Tipo: 'KEY', 'SIGNATURE', 'USER', etc.
    user_id CHAR(36),
    
    -- Límite alcanzado
    limit_reached BOOLEAN DEFAULT FALSE,
    max_limit INT,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- CREAR ÍNDICES
-- ============================================

-- Índices para organizations
CREATE INDEX idx_organizations_tenant ON organizations(tenant_id, type);
CREATE INDEX idx_organizations_parent ON organizations(parent_id);
CREATE INDEX idx_organizations_level ON organizations(level);
CREATE INDEX idx_organizations_status ON organizations(tenant_id, status);
CREATE INDEX idx_organizations_plan ON organizations(plan_type);
CREATE INDEX idx_organizations_country ON organizations(country_code);

-- Índices para audit_logs
CREATE INDEX idx_audit_tenant_created ON audit_logs(tenant_id, created_at DESC);
CREATE INDEX idx_audit_organization ON audit_logs(organization_id, created_at DESC);
CREATE INDEX idx_audit_service_action ON audit_logs(service_name, event_action, created_at DESC);
CREATE INDEX idx_audit_correlation ON audit_logs(correlation_id);
CREATE INDEX idx_audit_actor ON audit_logs(actor_type, actor_id);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_success ON audit_logs(success, created_at);
CREATE INDEX idx_audit_resource ON audit_logs(resource_type, resource_id);

-- Índices para audit_metadata
CREATE INDEX idx_audit_meta_key ON audit_metadata(meta_key);

-- Índices para users
CREATE INDEX idx_users_tenant_status ON users(tenant_id, status);
CREATE INDEX idx_users_organization ON users(organization_id);
CREATE INDEX idx_users_external ON users(tenant_id, identity_provider, external_id);

-- Índices para sessions
CREATE INDEX idx_sessions_user ON user_sessions(user_id, created_at DESC);
CREATE INDEX idx_sessions_expires ON user_sessions(expires_at);
CREATE INDEX idx_sessions_tenant ON user_sessions(tenant_id, revoked_at);

-- Índices para crypto_keys (con jerarquía PKI)
CREATE INDEX idx_crypto_keys_tenant_active ON crypto_keys(tenant_id, is_active);
CREATE INDEX idx_crypto_keys_owner ON crypto_keys(owner_type, owner_id);
CREATE INDEX idx_crypto_keys_parent ON crypto_keys(parent_key_id);
CREATE INDEX idx_crypto_keys_hierarchy ON crypto_keys(tenant_id, cert_level);
CREATE INDEX idx_crypto_keys_algorithm ON crypto_keys(algorithm, key_size);

-- Índices para key_metadata
CREATE INDEX idx_key_metadata_key ON key_metadata(meta_key);

-- Índices para key_operations
CREATE INDEX idx_key_ops_created ON key_operations(created_at DESC);
CREATE INDEX idx_key_ops_key ON key_operations(key_id, created_at);
CREATE INDEX idx_key_ops_tenant ON key_operations(tenant_id, operation_type);
CREATE INDEX idx_key_ops_organization ON key_operations(organization_id);

-- Índices para certificates (con cadena PKI)
CREATE INDEX idx_certificates_tenant_status ON certificates(tenant_id, status);
CREATE INDEX idx_certificates_owner ON certificates(owner_type, owner_id);
CREATE INDEX idx_certificates_issuer_cert ON certificates(issuer_certificate_id);
CREATE INDEX idx_certificates_issuer_key ON certificates(issuer_key_id);
CREATE INDEX idx_certificates_hierarchy ON certificates(tenant_id, cert_level);
CREATE INDEX idx_certificates_validity ON certificates(valid_to, status);
CREATE INDEX idx_certificates_serial ON certificates(serial_number);

-- Índices para identity_documents
CREATE INDEX idx_identity_docs_tenant ON identity_documents(tenant_id, type);
CREATE INDEX idx_identity_docs_expires ON identity_documents(expires_at);

-- Índices para signing_requests
CREATE INDEX idx_signing_req_tenant_status ON signing_requests(tenant_id, status);
CREATE INDEX idx_signing_req_organization ON signing_requests(organization_id);
CREATE INDEX idx_signing_req_user ON signing_requests(user_id, created_at DESC);
CREATE INDEX idx_signing_req_expires ON signing_requests(expires_at);

-- Índices para signatures
CREATE INDEX idx_signatures_key ON signatures(key_id, signing_time);
CREATE INDEX idx_signatures_validated ON signatures(is_validated, validation_timestamp);

-- Índices para verifications
CREATE INDEX idx_verifications_tenant ON verifications(tenant_id, created_at DESC);
CREATE INDEX idx_verifications_valid ON verifications(is_valid, verified_at);
CREATE INDEX idx_verifications_document ON verifications(document_hash);

-- Índices para key_permissions
CREATE INDEX idx_key_permissions_user ON key_permissions(user_id, valid_to);
CREATE INDEX idx_key_permissions_validity ON key_permissions(valid_to);

-- Índices para tablas de cuotas
CREATE INDEX idx_tenant_quota_active ON tenant_quotas(tenant_id, is_active);
CREATE INDEX idx_tenant_quota_type ON tenant_quotas(quota_type, is_active);
CREATE INDEX idx_tenant_usage_type ON tenant_usage(tenant_id, quota_type);
CREATE INDEX idx_usage_history_tenant ON tenant_usage_history(tenant_id, created_at DESC);
CREATE INDEX idx_usage_history_type ON tenant_usage_history(quota_type, created_at DESC);
CREATE INDEX idx_usage_history_resource ON tenant_usage_history(resource_type, resource_id);

-- ============================================
-- TRIGGERS DE VALIDACIÓN PKI
-- ============================================

DELIMITER $$

-- ============================================
-- TRIGGER 1: Validar jerarquía PKI al insertar certificado
-- ============================================
CREATE TRIGGER trg_validate_certificate_hierarchy_before_insert
BEFORE INSERT ON certificates
FOR EACH ROW
BEGIN
    DECLARE parent_is_ca BOOLEAN;
    DECLARE parent_path_length INT;
    DECLARE parent_cert_level INT;
    DECLARE key_owner_type VARCHAR(20);
    DECLARE key_owner_id CHAR(36);
    DECLARE key_cert_level INT;
    
    -- Validar consistencia con crypto_keys
    SELECT owner_type, owner_id, cert_level
    INTO key_owner_type, key_owner_id, key_cert_level
    FROM crypto_keys
    WHERE id = NEW.key_id;
    
    IF key_owner_type IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La clave criptográfica no existe';
    END IF;
    
    -- Validar que owner coincida
    IF key_owner_type != NEW.owner_type OR key_owner_id != NEW.owner_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El propietario del certificado no coincide con el de la clave';
    END IF;
    
    -- Validar que cert_level coincida
    IF key_cert_level != NEW.cert_level THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'cert_level del certificado debe coincidir con el de la clave';
    END IF;
    
    -- Si tiene emisor, validar la cadena
    IF NEW.issuer_certificate_id IS NOT NULL THEN
        SELECT is_ca, path_length, cert_level
        INTO parent_is_ca, parent_path_length, parent_cert_level
        FROM certificates
        WHERE id = NEW.issuer_certificate_id;
        
        IF parent_is_ca IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El certificado emisor no existe';
        END IF;
        
        -- 1. El emisor DEBE ser una CA
        IF parent_is_ca = FALSE THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El certificado emisor no es una CA (is_ca=FALSE)';
        END IF;
        
        -- 2. Si el nuevo certificado es CA, validar path_length del emisor
        IF NEW.is_ca = TRUE THEN
            IF parent_path_length IS NOT NULL AND parent_path_length < 1 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'El emisor no puede firmar CAs intermedias (path_length < 1)';
            END IF;
            
            -- El path_length del hijo debe ser menor
            IF NEW.path_length IS NOT NULL AND parent_path_length IS NOT NULL THEN
                IF NEW.path_length >= parent_path_length THEN
                    SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'path_length del certificado hijo debe ser menor que el del padre';
                END IF;
            END IF;
        END IF;
        
        -- 3. Validar que cert_level sea secuencial
        IF NEW.cert_level != (parent_cert_level + 1) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'cert_level debe ser secuencial (padre + 1)';
        END IF;
        
        -- 4. Validar que issuer_key_id corresponda al certificado emisor
        IF NEW.issuer_key_id IS NOT NULL THEN
            IF NOT EXISTS (
                SELECT 1 FROM certificates 
                WHERE id = NEW.issuer_certificate_id 
                AND key_id = NEW.issuer_key_id
            ) THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'issuer_key_id no corresponde con el key_id del certificado emisor';
            END IF;
        END IF;
        
        -- 5. Validar que el emisor no esté revocado o expirado
        IF EXISTS (
            SELECT 1 FROM certificates 
            WHERE id = NEW.issuer_certificate_id 
            AND (status = 'REVOKED' OR status = 'EXPIRED')
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede emitir certificado: el emisor está revocado o expirado';
        END IF;
    ELSE
        -- Si no tiene emisor, DEBE ser root (cert_level=0)
        IF NEW.cert_level != 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Solo certificados root (cert_level=0) pueden no tener emisor';
        END IF;
        
        -- Root debe ser CA
        IF NEW.is_ca = FALSE THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Certificados root deben ser CA (is_ca=TRUE)';
        END IF;
    END IF;
    
    -- Validar path_length si es CA
    IF NEW.is_ca = TRUE THEN
        IF NEW.path_length IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'path_length es requerido para certificados CA';
        END IF;
        
        IF NEW.path_length < 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'path_length no puede ser negativo';
        END IF;
    ELSE
        -- End-entities no deben tener path_length
        IF NEW.path_length IS NOT NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Certificados end-entity (is_ca=FALSE) no deben tener path_length';
        END IF;
    END IF;
END$$

-- ============================================
-- TRIGGER 2: Validar jerarquía PKI al actualizar certificado
-- ============================================
CREATE TRIGGER trg_validate_certificate_hierarchy_before_update
BEFORE UPDATE ON certificates
FOR EACH ROW
BEGIN
    -- No permitir cambios en campos críticos de PKI
    IF OLD.is_ca != NEW.is_ca THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede cambiar is_ca de un certificado existente';
    END IF;
    
    IF OLD.cert_level != NEW.cert_level THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede cambiar cert_level de un certificado existente';
    END IF;
    
    IF OLD.issuer_certificate_id != NEW.issuer_certificate_id 
       OR (OLD.issuer_certificate_id IS NULL AND NEW.issuer_certificate_id IS NOT NULL)
       OR (OLD.issuer_certificate_id IS NOT NULL AND NEW.issuer_certificate_id IS NULL) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede cambiar el emisor de un certificado existente';
    END IF;
    
    IF OLD.key_id != NEW.key_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede cambiar la clave de un certificado existente';
    END IF;
END$$

-- ============================================
-- TRIGGER 3: Prevenir eliminación de certificados con hijos
-- ============================================
CREATE TRIGGER trg_prevent_delete_ca_with_children
BEFORE DELETE ON certificates
FOR EACH ROW
BEGIN
    DECLARE child_count INT;
    
    SELECT COUNT(*) INTO child_count
    FROM certificates
    WHERE issuer_certificate_id = OLD.id;
    
    IF child_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede eliminar un certificado CA que tiene certificados hijos';
    END IF;
END$$

-- ============================================
-- TRIGGER 4: Validar crypto_keys al insertar (con modo híbrido)
-- ============================================
CREATE TRIGGER trg_validate_crypto_key_before_insert
BEFORE INSERT ON crypto_keys
FOR EACH ROW
BEGIN
    DECLARE parent_owner_type VARCHAR(20);
    DECLARE parent_cert_level INT;
    DECLARE tenant_mode VARCHAR(20);
    DECLARE tenant_hsm_slot INT;
    
    -- Obtener modo del tenant
    SELECT mode, hsm_slot INTO tenant_mode, tenant_hsm_slot
    FROM tenants
    WHERE id = NEW.tenant_id;
    
    -- Si tiene parent_key_id, validar jerarquía
    IF NEW.parent_key_id IS NOT NULL THEN
        SELECT owner_type, cert_level
        INTO parent_owner_type, parent_cert_level
        FROM crypto_keys
        WHERE id = NEW.parent_key_id;
        
        IF parent_owner_type IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La clave padre (parent_key_id) no existe';
        END IF;
        
        -- Validar que cert_level sea secuencial
        IF NEW.cert_level != (parent_cert_level + 1) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'cert_level de la clave debe ser secuencial (padre + 1)';
        END IF;
        
        -- La clave padre debe pertenecer al nivel superior en la jerarquía
        -- TENANT puede ser padre de ORGANIZATION
        -- ORGANIZATION puede ser padre de ORGANIZATION o USER
        -- USER no puede ser padre
        IF parent_owner_type = 'USER' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Una clave de usuario no puede ser padre de otra clave';
        END IF;
        
        -- VALIDACIÓN HÍBRIDA: Si el tenant es MANAGED, la clave debe estar bajo el root de DigSigna
        IF tenant_mode = 'MANAGED' AND NEW.cert_level = 1 THEN
            -- Validar que el parent sea el root de la plataforma (cert_level=0, owner_type=TENANT del platform)
            IF NOT EXISTS (
                SELECT 1 FROM crypto_keys 
                WHERE id = NEW.parent_key_id 
                AND cert_level = 0 
                AND owner_type = 'TENANT'
                AND hsm_slot = 0
            ) THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Tenant MANAGED debe tener CA bajo DigSigna Platform Root (hsm_slot=0)';
            END IF;
        END IF;
    ELSE
        -- Sin parent_key_id, debe ser root (cert_level=0)
        IF NEW.cert_level != 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Solo claves root (cert_level=0) pueden no tener parent_key_id';
        END IF;
        
        -- Solo TENANT puede tener claves root
        IF NEW.owner_type != 'TENANT' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Solo el TENANT puede tener claves root (cert_level=0)';
        END IF;
        
        -- VALIDACIÓN HÍBRIDA: Solo tenants INDEPENDENT pueden crear root CA propias
        IF tenant_mode = 'MANAGED' THEN
            -- Verificar si es el platform root (hsm_slot=0)
            IF tenant_hsm_slot != 0 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Solo tenants INDEPENDENT pueden crear Root CA propias. Tenant MANAGED debe usar Intermediate CA';
            END IF;
        END IF;
        
        -- Si es INDEPENDENT, debe usar hsm_slot dedicado (> 0)
        IF tenant_mode = 'INDEPENDENT' AND NEW.hsm_slot = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Tenant INDEPENDENT debe usar hsm_slot dedicado (> 0)';
        END IF;
    END IF;
    
    -- Validar cert_level no negativo
    IF NEW.cert_level < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'cert_level no puede ser negativo';
    END IF;
    
    -- Validar que hsm_slot coincida con el del tenant (para MANAGED)
    IF tenant_mode = 'MANAGED' AND NEW.hsm_slot != 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Claves de tenant MANAGED deben usar hsm_slot=0 (compartido)';
    END IF;
END$$

-- ============================================
-- TRIGGER 5: Validar organización activa al crear clave
-- ============================================
CREATE TRIGGER trg_validate_organization_for_key
BEFORE INSERT ON crypto_keys
FOR EACH ROW
BEGIN
    DECLARE org_status VARCHAR(20);
    
    -- Si el owner es una organización, validar que esté activa
    IF NEW.owner_type = 'ORGANIZATION' THEN
        SELECT status INTO org_status
        FROM organizations
        WHERE id = NEW.owner_id;
        
        IF org_status IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La organización propietaria no existe';
        END IF;
        
        IF org_status != 'ACTIVE' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede crear clave para organización inactiva';
        END IF;
    END IF;
    
    -- Si el owner es un usuario, validar que esté activo
    IF NEW.owner_type = 'USER' THEN
        IF NOT EXISTS (
            SELECT 1 FROM users 
            WHERE id = NEW.owner_id 
            AND status = 'ACTIVE'
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El usuario propietario no existe o no está activo';
        END IF;
    END IF;
END$$

-- ============================================
-- TRIGGER 6: Prevenir eliminación de claves con hijos
-- ============================================
CREATE TRIGGER trg_prevent_delete_key_with_children
BEFORE DELETE ON crypto_keys
FOR EACH ROW
BEGIN
    DECLARE child_count INT;
    
    SELECT COUNT(*) INTO child_count
    FROM crypto_keys
    WHERE parent_key_id = OLD.id;
    
    IF child_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede eliminar una clave que tiene claves hijas en la jerarquía PKI';
    END IF;
END$$

DELIMITER ;

-- Habilitar FK nuevamente
SET FOREIGN_KEY_CHECKS = 1;

-- ============================================
-- MENSAJE FINAL
-- ============================================
SELECT 'Base de datos DigSigna inicializada correctamente con triggers PKI' AS message;
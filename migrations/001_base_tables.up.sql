-- ============================================
-- TABLAS BASE: Tenants, Organizations, Users, Roles
-- ============================================

-- Deshabilitar FK temporalmente
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
    -- Legacy integer slot kept nullable during migration flow; mapping to `hsm_slots` is handled by later migrations.
    hsm_slot INT NULL DEFAULT NULL,
    
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
-- 2. ORGANIZATIONS - Municipios, Empresas, Colegios, etc.
-- ============================================
DROP TABLE IF EXISTS organizations;
CREATE TABLE organizations (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    parent_id CHAR(36),
    
    -- Tipo y datos básicos
    type VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    legal_name VARCHAR(255),
    description TEXT,
    
    -- Identificación fiscal/legal
    tax_id VARCHAR(50),
    country_code VARCHAR(2) DEFAULT 'MX',
    
    -- Jerarquía
    level INT NOT NULL DEFAULT 0,
    
    -- Estado y suspensión
    status ENUM('ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING_ACTIVATION') DEFAULT 'PENDING_ACTIVATION',
    suspended_reason VARCHAR(255),
    suspended_at TIMESTAMP(6),
    
    -- Plan y facturación
    plan_type ENUM('free', 'basic', 'professional', 'enterprise', 'custom'),
    billing_email VARCHAR(255),
    
    -- Metadata flexible
    metadata JSON,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (parent_id) REFERENCES organizations(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_organizations_tenant_name (tenant_id, name),
    INDEX idx_organizations_tax_id (tax_id),
    INDEX idx_organizations_tenant (tenant_id, type),
    INDEX idx_organizations_parent (parent_id),
    INDEX idx_organizations_level (level),
    INDEX idx_organizations_status (tenant_id, status),
    INDEX idx_organizations_plan (plan_type),
    INDEX idx_organizations_country (country_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 3. ROLES Y PERMISOS
-- ============================================
DROP TABLE IF EXISTS roles;
CREATE TABLE roles (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    is_system_role BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    UNIQUE(tenant_id, name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS permissions;
CREATE TABLE permissions (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    code VARCHAR(100) NOT NULL UNIQUE,
    description TEXT NOT NULL,
    module VARCHAR(50) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS role_permissions;
CREATE TABLE role_permissions (
    role_id CHAR(36) NOT NULL,
    permission_id CHAR(36) NOT NULL,
    granted_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    PRIMARY KEY (role_id, permission_id),
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
    FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 4. USERS
-- ============================================
DROP TABLE IF EXISTS users;
CREATE TABLE users (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    organization_id CHAR(36),
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
    
    UNIQUE KEY uk_users_tenant_email (tenant_id, email),
    INDEX idx_users_tenant_status (tenant_id, status),
    INDEX idx_users_organization (organization_id),
    INDEX idx_users_external (tenant_id, identity_provider, external_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS user_roles;
CREATE TABLE user_roles (
    user_id CHAR(36) NOT NULL,
    role_id CHAR(36) NOT NULL,
    assigned_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    assigned_by CHAR(36),
    
    PRIMARY KEY (user_id, role_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
    FOREIGN KEY (assigned_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TABLE IF EXISTS user_permissions;
CREATE TABLE user_permissions (
    user_id CHAR(36) NOT NULL,
    permission_id CHAR(36) NOT NULL,
    is_granted BOOLEAN NOT NULL DEFAULT TRUE,
    granted_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    PRIMARY KEY (user_id, permission_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 5. USER_SESSIONS
-- ============================================
DROP TABLE IF EXISTS user_sessions;
CREATE TABLE user_sessions (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    user_id CHAR(36) NOT NULL,
    tenant_id CHAR(36) NOT NULL,
    
    session_token CHAR(64) NOT NULL,
    refresh_token CHAR(64),
    
    device_info JSON,
    ip_address VARCHAR(45),
    user_agent VARCHAR(500),
    
    issued_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    expires_at TIMESTAMP(6) NOT NULL,
    revoked_at TIMESTAMP(6) NULL,
    revocation_reason VARCHAR(255),
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_session_token (session_token),
    INDEX idx_sessions_user (user_id, created_at DESC),
    INDEX idx_sessions_expires (expires_at),
    INDEX idx_sessions_tenant (tenant_id, revoked_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 6. IDENTITY_DOCUMENTS
-- ============================================
DROP TABLE IF EXISTS identity_documents;
CREATE TABLE identity_documents (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    user_id CHAR(36) NOT NULL,
    
    type ENUM('INE', 'PASSPORT', 'DRIVER_LICENSE', 'CURP', 'RFC') NOT NULL,
    number VARCHAR(100) NOT NULL,
    issuing_country VARCHAR(2) DEFAULT 'MX',
    
    issued_at DATE,
    expires_at DATE,
    
    document_hash VARCHAR(255),
    verification_level ENUM('LOW', 'MEDIUM', 'HIGH') DEFAULT 'LOW',
    
    metadata JSON,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_identity_docs_user_type (user_id, type),
    INDEX idx_identity_docs_tenant (tenant_id, type),
    INDEX idx_identity_docs_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Habilitar FK nuevamente
SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Tablas base creadas correctamente' AS message;

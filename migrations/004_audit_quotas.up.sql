-- ============================================
-- AUDITORÍA Y CUOTAS
-- ============================================

SET FOREIGN_KEY_CHECKS = 0;

USE digsigna;

-- ============================================
-- 1. AUDIT_LOGS - Auditoría del sistema
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
    
    -- Referencias (NULLables para auditoría de operaciones fallidas)
    tenant_id CHAR(36),
    organization_id CHAR(36),
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
    
    INDEX idx_audit_tenant_created (tenant_id, created_at DESC),
    INDEX idx_audit_organization (organization_id, created_at DESC),
    INDEX idx_audit_service_action (service_name, event_action, created_at DESC),
    INDEX idx_audit_correlation (correlation_id),
    INDEX idx_audit_actor (actor_type, actor_id),
    INDEX idx_audit_created (created_at DESC),
    INDEX idx_audit_success (success, created_at),
    INDEX idx_audit_resource (resource_type, resource_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 2. AUDIT_METADATA - Metadata adicional de auditoría
-- ============================================
DROP TABLE IF EXISTS audit_metadata;
CREATE TABLE audit_metadata (
    audit_log_id CHAR(36) NOT NULL,
    meta_key VARCHAR(100) NOT NULL,
    meta_value JSON,
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    PRIMARY KEY (audit_log_id, meta_key),
    FOREIGN KEY (audit_log_id) REFERENCES audit_logs(id) ON DELETE CASCADE,
    
    INDEX idx_audit_meta_key (meta_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 3. TENANT_QUOTAS - Cuotas y límites
-- ============================================
DROP TABLE IF EXISTS tenant_quotas;
CREATE TABLE tenant_quotas (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    
    quota_type ENUM(
        'USERS',
        'KEYS',
        'SIGNATURES',
        'VERIFICATIONS',
        'STORAGE_MB',
        'API_CALLS',
        'CERTIFICATES'
    ) NOT NULL,
    
    max_limit INT NOT NULL,
    warning_threshold INT DEFAULT 0,
    
    reset_period ENUM('NONE', 'DAILY', 'MONTHLY', 'YEARLY') DEFAULT 'NONE',
    last_reset_at TIMESTAMP(6),
    next_reset_at TIMESTAMP(6),
    
    is_active BOOLEAN DEFAULT TRUE,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_tenant_quota_type (tenant_id, quota_type),
    INDEX idx_tenant_quota_active (tenant_id, is_active),
    INDEX idx_tenant_quota_type (quota_type, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 4. TENANT_USAGE - Consumo en tiempo real
-- ============================================
DROP TABLE IF EXISTS tenant_usage;
CREATE TABLE tenant_usage (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    quota_type ENUM(
        'USERS', 'KEYS', 'SIGNATURES', 'VERIFICATIONS',
        'STORAGE_MB', 'API_CALLS', 'CERTIFICATES'
    ) NOT NULL,
    
    current_usage INT DEFAULT 0,
    period_usage INT DEFAULT 0,
    
    last_increment_at TIMESTAMP(6),
    last_decrement_at TIMESTAMP(6),
    last_reset_at TIMESTAMP(6),  -- Cuándo se reinició el período (para MONTHLY)
    
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_tenant_usage_type (tenant_id, quota_type),
    INDEX idx_tenant_usage_type (tenant_id, quota_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 5. TENANT_USAGE_HISTORY - Auditoría de consumo
-- ============================================
DROP TABLE IF EXISTS tenant_usage_history;
CREATE TABLE tenant_usage_history (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    quota_type ENUM(
        'USERS', 'KEYS', 'SIGNATURES', 'VERIFICATIONS',
        'STORAGE_MB', 'API_CALLS', 'CERTIFICATES'
    ) NOT NULL,
    
    action ENUM('INCREMENT', 'DECREMENT', 'RESET', 'LIMIT_REACHED') NOT NULL,
    previous_value INT NOT NULL,
    new_value INT NOT NULL,
    delta INT NOT NULL,
    
    resource_id CHAR(36),
    resource_type VARCHAR(50),
    user_id CHAR(36),
    
    limit_reached BOOLEAN DEFAULT FALSE,
    max_limit INT,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    
    INDEX idx_usage_history_tenant (tenant_id, created_at DESC),
    INDEX idx_usage_history_type (quota_type, created_at DESC),
    INDEX idx_usage_history_resource (resource_type, resource_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Tablas de auditoría y cuotas creadas correctamente' AS message;

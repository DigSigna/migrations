USE digsigna;

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
    
    UNIQUE KEY uk_tenant_usage_type (tenant_id, quota_type),
    
    INDEX idx_usage_tenant_type (tenant_id, quota_type)
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
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    
    INDEX idx_usage_history_tenant (tenant_id, created_at DESC),
    INDEX idx_usage_history_type (quota_type, created_at DESC),
    INDEX idx_usage_history_resource (resource_type, resource_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
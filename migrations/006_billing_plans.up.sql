-- ============================================
-- BILLING & PLANS: Planes, Suscripciones, Facturación
-- ============================================

SET FOREIGN_KEY_CHECKS = 0;

USE digsigna;

-- ============================================
-- 1. PLANS - Catálogo de planes
-- ============================================
DROP TABLE IF EXISTS plans;
CREATE TABLE plans (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    
    -- Identificación
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    
    -- Tipo y categoría
    plan_type ENUM('FREE', 'PAID', 'TRIAL', 'CUSTOM', 'WHITE_LABEL') NOT NULL,
    target_audience ENUM('INDIVIDUAL', 'SMALL_BUSINESS', 'ENTERPRISE', 'RESELLER') DEFAULT 'INDIVIDUAL',
    
    -- Precios
    price DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    currency VARCHAR(3) DEFAULT 'USD',
    billing_period ENUM('MONTHLY', 'QUARTERLY', 'YEARLY', 'LIFETIME', 'ONE_TIME') DEFAULT 'MONTHLY',
    
    -- Trial
    trial_days INT DEFAULT 0,
    
    -- Features (JSON para flexibilidad)
    features JSON,
    
    -- Quotas incluidas
    max_users INT DEFAULT -1,  -- -1 = ilimitado
    max_keys INT DEFAULT -1,
    max_signatures INT DEFAULT -1,
    max_storage_mb INT DEFAULT -1,
    max_api_calls INT DEFAULT -1,
    max_certificates INT DEFAULT -1,
    
    -- Estado y vigencia
    is_active BOOLEAN DEFAULT TRUE,
    is_public BOOLEAN DEFAULT TRUE,  -- Visible en página de precios
    valid_from DATE,
    valid_until DATE,
    
    -- Orden de visualización
    display_order INT DEFAULT 0,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    INDEX idx_plans_type (plan_type, is_active),
    INDEX idx_plans_public (is_public, is_active),
    INDEX idx_plans_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 2. PLAN_FEATURES - Features específicos por plan (alternativa a JSON)
-- ============================================
DROP TABLE IF EXISTS plan_features;
CREATE TABLE plan_features (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    plan_id CHAR(36) NOT NULL,
    
    feature_key VARCHAR(100) NOT NULL,
    feature_value VARCHAR(255),
    feature_type ENUM('BOOLEAN', 'INTEGER', 'STRING', 'JSON') DEFAULT 'BOOLEAN',
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (plan_id) REFERENCES plans(id) ON DELETE CASCADE,
    
    UNIQUE KEY uk_plan_features (plan_id, feature_key),
    INDEX idx_plan_features_key (feature_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 3. TENANT_SUBSCRIPTIONS - Suscripciones activas
-- ============================================
DROP TABLE IF EXISTS tenant_subscriptions;
CREATE TABLE tenant_subscriptions (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    plan_id CHAR(36) NOT NULL,
    
    -- Estado de suscripción
    status ENUM('ACTIVE', 'TRIALING', 'PAST_DUE', 'CANCELLED', 'EXPIRED', 'SUSPENDED') DEFAULT 'ACTIVE',
    
    -- Fechas
    started_at TIMESTAMP(6) NOT NULL,
    trial_ends_at TIMESTAMP(6),
    current_period_start TIMESTAMP(6) NOT NULL,
    current_period_end TIMESTAMP(6) NOT NULL,
    cancelled_at TIMESTAMP(6),
    expires_at TIMESTAMP(6),
    
    -- Auto-renovación
    auto_renew BOOLEAN DEFAULT TRUE,
    next_billing_date DATE,
    
    -- Customización de quotas (sobreescribe las del plan)
    custom_max_users INT,
    custom_max_keys INT,
    custom_max_signatures INT,
    custom_max_storage_mb INT,
    custom_max_api_calls INT,
    custom_max_certificates INT,
    
    -- Metadata
    metadata JSON,
    cancellation_reason VARCHAR(255),
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (plan_id) REFERENCES plans(id) ON DELETE RESTRICT,
    
    INDEX idx_subscriptions_tenant (tenant_id, status),
    INDEX idx_subscriptions_status (status, current_period_end),
    INDEX idx_subscriptions_billing (next_billing_date, auto_renew)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 4. SUBSCRIPTION_HISTORY - Historial de cambios
-- ============================================
DROP TABLE IF EXISTS subscription_history;
CREATE TABLE subscription_history (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    subscription_id CHAR(36) NOT NULL,
    
    -- Tipo de evento
    event_type ENUM(
        'CREATED', 'RENEWED', 'UPGRADED', 'DOWNGRADED', 
        'CANCELLED', 'EXPIRED', 'REACTIVATED', 'SUSPENDED'
    ) NOT NULL,
    
    -- Planes involucrados
    from_plan_id CHAR(36),
    to_plan_id CHAR(36),
    
    -- Detalles
    reason VARCHAR(255),
    performed_by CHAR(36),  -- ID del usuario que realizó el cambio
    
    -- Valores antes/después (JSON)
    before_state JSON,
    after_state JSON,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (subscription_id) REFERENCES tenant_subscriptions(id) ON DELETE CASCADE,
    FOREIGN KEY (from_plan_id) REFERENCES plans(id) ON DELETE SET NULL,
    FOREIGN KEY (to_plan_id) REFERENCES plans(id) ON DELETE SET NULL,
    FOREIGN KEY (performed_by) REFERENCES users(id) ON DELETE SET NULL,
    
    INDEX idx_subscription_history_tenant (tenant_id, created_at DESC),
    INDEX idx_subscription_history_subscription (subscription_id, created_at DESC),
    INDEX idx_subscription_history_event (event_type, created_at DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 5. INVOICES - Facturas
-- ============================================
DROP TABLE IF EXISTS invoices;
CREATE TABLE invoices (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    subscription_id CHAR(36),
    
    -- Número de factura
    invoice_number VARCHAR(50) NOT NULL UNIQUE,
    
    -- Montos
    subtotal DECIMAL(10,2) NOT NULL,
    tax DECIMAL(10,2) DEFAULT 0.00,
    discount DECIMAL(10,2) DEFAULT 0.00,
    total DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    
    -- Estado
    status ENUM('DRAFT', 'PENDING', 'PAID', 'FAILED', 'REFUNDED', 'CANCELLED') DEFAULT 'PENDING',
    
    -- Fechas
    issued_at TIMESTAMP(6) NOT NULL,
    due_date DATE NOT NULL,
    paid_at TIMESTAMP(6),
    
    -- Información de facturación
    billing_name VARCHAR(255),
    billing_email VARCHAR(255),
    billing_address TEXT,
    tax_id VARCHAR(50),
    
    -- Detalles de la factura (JSON para line items)
    line_items JSON,
    
    -- Notas
    notes TEXT,
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (subscription_id) REFERENCES tenant_subscriptions(id) ON DELETE SET NULL,
    
    INDEX idx_invoices_tenant (tenant_id, issued_at DESC),
    INDEX idx_invoices_status (status, due_date),
    INDEX idx_invoices_number (invoice_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- 6. PAYMENTS - Pagos
-- ============================================
DROP TABLE IF EXISTS payments;
CREATE TABLE payments (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    invoice_id CHAR(36),
    
    -- Monto
    amount DECIMAL(10,2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'USD',
    
    -- Método de pago
    payment_method ENUM('CREDIT_CARD', 'DEBIT_CARD', 'PAYPAL', 'BANK_TRANSFER', 'STRIPE', 'MANUAL', 'OTHER') NOT NULL,
    
    -- Gateway de pago
    payment_gateway VARCHAR(50),  -- 'stripe', 'paypal', 'conekta', etc.
    transaction_id VARCHAR(255),  -- ID del gateway externo
    
    -- Estado
    status ENUM('PENDING', 'PROCESSING', 'COMPLETED', 'FAILED', 'REFUNDED') DEFAULT 'PENDING',
    
    -- Detalles
    payment_details JSON,  -- Info adicional del gateway
    failure_reason VARCHAR(255),
    
    -- Fechas
    processed_at TIMESTAMP(6),
    refunded_at TIMESTAMP(6),
    
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (invoice_id) REFERENCES invoices(id) ON DELETE SET NULL,
    
    INDEX idx_payments_tenant (tenant_id, created_at DESC),
    INDEX idx_payments_invoice (invoice_id),
    INDEX idx_payments_status (status, processed_at),
    INDEX idx_payments_transaction (payment_gateway, transaction_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Tablas de billing y planes creadas correctamente' AS message;

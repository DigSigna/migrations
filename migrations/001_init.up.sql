-- ============================================
-- Tenants (master table)
-- ============================================
CREATE TABLE IF NOT EXISTS tenants (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    contact_email VARCHAR(255),
    plan_type VARCHAR(50) DEFAULT 'free',
    status VARCHAR(50) DEFAULT 'active',
    configuration JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
-- seed data
INSERT INTO tenants (id, name, contact_email, plan_type, status, configuration)
VALUES ('00000000-0000-0000-0000-000000000001', 'Default Tenant', 'admin@example.com', 'free', 'active', '{}')
ON DUPLICATE KEY UPDATE name=name;

-- ============================================
-- Users (shared across microservices)
-- ============================================
CREATE TABLE IF NOT EXISTS users (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255),
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

CREATE INDEX idx_users_tenant_id ON users(tenant_id);
-- seed data
INSERT INTO users (id,tenant_id,email,password_hash,first_name,last_name)
	VALUES ('00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','admin@example.com','hashed_password','Admin','User')
ON DUPLICATE KEY UPDATE email=email;

-- crypto_keys stored or managed by the HSM
CREATE TABLE IF NOT EXISTS crypto_keys (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36) NOT NULL,
    name VARCHAR(255) NOT NULL,
    algorithm VARCHAR(50) NOT NULL,
    key_type VARCHAR(50),         -- RSA, ECC, AES
    purpose VARCHAR(50),          -- SIGNING, ENCRYPTION
    is_hardware_backed BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id) REFERENCES tenants(id)
);

CREATE INDEX idx_crypto_keys_tenant_id ON crypto_keys(tenant_id);


-- Optional: key attributes (padding, curve, key_size)
CREATE TABLE IF NOT EXISTS key_metadata (
    id VARCHAR(36) PRIMARY KEY,
    key_id VARCHAR(36) NOT NULL,
    meta_key VARCHAR(255) NOT NULL,
    meta_value VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (key_id) REFERENCES crypto_keys(id)
);

CREATE TABLE IF NOT EXISTS identity_documents (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36) NOT NULL,
    type VARCHAR(50) NOT NULL,     -- INE, passport, driver_license
    number VARCHAR(100),
    issued_at DATE,
    expires_at DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_identity_docs_tenant ON identity_documents(tenant_id);


CREATE TABLE IF NOT EXISTS certificates (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36),
    key_id VARCHAR(36),
    csr TEXT,
    certificate_pem TEXT,
    status VARCHAR(50) DEFAULT 'PENDING', -- PENDING, ISSUED, REVOKED
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id)
);

CREATE INDEX idx_certificates_tenant ON certificates(tenant_id);

CREATE TABLE IF NOT EXISTS signing_requests (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36),
    key_id VARCHAR(36),
    document_hash VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'PENDING', 
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (key_id) REFERENCES crypto_keys(id)
);

CREATE INDEX idx_sign_req_tenant ON signing_requests(tenant_id);


CREATE TABLE IF NOT EXISTS signatures (
    id VARCHAR(36) PRIMARY KEY,
    signing_request_id VARCHAR(36) NOT NULL,
    signature_base64 TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (signing_request_id) REFERENCES signing_requests(id)
);

CREATE TABLE IF NOT EXISTS verifications (
    id VARCHAR(36) PRIMARY KEY,
    tenant_id VARCHAR(36) NOT NULL,
    signature_id VARCHAR(36),
    document_hash VARCHAR(255),
    is_valid BOOLEAN,
    reason VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (signature_id) REFERENCES signatures(id)
);

CREATE INDEX idx_verif_tenant ON verifications(tenant_id);

CREATE TABLE IF NOT EXISTS audit_logs (
    id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
    tenant_id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36),
    event VARCHAR(255) NOT NULL,
    payload JSON,
    resource_id VARCHAR(36),
    resource_type VARCHAR(100),
    details TEXT,
    ip_address VARCHAR(45),
    user_agent VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (tenant_id) REFERENCES tenants(id),
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_audit_tenant ON audit_logs(tenant_id);

CREATE TABLE IF NOT EXISTS key_permissions (
    id VARCHAR(36) PRIMARY KEY,
    key_id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36) NOT NULL,
    can_sign BOOLEAN DEFAULT FALSE,
    can_encrypt BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (key_id) REFERENCES crypto_keys(id),
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_key_permissions_key ON key_permissions(key_id);
CREATE INDEX idx_key_permissions_user ON key_permissions(user_id);

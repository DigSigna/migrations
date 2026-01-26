-- ============================================
-- HSM SLOTS + AES KEY METADATA
-- ============================================

USE digsigna;

SET FOREIGN_KEY_CHECKS = 0;

-- 1. AES KEY METADATA (metadatos de las claves AES usadas para encriptar PINs)
DROP TABLE IF EXISTS aes_key_metadata;
CREATE TABLE aes_key_metadata (
    version_id VARCHAR(10) PRIMARY KEY,     -- e.g. "v1", "v2"
    active BOOLEAN NOT NULL DEFAULT FALSE,   -- Solo una activa a la vez (enforzado por trigger)
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    algorithm VARCHAR(50),                  -- e.g. "aes-256-gcm"
    source VARCHAR(255),                    -- origen de la llave (p.ej. "k8s-secret/hsm-keys")
    description TEXT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Trigger: Garantizar que solo una fila tenga active=TRUE
DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_insert;
CREATE TRIGGER trg_aes_key_metadata_after_insert
AFTER INSERT ON aes_key_metadata
FOR EACH ROW
BEGIN
    IF NEW.active = TRUE THEN
        UPDATE aes_key_metadata
        SET active = FALSE
        WHERE version_id != NEW.version_id AND active = TRUE;
    END IF;
END;

DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_update;
CREATE TRIGGER trg_aes_key_metadata_after_update
AFTER UPDATE ON aes_key_metadata
FOR EACH ROW
BEGIN
    IF NEW.active = TRUE THEN
        UPDATE aes_key_metadata
        SET active = FALSE
        WHERE version_id != NEW.version_id AND active = TRUE;
    END IF;
END;

-- 2. HSM SLOTS (datos del slot, NO almacenar aquí la clave AES en claro)
DROP TABLE IF EXISTS hsm_slots;
CREATE TABLE hsm_slots (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    tenant_id CHAR(36) NOT NULL,
    label VARCHAR(255) NOT NULL,
    slot_number INT NOT NULL,
    encrypted_pin VARBINARY(512) NOT NULL,           -- AES-GCM ciphertext del PIN
    key_version_id VARCHAR(10) NOT NULL,    -- referencia a aes_key_metadata.version_id
    encryption_context JSON,               -- {"tenant": ..., "algorithm": ..., "derived": true}
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    FOREIGN KEY (key_version_id) REFERENCES aes_key_metadata(version_id) ON DELETE RESTRICT,
    UNIQUE KEY uk_hsm_slots_tenant_slot (tenant_id, slot_number),
    INDEX idx_tenant (tenant_id),
    INDEX idx_key_version (key_version_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'HSM slots and AES key metadata created' AS message;

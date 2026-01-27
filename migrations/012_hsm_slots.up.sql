-- ============================================
-- HSM SLOTS + AES KEY METADATA
-- ============================================

USE digsigna;

SET FOREIGN_KEY_CHECKS = 0;

-- 1. HSM SLOTS (datos del slot, NO almacenar aquí la clave AES en claro)
DROP TABLE IF EXISTS hsm_slots;
CREATE TABLE hsm_slots (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    label VARCHAR(255) NOT NULL,
    slot_number INT NOT NULL,
    -- Split AES-GCM encrypted PIN into its components: IV (nonce), ciphertext and auth tag
    pin_iv VARBINARY(12) NULL COMMENT 'IV/nonce for AES-GCM (12 bytes)',
    pin_ciphertext VARBINARY(1024) NULL COMMENT 'AES-GCM ciphertext of the PIN',
    pin_auth_tag VARBINARY(32) NULL COMMENT 'Authentication tag for AES-GCM (e.g. 16 bytes)',
    key_metadata_id CHAR(36) NULL,                    -- referencia opcional a aes_key_metadata.id
    encryption_context JSON,                          -- {"algorithm": ..., "derived": true}
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    UNIQUE KEY uk_hsm_slots_slot_number (slot_number),
    INDEX idx_key_metadata (key_metadata_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'HSM slots and AES key metadata created' AS message;

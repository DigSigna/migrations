-- ============================================
-- Migrate hsm_slot INT -> hsm_slot_id CHAR(36) (FK to hsm_slots)
-- ============================================

USE digsigna;

SET FOREIGN_KEY_CHECKS = 0;

-- 1) Create slot-scoped AES key metadata
DROP TABLE IF EXISTS aes_key_metadata;
CREATE TABLE aes_key_metadata (
    id CHAR(36) PRIMARY KEY DEFAULT (UUID()),
    hsm_slot_id CHAR(36) NOT NULL,
    version_id VARCHAR(50) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT FALSE,
    algorithm VARCHAR(50),
    source VARCHAR(255),
    description TEXT,
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    FOREIGN KEY (hsm_slot_id) REFERENCES hsm_slots(id) ON DELETE CASCADE,
    UNIQUE KEY uk_aes_key_metadata_slot_version (hsm_slot_id, version_id),
    INDEX idx_aes_key_metadata_slot (hsm_slot_id),
    INDEX idx_aes_key_metadata_version (version_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2) Add FK from hsm_slots.key_metadata_id to aes_key_metadata.id
ALTER TABLE hsm_slots
    ADD CONSTRAINT fk_hsm_slots_key_metadata FOREIGN KEY (key_metadata_id) REFERENCES aes_key_metadata(id) ON DELETE RESTRICT;
-- 3) Triggers: enforce single-active per slot
DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_insert;
CREATE TRIGGER trg_aes_key_metadata_after_insert
AFTER INSERT ON aes_key_metadata
FOR EACH ROW
BEGIN
    IF NEW.active = TRUE THEN
        UPDATE aes_key_metadata
        SET active = FALSE
        WHERE hsm_slot_id = NEW.hsm_slot_id AND id != NEW.id AND active = TRUE;
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
        WHERE hsm_slot_id = NEW.hsm_slot_id AND id != NEW.id AND active = TRUE;
    END IF;
END;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Migration 013 applied: aes_key_metadata created and linked to hsm_slots' AS message;

-- ============================================
-- Rollback migration 014: restore previous aes_key_metadata design and hsm_slots.key_version_id
-- ============================================

USE digsigna;

SET FOREIGN_KEY_CHECKS = 0;

-- Remove triggers
DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_update;
DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_insert;

-- Remove FK from hsm_slots and drop new column
ALTER TABLE hsm_slots DROP FOREIGN KEY fk_hsm_slots_key_metadata;
ALTER TABLE hsm_slots DROP COLUMN key_metadata_id;

-- Recreate old aes_key_metadata structure (version_id as PK)
DROP TABLE IF EXISTS aes_key_metadata;
CREATE TABLE aes_key_metadata (
    version_id VARCHAR(10) PRIMARY KEY,
    active BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6),
    updated_at TIMESTAMP(6) DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
    algorithm VARCHAR(50),
    source VARCHAR(255),
    description TEXT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Recreate previous key_version_id column on hsm_slots
ALTER TABLE hsm_slots ADD COLUMN key_version_id VARCHAR(10) NULL;
ALTER TABLE hsm_slots
    ADD CONSTRAINT fk_hsm_slots_key_version FOREIGN KEY (key_version_id) REFERENCES aes_key_metadata(version_id) ON DELETE RESTRICT;

-- Recreate original triggers that disabled all versions (legacy behavior)
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

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Migration 014 rolled back' AS message;

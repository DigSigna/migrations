-- ============================================
-- Rollback migration 013: restore previous hsm_slot INT columns and triggers
-- ============================================

USE digsigna;

SET FOREIGN_KEY_CHECKS = 0;

-- Drop triggers and FK from hsm_slots
DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_update;
DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_insert;

ALTER TABLE hsm_slots DROP FOREIGN KEY fk_hsm_slots_key_metadata;

-- Drop aes_key_metadata table
DROP TABLE IF EXISTS aes_key_metadata;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Migration 013 rolled back' AS message;

-- ============================================
-- Rollback: HSM SLOTS + AES KEY METADATA
-- ============================================

USE digsigna;

SET FOREIGN_KEY_CHECKS = 0;

-- Remove triggers first
DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_update;
DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_insert;

-- Drop tables
DROP TABLE IF EXISTS hsm_slots;
DROP TABLE IF EXISTS aes_key_metadata;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'HSM slots and AES key metadata dropped' AS message;

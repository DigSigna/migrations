-- ============================================
-- Rollback migration 013: restore previous hsm_slot INT columns and triggers
-- ============================================

USE digsigna;

SET FOREIGN_KEY_CHECKS = 0;

-- Drop updated trigger
DROP TRIGGER IF EXISTS trg_validate_crypto_key_before_insert;

-- Drop foreign keys
ALTER TABLE crypto_keys DROP FOREIGN KEY IF EXISTS fk_crypto_keys_hsm_slot_id;
ALTER TABLE tenants DROP FOREIGN KEY IF EXISTS fk_tenants_hsm_slot_id;

-- Drop new columns
ALTER TABLE crypto_keys DROP COLUMN IF EXISTS hsm_slot_id;
ALTER TABLE tenants DROP COLUMN IF EXISTS hsm_slot_id;

-- Recreate original integer columns (defaulting to 0)
ALTER TABLE tenants ADD COLUMN hsm_slot INT NOT NULL DEFAULT 0;
ALTER TABLE crypto_keys ADD COLUMN hsm_slot INT NOT NULL DEFAULT 0;

-- Note: original trigger definitions should be reapplied from 005_pki_triggers.up.sql if needed

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Migration 013 rolled back' AS message;

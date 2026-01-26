-- ============================================
-- Rollback: HSM SLOTS + AES KEY METADATA
-- ============================================

USE digsigna;

SET FOREIGN_KEY_CHECKS = 0;

-- Drop table hsm_slots
DROP TABLE IF EXISTS hsm_slots;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'HSM slots and AES key metadata dropped' AS message;

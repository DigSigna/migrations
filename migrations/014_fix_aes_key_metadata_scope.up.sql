-- ============================================
-- Fix AES key metadata: make metadata scoped per HSM slot
-- ============================================

USE digsigna;

SET FOREIGN_KEY_CHECKS = 0;

-- 014: Add hsm_slot_id references to tenants and crypto_keys and populate from legacy integer hsm_slot

-- 1) Add columns
ALTER TABLE tenants ADD COLUMN hsm_slot_id CHAR(36) NULL;
CREATE INDEX idx_tenants_hsm_slot_id ON tenants(hsm_slot_id);

-- crypto_keys already declares `hsm_slot_id` in earlier migration (002).
-- If not present, it should be added in a prior migration. We avoid adding it again here to prevent duplicate column errors.

INSERT INTO hsm_slots (id, label, slot_number, pin_iv, pin_ciphertext, pin_auth_tag, created_at)
SELECT UUID(), CONCAT('slot-', CAST(src.hsm_slot AS CHAR)), src.hsm_slot, x'', x'', x'', CURRENT_TIMESTAMP(6)
FROM (
    SELECT DISTINCT hsm_slot FROM tenants WHERE hsm_slot IS NOT NULL
) AS src
LEFT JOIN hsm_slots hs ON hs.slot_number = src.hsm_slot
WHERE hs.id IS NULL;

-- 3) Map tenants and crypto_keys to slot IDs
UPDATE tenants t
JOIN hsm_slots hs ON hs.slot_number = t.hsm_slot
SET t.hsm_slot_id = hs.id
WHERE t.hsm_slot IS NOT NULL;

-- Map crypto_keys to slot IDs using the tenant mapping (safer: crypto_keys belong to tenants)
UPDATE crypto_keys ck
JOIN tenants t ON ck.tenant_id = t.id
JOIN hsm_slots hs ON hs.id = t.hsm_slot_id
SET ck.hsm_slot_id = hs.id
WHERE t.hsm_slot_id IS NOT NULL;

-- 3.5) Seed: create an HSM slot for the first tenant and initial AES metadata (idempotent)
-- Drop AES metadata triggers temporarily to avoid trigger-side table-modification conflicts
DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_insert;
DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_update;

-- This will:
--  - pick the earliest-created tenant (if any), use its legacy hsm_slot integer (or 0 if NULL)
--  - insert an hsm_slots row for that slot_number if missing
--  - insert an aes_key_metadata row (version 'v1') for that slot if missing and mark it active
--  - link hsm_slots.key_metadata_id -> aes_key_metadata.id and set tenants.hsm_slot_id for the tenant

SET @first_tenant_id = (SELECT id FROM tenants ORDER BY created_at LIMIT 1);
SET @first_tenant_slot = (SELECT hsm_slot FROM tenants ORDER BY created_at LIMIT 1);
SET @first_tenant_slot = IFNULL(@first_tenant_slot, 0);

INSERT INTO hsm_slots (id, label, slot_number, pin_iv, pin_ciphertext, pin_auth_tag, created_at)
SELECT UUID(), CONCAT('slot-', CAST(@first_tenant_slot AS CHAR)), @first_tenant_slot, x'', x'', x'', CURRENT_TIMESTAMP(6)
FROM DUAL
WHERE @first_tenant_id IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM hsm_slots WHERE slot_number = @first_tenant_slot);

-- Obtain the hsm_slot id we just ensured exists
SET @seed_hsm_slot_id = (SELECT id FROM hsm_slots WHERE slot_number = @first_tenant_slot LIMIT 1);

-- Insert initial AES metadata for that slot (version 'v1') if missing
-- To avoid trigger conflict (the aes_key_metadata triggers update the same table),
-- first read any existing metadata id into @seed_meta_id, then conditionally insert only when NULL.
SET @seed_meta_id = NULL;
SELECT id INTO @seed_meta_id FROM aes_key_metadata WHERE hsm_slot_id = @seed_hsm_slot_id AND version_id = 'v1' LIMIT 1;

INSERT INTO aes_key_metadata (id, hsm_slot_id, version_id, active, algorithm, source, description, wrapped_data_key, wrap_key_version, last_rewrap_at, created_at)
SELECT UUID(), @seed_hsm_slot_id, 'v1', TRUE, 'AES-GCM', 'migrated-seed', 'Initial AES metadata for slot', NULL, 'master-v1', NULL, CURRENT_TIMESTAMP(6)
FROM DUAL
WHERE @first_tenant_id IS NOT NULL
    AND @seed_hsm_slot_id IS NOT NULL
    AND @seed_meta_id IS NULL;

-- Obtain the metadata id (existing or newly created)
SET @seed_meta_id = NULL;
SELECT id INTO @seed_meta_id FROM aes_key_metadata WHERE hsm_slot_id = @seed_hsm_slot_id AND version_id = 'v1' LIMIT 1;

-- Link hsm_slots.key_metadata_id to the metadata row
UPDATE hsm_slots SET key_metadata_id = @seed_meta_id WHERE id = @seed_hsm_slot_id AND @seed_meta_id IS NOT NULL;

-- Point the first tenant to this hsm_slot_id
UPDATE tenants SET hsm_slot_id = @seed_hsm_slot_id WHERE id = @first_tenant_id AND @seed_hsm_slot_id IS NOT NULL;

-- Recreate AES metadata triggers (same behavior as defined in migration 013)
DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_insert;
CREATE TRIGGER trg_aes_key_metadata_after_insert
AFTER INSERT ON aes_key_metadata
FOR EACH ROW
BEGIN
    -- allow controlled suppression of trigger logic from the session by setting @skip_aes_triggers = 1
    IF COALESCE(@skip_aes_triggers, 0) = 0 THEN
        IF NEW.active = TRUE THEN
            UPDATE aes_key_metadata
            SET active = FALSE
            WHERE hsm_slot_id = NEW.hsm_slot_id AND id != NEW.id AND active = TRUE;
        END IF;
    END IF;
END;

DROP TRIGGER IF EXISTS trg_aes_key_metadata_after_update;
CREATE TRIGGER trg_aes_key_metadata_after_update
AFTER UPDATE ON aes_key_metadata
FOR EACH ROW
BEGIN
    -- allow controlled suppression of trigger logic from the session by setting @skip_aes_triggers = 1
    IF COALESCE(@skip_aes_triggers, 0) = 0 THEN
        IF NEW.active = TRUE THEN
            UPDATE aes_key_metadata
            SET active = FALSE
            WHERE hsm_slot_id = NEW.hsm_slot_id AND id != NEW.id AND active = TRUE;
        END IF;
    END IF;
END;

-- 4) Add FK constraints
ALTER TABLE tenants ADD CONSTRAINT fk_tenants_hsm_slot_id FOREIGN KEY (hsm_slot_id) REFERENCES hsm_slots(id) ON DELETE SET NULL;
ALTER TABLE crypto_keys ADD CONSTRAINT fk_crypto_keys_hsm_slot_id FOREIGN KEY (hsm_slot_id) REFERENCES hsm_slots(id) ON DELETE SET NULL;

-- 5) Cleanup legacy integer columns now that mapping and FKs exist
-- Drop legacy hsm_slot INT columns from tenants and crypto_keys to avoid technical debt
-- Use conditional prepared statements to avoid 'IF EXISTS' syntax which may not be supported
-- Check tenants.hsm_slot and drop it only if present
SET @stmt = (
    SELECT IF(
        (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tenants' AND COLUMN_NAME = 'hsm_slot') > 0,
        'ALTER TABLE tenants DROP COLUMN hsm_slot',
        'SELECT 1'
    )
);
PREPARE conditional_stmt FROM @stmt;
EXECUTE conditional_stmt;
DEALLOCATE PREPARE conditional_stmt;

-- Check crypto_keys.hsm_slot and drop it only if present
SET @stmt = (
    SELECT IF(
        (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'crypto_keys' AND COLUMN_NAME = 'hsm_slot') > 0,
        'ALTER TABLE crypto_keys DROP COLUMN hsm_slot',
        'SELECT 1'
    )
);
PREPARE conditional_stmt FROM @stmt;
EXECUTE conditional_stmt;
DEALLOCATE PREPARE conditional_stmt;

-- 6) Replace PKI crypto_keys BEFORE INSERT trigger to use hsm_slot_id exclusively
DROP TRIGGER IF EXISTS trg_validate_crypto_key_before_insert;
CREATE TRIGGER trg_validate_crypto_key_before_insert
BEFORE INSERT ON crypto_keys
FOR EACH ROW
BEGIN
    DECLARE parent_owner_type VARCHAR(20);
    DECLARE parent_cert_level INT;
    DECLARE tenant_mode VARCHAR(20);
    DECLARE tenant_hsm_slot_id CHAR(36);
    DECLARE parent_hsm_slot_id CHAR(36);

    -- Obtener modo del tenant y su hsm_slot_id
    SELECT mode, hsm_slot_id INTO tenant_mode, tenant_hsm_slot_id FROM tenants WHERE id = NEW.tenant_id;

    -- Si tiene parent_key_id, validar jerarquía
    IF NEW.parent_key_id IS NOT NULL THEN
        SELECT owner_type, cert_level, hsm_slot_id
        INTO parent_owner_type, parent_cert_level, parent_hsm_slot_id
        FROM crypto_keys
        WHERE id = NEW.parent_key_id;

        IF parent_owner_type IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La clave padre (parent_key_id) no existe';
        END IF;

        IF NEW.cert_level != (parent_cert_level + 1) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'cert_level de la clave debe ser secuencial (padre + 1)';
        END IF;

        IF parent_owner_type = 'USER' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Una clave de usuario no puede ser padre de otra clave';
        END IF;

        -- Para tenants MANAGED, exigir que el parent root esté en slot_number = 0
        IF tenant_mode = 'MANAGED' AND NEW.cert_level = 1 THEN
            IF NOT EXISTS (
                SELECT 1 FROM crypto_keys pk
                JOIN hsm_slots hs ON pk.hsm_slot_id = hs.id
                WHERE pk.id = NEW.parent_key_id
                  AND pk.cert_level = 0
                  AND pk.owner_type = 'TENANT'
                  AND hs.slot_number = 0
            ) THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Tenant MANAGED debe tener CA bajo DigSigna Platform Root (slot 0)';
            END IF;
        END IF;
    ELSE
        -- Sin parent_key_id, debe ser root (cert_level=0) y sólo TENANT
        IF NEW.cert_level != 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Solo claves root (cert_level=0) pueden no tener parent_key_id';
        END IF;

        IF NEW.owner_type != 'TENANT' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Solo el TENANT puede tener claves root (cert_level=0)';
        END IF;

        -- Si tenant es INDEPENDENT, exigir hsm_slot_id que no apunte a slot_number = 0
        IF tenant_mode = 'INDEPENDENT' THEN
            IF NEW.hsm_slot_id IS NULL OR EXISTS (SELECT 1 FROM hsm_slots WHERE id = NEW.hsm_slot_id AND slot_number = 0) THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Tenant INDEPENDENT debe usar hsm_slot dedicado (> 0)';
            END IF;
        END IF;
    END IF;

    IF NEW.cert_level < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'cert_level no puede ser negativo';
    END IF;

    -- Para tenants MANAGED, la clave debe apuntar a slot_number = 0
    IF tenant_mode = 'MANAGED' THEN
        IF NEW.hsm_slot_id IS NULL OR NOT EXISTS (SELECT 1 FROM hsm_slots WHERE id = NEW.hsm_slot_id AND slot_number = 0) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Claves de tenant MANAGED deben usar slot compartido (slot 0)';
        END IF;
    END IF;
END;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Migration 014 applied: tenants and crypto_keys now reference hsm_slots via hsm_slot_id and legacy hsm_slot columns removed' AS message;

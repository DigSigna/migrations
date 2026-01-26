-- ============================================
-- Rollback migration 014: restore previous aes_key_metadata design and hsm_slots.key_version_id
-- ============================================

USE digsigna;

SET FOREIGN_KEY_CHECKS = 0;

-- Rollback mapping of tenants/crypto_keys to hsm_slots
SET FOREIGN_KEY_CHECKS = 0;

ALTER TABLE crypto_keys DROP FOREIGN KEY fk_crypto_keys_hsm_slot_id;
ALTER TABLE tenants DROP FOREIGN KEY fk_tenants_hsm_slot_id;

-- Recreate legacy integer columns to restore previous state
ALTER TABLE crypto_keys ADD COLUMN hsm_slot INT NULL;
CREATE INDEX idx_crypto_keys_hsm_slot ON crypto_keys(hsm_slot);

ALTER TABLE tenants ADD COLUMN hsm_slot INT NULL;
CREATE INDEX idx_tenants_hsm_slot ON tenants(hsm_slot);

ALTER TABLE crypto_keys DROP COLUMN hsm_slot_id;
ALTER TABLE tenants DROP COLUMN hsm_slot_id;

-- Restore previous trigger that used legacy hsm_slot INT semantics
DROP TRIGGER IF EXISTS trg_validate_crypto_key_before_insert;
CREATE TRIGGER trg_validate_crypto_key_before_insert
BEFORE INSERT ON crypto_keys
FOR EACH ROW
BEGIN
	DECLARE parent_owner_type VARCHAR(20);
	DECLARE parent_cert_level INT;
	DECLARE tenant_mode VARCHAR(20);
	DECLARE tenant_hsm_slot INT;

	-- Obtener modo del tenant
	SELECT mode, hsm_slot INTO tenant_mode, tenant_hsm_slot
	FROM tenants
	WHERE id = NEW.tenant_id;

	IF NEW.parent_key_id IS NOT NULL THEN
		SELECT owner_type, cert_level
		INTO parent_owner_type, parent_cert_level
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

		IF tenant_mode = 'MANAGED' AND NEW.cert_level = 1 THEN
			IF NOT EXISTS (
				SELECT 1 FROM crypto_keys 
				WHERE id = NEW.parent_key_id 
				AND cert_level = 0 
				AND owner_type = 'TENANT'
				AND hsm_slot = 0
			) THEN
				SIGNAL SQLSTATE '45000'
				SET MESSAGE_TEXT = 'Tenant MANAGED debe tener CA bajo DigSigna Platform Root (hsm_slot=0)';
			END IF;
		END IF;
	ELSE
		IF NEW.cert_level != 0 THEN
			SIGNAL SQLSTATE '45000'
			SET MESSAGE_TEXT = 'Solo claves root (cert_level=0) pueden no tener parent_key_id';
		END IF;

		IF NEW.owner_type != 'TENANT' THEN
			SIGNAL SQLSTATE '45000'
			SET MESSAGE_TEXT = 'Solo el TENANT puede tener claves root (cert_level=0)';
		END IF;

		IF tenant_mode = 'MANAGED' THEN
			IF tenant_hsm_slot != 0 THEN
				SIGNAL SQLSTATE '45000'
				SET MESSAGE_TEXT = 'Solo tenants INDEPENDENT pueden crear Root CA propias. Tenant MANAGED debe usar Intermediate CA';
			END IF;
		END IF;

		IF tenant_mode = 'INDEPENDENT' AND NEW.hsm_slot = 0 THEN
			SIGNAL SQLSTATE '45000'
			SET MESSAGE_TEXT = 'Tenant INDEPENDENT debe usar hsm_slot dedicado (> 0)';
		END IF;
	END IF;

	IF NEW.cert_level < 0 THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'cert_level no puede ser negativo';
	END IF;

	IF tenant_mode = 'MANAGED' AND NEW.hsm_slot != 0 THEN
		SIGNAL SQLSTATE '45000'
		SET MESSAGE_TEXT = 'Claves de tenant MANAGED deben usar hsm_slot=0 (compartido)';
	END IF;
END;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Migration 014 rolled back: removed hsm_slot_id columns and constraints' AS message;

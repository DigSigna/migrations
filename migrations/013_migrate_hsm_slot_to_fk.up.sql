-- ============================================
-- Migrate hsm_slot INT -> hsm_slot_id CHAR(36) (FK to hsm_slots)
-- ============================================

USE digsigna;

SET FOREIGN_KEY_CHECKS = 0;

-- 1) Alter tenants: hsm_slot INT -> hsm_slot_id CHAR(36)
ALTER TABLE tenants
    ADD COLUMN hsm_slot_id CHAR(36) NULL;

-- Index and FK will be added after population (safe order)
CREATE INDEX idx_tenants_hsm_slot_id ON tenants(hsm_slot_id);

-- 2) Alter crypto_keys: hsm_slot INT -> hsm_slot_id CHAR(36)
ALTER TABLE crypto_keys
    ADD COLUMN hsm_slot_id CHAR(36) NULL;
CREATE INDEX idx_crypto_keys_hsm_slot_id ON crypto_keys(hsm_slot_id);

-- 3) Optional: If you have existing hsm_slots rows, populate mapping from integers
-- Since this project is in development and DB can be re-created, we do not attempt automatic population here.
-- If you want automatic population, uncomment and use the UPDATE below when appropriate.
-- UPDATE crypto_keys ck
-- JOIN hsm_slots hs ON hs.tenant_id = ck.tenant_id AND hs.slot_number = ck.hsm_slot
-- SET ck.hsm_slot_id = hs.id
-- WHERE ck.hsm_slot IS NOT NULL;

-- UPDATE tenants t
-- JOIN hsm_slots hs ON hs.tenant_id = t.id AND hs.slot_number = t.hsm_slot
-- SET t.hsm_slot_id = hs.id
-- WHERE t.hsm_slot IS NOT NULL;

-- 4) Add FK constraints (deferred until population to avoid violations)
ALTER TABLE tenants
    ADD CONSTRAINT fk_tenants_hsm_slot_id FOREIGN KEY (hsm_slot_id) REFERENCES hsm_slots(id) ON DELETE SET NULL;

ALTER TABLE crypto_keys
    ADD CONSTRAINT fk_crypto_keys_hsm_slot_id FOREIGN KEY (hsm_slot_id) REFERENCES hsm_slots(id) ON DELETE SET NULL;

-- 5) Replace trigger trg_validate_crypto_key_before_insert with updated logic (uses hsm_slot_id and slot_number checks)
DROP TRIGGER IF EXISTS trg_validate_crypto_key_before_insert;
CREATE TRIGGER trg_validate_crypto_key_before_insert
BEFORE INSERT ON crypto_keys
FOR EACH ROW
BEGIN
    DECLARE parent_owner_type VARCHAR(20);
    DECLARE parent_cert_level INT;
    DECLARE tenant_mode VARCHAR(20);
    DECLARE tenant_hsm_slot_id CHAR(36);
    DECLARE tenant_hsm_slot_num INT;
    DECLARE new_hsm_slot_num INT;

    -- Obtener modo del tenant y su referencia al slot (ahora un id)
    SELECT mode, hsm_slot_id INTO tenant_mode, tenant_hsm_slot_id
    FROM tenants
    WHERE id = NEW.tenant_id;

    -- Derivar número de slot si existe
    IF tenant_hsm_slot_id IS NOT NULL THEN
        SELECT slot_number INTO tenant_hsm_slot_num FROM hsm_slots WHERE id = tenant_hsm_slot_id;
    ELSE
        SET tenant_hsm_slot_num = NULL;
    END IF;

    IF NEW.parent_key_id IS NOT NULL THEN
        SELECT owner_type, cert_level
        INTO parent_owner_type, parent_cert_level
        FROM crypto_keys
        WHERE id = NEW.parent_key_id;

        IF parent_owner_type IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La clave padre (parent_key_id) no existe';
        END IF;

        -- Validar que cert_level sea secuencial
        IF NEW.cert_level != (parent_cert_level + 1) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'cert_level de la clave debe ser secuencial (padre + 1)';
        END IF;

        -- La clave padre debe pertenecer al nivel superior en la jerarquía
        IF parent_owner_type = 'USER' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Una clave de usuario no puede ser padre de otra clave';
        END IF;

        -- VALIDACIÓN HÍBRIDA: Si el tenant es MANAGED, la clave debe estar bajo el root de DigSigna (slot_number = 0)
        IF tenant_mode = 'MANAGED' AND NEW.cert_level = 1 THEN
            IF NOT EXISTS (
                SELECT 1 FROM crypto_keys ck
                JOIN hsm_slots hs ON ck.hsm_slot_id = hs.id
                WHERE ck.id = NEW.parent_key_id
                AND ck.cert_level = 0
                AND ck.owner_type = 'TENANT'
                AND hs.slot_number = 0
            ) THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Tenant MANAGED debe tener CA bajo DigSigna Platform Root (slot_number=0)';
            END IF;
        END IF;
    ELSE
        -- Sin parent_key_id, debe ser root (cert_level=0)
        IF NEW.cert_level != 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Solo claves root (cert_level=0) pueden no tener parent_key_id';
        END IF;

        -- Solo TENANT puede tener claves root
        IF NEW.owner_type != 'TENANT' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Solo el TENANT puede tener claves root (cert_level=0)';
        END IF;

        -- VALIDACIÓN HÍBRIDA: Solo tenants INDEPENDENT pueden crear root CA propias
        IF tenant_mode = 'MANAGED' THEN
            IF tenant_hsm_slot_num IS NOT NULL AND tenant_hsm_slot_num != 0 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Solo tenants INDEPENDENT pueden crear Root CA propias. Tenant MANAGED debe usar Intermediate CA';
            END IF;
        END IF;

        -- If tenant is INDEPENDENT, the referenced slot for the new key must be > 0
        IF tenant_mode = 'INDEPENDENT' THEN
            IF NEW.hsm_slot_id IS NULL THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Tenant INDEPENDENT debe especificar hsm_slot_id dedicado (> slot 0)';
            ELSE
                SELECT slot_number INTO new_hsm_slot_num FROM hsm_slots WHERE id = NEW.hsm_slot_id;
                IF new_hsm_slot_num IS NULL OR new_hsm_slot_num = 0 THEN
                    SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'Tenant INDEPENDENT debe usar hsm_slot dedicado (slot_number > 0)';
                END IF;
            END IF;
        END IF;
    END IF;

    -- Validar cert_level no negativo
    IF NEW.cert_level < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'cert_level no puede ser negativo';
    END IF;

    -- Validar que hsm_slot_id coincida con el del tenant (para MANAGED)
    IF tenant_mode = 'MANAGED' AND NEW.hsm_slot_id IS NOT NULL THEN
        SELECT slot_number INTO new_hsm_slot_num FROM hsm_slots WHERE id = NEW.hsm_slot_id;
        IF new_hsm_slot_num IS NULL OR new_hsm_slot_num != 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Claves de tenant MANAGED deben usar un hsm_slot con slot_number=0 (compartido)';
        END IF;
    END IF;
END;

SET FOREIGN_KEY_CHECKS = 1;

SELECT 'Migration 013 applied: hsm_slot columns added and trigger updated' AS message;

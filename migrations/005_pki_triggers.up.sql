-- ============================================
-- TRIGGERS DE VALIDACIÓN PKI
-- ============================================

USE digsigna;

-- ============================================
-- TRIGGER 1: Validar jerarquía PKI al insertar certificado
-- ============================================
CREATE TRIGGER trg_validate_certificate_hierarchy_before_insert
BEFORE INSERT ON certificates
FOR EACH ROW
BEGIN
    DECLARE parent_is_ca BOOLEAN;
    DECLARE parent_path_length INT;
    DECLARE parent_cert_level INT;
    DECLARE key_owner_type VARCHAR(20);
    DECLARE key_owner_id CHAR(36);
    DECLARE key_cert_level INT;
    
    -- Validar consistencia con crypto_keys
    SELECT owner_type, owner_id, cert_level
    INTO key_owner_type, key_owner_id, key_cert_level
    FROM crypto_keys
    WHERE id = NEW.key_id;
    
    IF key_owner_type IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'La clave criptográfica no existe';
    END IF;
    
    -- Validar que owner coincida
    IF key_owner_type != NEW.owner_type OR key_owner_id != NEW.owner_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'El propietario del certificado no coincide con el de la clave';
    END IF;
    
    -- Validar que cert_level coincida
    IF key_cert_level != NEW.cert_level THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'cert_level del certificado debe coincidir con el de la clave';
    END IF;
    
    -- Si tiene emisor, validar la cadena
    IF NEW.issuer_certificate_id IS NOT NULL THEN
        SELECT is_ca, path_length, cert_level
        INTO parent_is_ca, parent_path_length, parent_cert_level
        FROM certificates
        WHERE id = NEW.issuer_certificate_id;
        
        IF parent_is_ca IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El certificado emisor no existe';
        END IF;
        
        -- 1. El emisor DEBE ser una CA
        IF parent_is_ca = FALSE THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El certificado emisor no es una CA (is_ca=FALSE)';
        END IF;
        
        -- 2. Si el nuevo certificado es CA, validar path_length del emisor
        IF NEW.is_ca = TRUE THEN
            IF parent_path_length IS NOT NULL AND parent_path_length < 1 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'El emisor no puede firmar CAs intermedias (path_length < 1)';
            END IF;
            
            -- El path_length del hijo debe ser menor
            IF NEW.path_length IS NOT NULL AND parent_path_length IS NOT NULL THEN
                IF NEW.path_length >= parent_path_length THEN
                    SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = 'path_length del certificado hijo debe ser menor que el del padre';
                END IF;
            END IF;
        END IF;
        
        -- 3. Validar que cert_level sea secuencial
        IF NEW.cert_level != (parent_cert_level + 1) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'cert_level debe ser secuencial (padre + 1)';
        END IF;
        
        -- 4. Validar que issuer_key_id corresponda al certificado emisor
        IF NEW.issuer_key_id IS NOT NULL THEN
            IF NOT EXISTS (
                SELECT 1 FROM certificates 
                WHERE id = NEW.issuer_certificate_id 
                AND key_id = NEW.issuer_key_id
            ) THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'issuer_key_id no corresponde con el key_id del certificado emisor';
            END IF;
        END IF;
        
        -- 5. Validar que el emisor no esté revocado o expirado
        IF EXISTS (
            SELECT 1 FROM certificates 
            WHERE id = NEW.issuer_certificate_id 
            AND (status = 'REVOKED' OR status = 'EXPIRED')
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede emitir certificado: el emisor está revocado o expirado';
        END IF;
    ELSE
        -- Si no tiene emisor, DEBE ser root (cert_level=0)
        IF NEW.cert_level != 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Solo certificados root (cert_level=0) pueden no tener emisor';
        END IF;
        
        -- Root debe ser CA
        IF NEW.is_ca = FALSE THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Certificados root deben ser CA (is_ca=TRUE)';
        END IF;
    END IF;
    
    -- Validar path_length si es CA
    IF NEW.is_ca = TRUE THEN
        IF NEW.path_length IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'path_length es requerido para certificados CA';
        END IF;
        
        IF NEW.path_length < 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'path_length no puede ser negativo';
        END IF;
    ELSE
        -- End-entities no deben tener path_length
        IF NEW.path_length IS NOT NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Certificados end-entity (is_ca=FALSE) no deben tener path_length';
        END IF;
    END IF;
END;

-- ============================================
-- TRIGGER 2: Validar jerarquía PKI al actualizar certificado
-- ============================================
CREATE TRIGGER trg_validate_certificate_hierarchy_before_update
BEFORE UPDATE ON certificates
FOR EACH ROW
BEGIN
    -- No permitir cambios en campos críticos de PKI
    IF OLD.is_ca != NEW.is_ca THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede cambiar is_ca de un certificado existente';
    END IF;
    
    IF OLD.cert_level != NEW.cert_level THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede cambiar cert_level de un certificado existente';
    END IF;
    
    IF OLD.issuer_certificate_id != NEW.issuer_certificate_id 
       OR (OLD.issuer_certificate_id IS NULL AND NEW.issuer_certificate_id IS NOT NULL)
       OR (OLD.issuer_certificate_id IS NOT NULL AND NEW.issuer_certificate_id IS NULL) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede cambiar el emisor de un certificado existente';
    END IF;
    
    IF OLD.key_id != NEW.key_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede cambiar la clave de un certificado existente';
    END IF;
END;

-- ============================================
-- TRIGGER 3: Prevenir eliminación de certificados con hijos
-- ============================================
CREATE TRIGGER trg_prevent_delete_ca_with_children
BEFORE DELETE ON certificates
FOR EACH ROW
BEGIN
    DECLARE child_count INT;
    
    SELECT COUNT(*) INTO child_count
    FROM certificates
    WHERE issuer_certificate_id = OLD.id;
    
    IF child_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede eliminar un certificado CA que tiene certificados hijos';
    END IF;
END;

-- ============================================
-- TRIGGER 4: Validar crypto_keys al insertar (con modo híbrido)
-- ============================================
-- NOTE: La validación y trigger para inserción en `crypto_keys` se migra y crea en
-- la migración 014 (`014_fix_aes_key_metadata_scope.up.sql`) para garantizar que
-- los campos y la tabla `hsm_slots` existan antes de crear las reglas que los
-- referencian. Mantener la lógica en 014 evita errores al aplicar migraciones en
-- orden sobre una BD vacía.

CREATE TRIGGER trg_validate_organization_for_key
BEFORE INSERT ON crypto_keys
FOR EACH ROW
BEGIN
    DECLARE org_status VARCHAR(20);
    
    -- Si el owner es una organización, validar que esté activa
    IF NEW.owner_type = 'ORGANIZATION' THEN
        SELECT status INTO org_status
        FROM organizations
        WHERE id = NEW.owner_id;
        
        IF org_status IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La organización propietaria no existe';
        END IF;
        
        IF org_status != 'ACTIVE' THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No se puede crear clave para organización inactiva';
        END IF;
    END IF;
    
    -- Si el owner es un usuario, validar que esté activo
    IF NEW.owner_type = 'USER' THEN
        IF NOT EXISTS (
            SELECT 1 FROM users 
            WHERE id = NEW.owner_id 
            AND status = 'ACTIVE'
        ) THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'El usuario propietario no existe o no está activo';
        END IF;
    END IF;
END;

-- ============================================
-- TRIGGER 6: Prevenir eliminación de claves con hijos
-- ============================================
CREATE TRIGGER trg_prevent_delete_key_with_children
BEFORE DELETE ON crypto_keys
FOR EACH ROW
BEGIN
    DECLARE child_count INT;
    
    SELECT COUNT(*) INTO child_count
    FROM crypto_keys
    WHERE parent_key_id = OLD.id;
    
    IF child_count > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'No se puede eliminar una clave que tiene claves hijas en la jerarquía PKI';
    END IF;
END;

SELECT 'Triggers PKI creados correctamente' AS message;

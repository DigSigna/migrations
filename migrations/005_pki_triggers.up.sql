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
    
    -- Si tiene parent_key_id, validar jerarquía
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
        
        -- VALIDACIÓN HÍBRIDA: Si el tenant es MANAGED, la clave debe estar bajo el root de DigSigna
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
            IF tenant_hsm_slot != 0 THEN
                SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Solo tenants INDEPENDENT pueden crear Root CA propias. Tenant MANAGED debe usar Intermediate CA';
            END IF;
        END IF;
        
        -- Si es INDEPENDENT, debe usar hsm_slot dedicado (> 0)
        IF tenant_mode = 'INDEPENDENT' AND NEW.hsm_slot = 0 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Tenant INDEPENDENT debe usar hsm_slot dedicado (> 0)';
        END IF;
    END IF;
    
    -- Validar cert_level no negativo
    IF NEW.cert_level < 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'cert_level no puede ser negativo';
    END IF;
    
    -- Validar que hsm_slot coincida con el del tenant (para MANAGED)
    IF tenant_mode = 'MANAGED' AND NEW.hsm_slot != 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Claves de tenant MANAGED deben usar hsm_slot=0 (compartido)';
    END IF;
END;

-- ============================================
-- TRIGGER 5: Validar organización activa al crear clave
-- ============================================
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

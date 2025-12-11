USE digsigna;
-- ============================================
-- PERMISOS Y ROLES DE BASE DE DATOS 
-- ============================================
-- TODO THIS MUST BE RUN BY A DIFFERENT JOB AND MIGRATION 

-- Crear usuario de aplicación (ajusta la contraseña)
CREATE USER IF NOT EXISTS 'digsigna_app'@'%' IDENTIFIED BY 'StrongPassword123!';
GRANT SELECT, INSERT, UPDATE, DELETE ON digsigna.* TO 'digsigna_app'@'%';

-- Usuario de solo lectura para reportes
CREATE USER IF NOT EXISTS 'digsigna_report'@'%' IDENTIFIED BY 'ReportPassword123!';
GRANT SELECT ON digsigna.* TO 'digsigna_report'@'%';
GRANT SELECT ON digsigna.vw_recent_audit TO 'digsigna_report'@'%';

-- Usuario de mantenimiento
CREATE USER IF NOT EXISTS 'digsigna_maint'@'localhost' IDENTIFIED BY 'MaintenancePassword123!';
GRANT ALL PRIVILEGES ON digsigna.* TO 'digsigna_maint'@'localhost';
GRANT EXECUTE ON digsigna.* TO 'digsigna_maint'@'localhost';
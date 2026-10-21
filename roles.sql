USE COMPUCOMISIONES;
GO

CREATE ROLE registrador;
CREATE ROLE moderador;
CREATE ROLE administrador;
GO

-- Registradores
GRANT SELECT, INSERT, UPDATE ON comisiones_schema.persona TO registrador;
GRANT SELECT, INSERT, UPDATE ON comisiones_schema.vendedor TO registrador;
GRANT SELECT, INSERT, UPDATE ON comisiones_schema.supervisor TO registrador;
GRANT SELECT, INSERT, UPDATE ON comisiones_schema.finanzas TO registrador;
GRANT SELECT, INSERT, UPDATE ON comisiones_schema.factura TO registrador;
GRANT SELECT, INSERT, UPDATE ON comisiones_schema.detalle_factura TO registrador;
GRANT SELECT, INSERT, UPDATE ON comisiones_schema.participacion_factura TO registrador;

-- Moderadores
GRANT SELECT ON SCHEMA::comisiones_schema TO moderador;

-- Administradores
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::comisiones_schema TO administrador;
GRANT EXECUTE ON SCHEMA::comisiones_schema TO administrador;
GO

CREATE LOGIN login_registrador WITH PASSWORD = 'Registrador#2026', DEFAULT_DATABASE = COMPUCOMISIONES;
CREATE LOGIN login_moderador WITH PASSWORD = 'Moderador#2026', DEFAULT_DATABASE = COMPUCOMISIONES;
CREATE LOGIN login_administrador WITH PASSWORD = 'Administrador#2026', DEFAULT_DATABASE = COMPUCOMISIONES;
GO

CREATE USER usuario_registrador FOR LOGIN login_registrador WITH DEFAULT_SCHEMA = comisiones_schema;
CREATE USER usuario_moderador FOR LOGIN login_moderador WITH DEFAULT_SCHEMA = comisiones_schema;
CREATE USER usuario_administrador FOR LOGIN login_administrador WITH DEFAULT_SCHEMA = comisiones_schema;
GO

ALTER ROLE registrador ADD MEMBER usuario_registrador;
ALTER ROLE moderador ADD MEMBER usuario_moderador;
ALTER ROLE administrador ADD MEMBER usuario_administrador;
GO

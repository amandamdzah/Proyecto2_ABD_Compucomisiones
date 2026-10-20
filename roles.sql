
CREATE SCHEMA comisiones_schema;
GO

CREATE LOGIN [PropietarioCompucomisiones] 
WITH PASSWORD = '<Mortadela123>', 
CHECK_POLICY = ON;
GO

ALTER LOGIN [PropietarioCompucomisiones] DISABLE;
GO

CREATE USER [UsuarioPropietario] FOR LOGIN [PropietarioCompucomisiones];
GO

CREATE ROLE registrador;
CREATE ROLE moderador;
CREATE ROLE administrador;
GO

-- Registradores
GRANT INSERT, UPDATE ON persona TO registrador;
GRANT INSERT, UPDATE ON factura TO registrador;
GRANT INSERT, UPDATE ON participacion_factura TO registrador;

-- Moderadores
GRANT SELECT ON SCHEMA::dbo TO moderador; 

-- Administradores
GRANT CONTROL ON SCHEMA::dbo TO administrador;
GO
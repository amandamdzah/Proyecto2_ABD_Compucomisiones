USE master;
GO

DECLARE @ruta NVARCHAR(400);
SET @ruta = CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS NVARCHAR(400)) + '\Backup_CompuComisiones';
EXEC master.sys.xp_create_subdir @ruta;
GO

-- 1. backup completo 
BACKUP DATABASE COMPUCOMISIONES
TO DISK = 'Backup_CompuComisiones\CompuComisiones_FULL.bak'
WITH INIT, CHECKSUM;
GO

RESTORE VERIFYONLY
FROM DISK = 'Backup_CompuComisiones\CompuComisiones_FULL.bak'
WITH CHECKSUM;
GO

-- 2. backup diferencial 
BACKUP DATABASE COMPUCOMISIONES
TO DISK = 'Backup_CompuComisiones\CompuComisiones_DIF.bak'
WITH DIFFERENTIAL, INIT, CHECKSUM;
GO

RESTORE VERIFYONLY
FROM DISK = 'Backup_CompuComisiones\CompuComisiones_DIF.bak'
WITH CHECKSUM;
GO

-- 3. backup del log 
DECLARE @archivo NVARCHAR(400);
SET @archivo = 'Backup_CompuComisiones\CompuComisiones_LOG_' + FORMAT(GETDATE(), 'yyyyMMdd_HHmm') + '.trn';

BACKUP LOG COMPUCOMISIONES
TO DISK = @archivo
WITH CHECKSUM;
GO

-- historial de backups
SELECT type, backup_start_date, backup_finish_date
FROM msdb.dbo.backupset
WHERE database_name = 'COMPUCOMISIONES'
ORDER BY backup_finish_date DESC;
GO

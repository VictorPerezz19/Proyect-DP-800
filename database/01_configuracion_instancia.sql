/* =============================================================================
   01_configuracion_instancia.sql
   -----------------------------------------------------------------------------
   Fase 1. Prepara la instancia de SQL Server 2025 y la base de datos.

   Requisitos previos (ver README.md):
     - SQL Server 2025 (17.x) Developer en Windows.
     - SQL Server Machine Learning Services instalado (servicio Launchpad):
       el runtime ONNX local se ejecuta en el proceso AIRuntimeHost, que lanza
       Launchpad.
     - Carpeta C:\onnx_runtime preparada con scripts\preparar_onnx_runtime.ps1.

   Requiere permiso ALTER SETTINGS (sysadmin) para sp_configure.
   ============================================================================= */
USE master;
GO

-- 1. Comprobaciones de versión y del servicio Launchpad --------------------
SELECT
    SERVERPROPERTY('ProductVersion')      AS VersionProducto,   -- 17.x = SQL Server 2025
    SERVERPROPERTY('Edition')             AS Edicion,
    CASE WHEN CAST(SERVERPROPERTY('ProductMajorVersion') AS INT) >= 17
         THEN N'OK' ELSE N'ERROR: se necesita SQL Server 2025' END AS ComprobacionVersion;

SELECT servicename, status_desc, service_account
FROM sys.dm_server_services
WHERE servicename LIKE N'SQL Server Launchpad%';   -- debe aparecer y estar "Running"
GO

-- 2. Habilitar los runtimes de IA externos (ONNX Runtime local) -------------
--    Sin esta opción, AI_GENERATE_EMBEDDINGS no puede arrancar AIRuntimeHost.
--    NOTA: no se habilita 'external rest endpoint enabled' porque no llamamos a
--    ningún endpoint REST externo (arquitectura 100 % local).
EXECUTE sp_configure 'external AI runtimes enabled', 1;
RECONFIGURE WITH OVERRIDE;
GO

-- 3. Crear la base de datos ------------------------------------------------
IF DB_ID(N'NormativaRAG') IS NULL
    CREATE DATABASE NormativaRAG;
GO

-- 4. Habilitar características en preview en la base de datos ---------------
--    El runtime ONNX local de CREATE EXTERNAL MODEL es una característica en
--    preview de SQL Server 2025 y se activa por base de datos.
USE NormativaRAG;
GO
ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON;
GO

-- 5. Verificación ----------------------------------------------------------
SELECT name, value_in_use
FROM sys.configurations
WHERE name = N'external AI runtimes enabled';

SELECT name, value
FROM sys.database_scoped_configurations
WHERE name = N'PREVIEW_FEATURES';
GO

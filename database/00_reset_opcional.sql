/* =============================================================================
   00_reset_opcional.sql
   -----------------------------------------------------------------------------
   OPCIONAL. Solo hace falta si la base de datos NormativaRAG ya existe con
   objetos de la versión anterior del proyecto (tabla ModelosIA con el ONNX en
   VARBINARY, tabla DocumentosNormativa, política basada en SESSION_CONTEXT) o
   si quieres volver a empezar desde cero.

   Elimina, en orden de dependencias:
     1. Políticas de seguridad (RLS) y funciones de predicado.
     2. Procedimientos, vistas, tablas, usuarios y roles del proyecto.
     3. El modelo externo.
   No elimina la base de datos ni toca la configuración de la instancia.
   ============================================================================= */
USE NormativaRAG;
GO

-- 1. RLS: primero la política (depende de la función) y luego la función
DROP SECURITY POLICY IF EXISTS Seguridad.PoliticaDocumentos;    -- versión anterior
DROP SECURITY POLICY IF EXISTS Seguridad.PoliticaNormativas;
DROP FUNCTION IF EXISTS Seguridad.fn_FiltroAcceso;              -- versión anterior
DROP FUNCTION IF EXISTS Seguridad.fn_PredicadoNormativas;
GO

-- 2. Objetos de la versión actual
DROP PROCEDURE IF EXISTS dbo.usp_BuscarNormativa;
DROP VIEW IF EXISTS dbo.vw_MiPerfil;
DROP TABLE IF EXISTS dbo.Normativas;
DROP TABLE IF EXISTS dbo.Empleados;
DROP TABLE IF EXISTS dbo.Departamentos;
GO

-- El índice full-text se elimina con la tabla; el catálogo hay que borrarlo aparte
IF EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'FTC_Normativas')
    DROP FULLTEXT CATALOG FTC_Normativas;
GO

-- 3. Objetos de la versión anterior
DROP TABLE IF EXISTS dbo.DocumentosNormativa;
DROP TABLE IF EXISTS dbo.ModelosIA;
GO

-- 4. Usuarios de prueba (sin login) y roles
DECLARE @sql NVARCHAR(MAX) = N'';

-- Primero se sacan los miembros de los roles del proyecto
SELECT @sql += N'ALTER ROLE ' + QUOTENAME(r.name) + N' DROP MEMBER ' + QUOTENAME(m.name) + N';' + CHAR(10)
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals AS m ON m.principal_id = rm.member_principal_id
WHERE r.name LIKE N'Rol[_]%';

SELECT @sql += N'DROP USER ' + QUOTENAME(name) + N';' + CHAR(10)
FROM sys.database_principals
WHERE type = 'S'                               -- usuario SQL
  AND authentication_type_desc = 'NONE'        -- creado WITHOUT LOGIN
  AND name IN (N'ana_rrhh', N'carlos_ventas', N'lucia_it', N'marta_direccion', N'invitado_externo');

SELECT @sql += N'DROP ROLE ' + QUOTENAME(name) + N';' + CHAR(10)
FROM sys.database_principals
WHERE type = 'R' AND name LIKE N'Rol[_]%';

EXEC sys.sp_executesql @sql;
GO

-- 5. Modelo externo
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'ModeloEmbeddingsLocal')
    DROP EXTERNAL MODEL ModeloEmbeddingsLocal;
GO

SELECT N'Reset completado. Ejecuta los scripts desde 01 en adelante.' AS Estado;
GO

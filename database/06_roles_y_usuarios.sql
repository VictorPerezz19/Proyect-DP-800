/* =============================================================================
   06_roles_y_usuarios.sql
   -----------------------------------------------------------------------------
   Fase 3. Roles de base de datos y usuarios de prueba.

   - Un rol por departamento (Rol_RRHH, Rol_Ventas, Rol_IT, Rol_Direccion) más
     Rol_Empleado, el rol base que da acceso a las normativas generales.
   - Los usuarios de prueba se crean WITHOUT LOGIN: existen solo en la base de
     datos, no tienen contraseña y no pueden conectarse por su cuenta. Se usan
     con EXECUTE AS USER desde una sesión de administrador (la conexión con
     autenticación de Windows que usa Copilot @mssql). Así se prueba el RLS
     sin crear logins ni guardar contraseñas.
   - Cada usuario se añade de forma explícita a Rol_Empleado y a su rol de
     departamento (no se anidan roles), para que la pertenencia que evalúa
     IS_MEMBER() sea evidente al revisar el script.
   - Mínimo privilegio: los roles solo pueden leer las tablas de normativas y
     departamentos y ejecutar el modelo. El procedimiento de búsqueda se
     concede en 08.
   ============================================================================= */
USE NormativaRAG;
GO

-- 1. Roles ------------------------------------------------------------------
IF DATABASE_PRINCIPAL_ID(N'Rol_Empleado')  IS NULL CREATE ROLE Rol_Empleado;
IF DATABASE_PRINCIPAL_ID(N'Rol_RRHH')      IS NULL CREATE ROLE Rol_RRHH;
IF DATABASE_PRINCIPAL_ID(N'Rol_Ventas')    IS NULL CREATE ROLE Rol_Ventas;
IF DATABASE_PRINCIPAL_ID(N'Rol_IT')        IS NULL CREATE ROLE Rol_IT;
IF DATABASE_PRINCIPAL_ID(N'Rol_Direccion') IS NULL CREATE ROLE Rol_Direccion;
GO

-- 2. Usuarios de prueba sin login ------------------------------------------
IF DATABASE_PRINCIPAL_ID(N'ana_rrhh')         IS NULL CREATE USER ana_rrhh         WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID(N'carlos_ventas')    IS NULL CREATE USER carlos_ventas    WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID(N'lucia_it')         IS NULL CREATE USER lucia_it         WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID(N'marta_direccion')  IS NULL CREATE USER marta_direccion  WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID(N'invitado_externo') IS NULL CREATE USER invitado_externo WITHOUT LOGIN;  -- sin ningún rol
GO

-- 3. Pertenencia a roles ----------------------------------------------------
ALTER ROLE Rol_Empleado  ADD MEMBER ana_rrhh;
ALTER ROLE Rol_RRHH      ADD MEMBER ana_rrhh;

ALTER ROLE Rol_Empleado  ADD MEMBER carlos_ventas;
ALTER ROLE Rol_Ventas    ADD MEMBER carlos_ventas;

ALTER ROLE Rol_Empleado  ADD MEMBER lucia_it;
ALTER ROLE Rol_IT        ADD MEMBER lucia_it;

ALTER ROLE Rol_Empleado  ADD MEMBER marta_direccion;
ALTER ROLE Rol_Direccion ADD MEMBER marta_direccion;
GO

-- 4. Permisos mínimos -------------------------------------------------------
-- Lectura directa de normativas (RLS filtra las filas) y del catálogo de departamentos
GRANT SELECT ON dbo.Normativas    TO Rol_Empleado;
GRANT SELECT ON dbo.Departamentos TO Rol_Empleado;

-- Ejecutar el modelo de embeddings (lo necesita AI_GENERATE_EMBEDDINGS).
-- Imprescindible también para usar el procedimiento: el encadenamiento de propiedad
-- NO cubre los modelos externos (comprobado: sin este GRANT, el procedimiento falla
-- con el error 15151).
GRANT EXECUTE ON EXTERNAL MODEL::ModeloEmbeddingsLocal TO Rol_Empleado;

-- invitado_externo recibe los mismos permisos de objeto pero ningún rol:
-- sirve para demostrar que el permiso de objeto no basta, porque RLS no le
-- devuelve ninguna fila.
GRANT SELECT  ON dbo.Normativas TO invitado_externo;
GRANT EXECUTE ON EXTERNAL MODEL::ModeloEmbeddingsLocal TO invitado_externo;
GO

-- 5. Verificación -----------------------------------------------------------
SELECT r.name AS Rol, m.name AS Miembro
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals AS m ON m.principal_id = rm.member_principal_id
WHERE r.name LIKE N'Rol[_]%'
ORDER BY m.name, r.name;
GO

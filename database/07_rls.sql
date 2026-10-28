/* =============================================================================
   07_rls.sql
   -----------------------------------------------------------------------------
   Fase 3. Row-Level Security sobre dbo.Normativas.

   Funcionamiento:
   - La función de predicado es una TVF inline con SCHEMABINDING que recibe el
     DepartamentoId de cada fila y devuelve una fila (acceso permitido) o
     ninguna (fila invisible).
   - Se usa IS_MEMBER() y no SESSION_CONTEXT: IS_MEMBER evalúa la pertenencia
     real del usuario de base de datos a un rol, que fija el administrador y el
     cliente no puede falsear. SESSION_CONTEXT lo establece la aplicación con
     sp_set_session_context, y Copilot @mssql no tiene una capa de aplicación
     que lo haga de forma fiable. Con IS_MEMBER la seguridad depende solo de la
     identidad de la conexión.
   - El rol que da acceso a cada departamento se lee de dbo.Departamentos.RolBD
     (diseño dirigido por datos). Rol_Empleado da acceso a "General" y
     Rol_Direccion ve todos los departamentos.
   - SECURITY POLICY con FILTER PREDICATE: el motor añade el predicado a todas
     las consultas sobre la tabla (SELECT, UPDATE, DELETE), también dentro de
     procedimientos almacenados. Por eso la búsqueda vectorial de 08 queda
     protegida sin ningún WHERE adicional: el motor descarta las filas no
     autorizadas ANTES de calcular el TOP N por distancia.
   - No se añade BLOCK PREDICATE porque ningún rol tiene permiso de escritura.
   ============================================================================= */
USE NormativaRAG;
GO

IF SCHEMA_ID(N'Seguridad') IS NULL
    EXEC (N'CREATE SCHEMA Seguridad AUTHORIZATION dbo;');
GO

-- Si se vuelve a ejecutar: primero la política, después la función
DROP SECURITY POLICY IF EXISTS Seguridad.PoliticaNormativas;
DROP FUNCTION IF EXISTS Seguridad.fn_PredicadoNormativas;
GO

CREATE FUNCTION Seguridad.fn_PredicadoNormativas (@DepartamentoId INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS Autorizado
    WHERE IS_MEMBER(N'Rol_Direccion') = 1                 -- Dirección ve todo
       OR EXISTS (SELECT 1
                  FROM dbo.Departamentos AS d
                  WHERE d.DepartamentoId = @DepartamentoId
                    AND IS_MEMBER(d.RolBD) = 1);          -- rol del departamento de la fila
GO

CREATE SECURITY POLICY Seguridad.PoliticaNormativas
    ADD FILTER PREDICATE Seguridad.fn_PredicadoNormativas(DepartamentoId) ON dbo.Normativas
    WITH (STATE = ON, SCHEMABINDING = ON);
GO

-- Verificación
SELECT p.name AS Politica, p.is_enabled, pr.predicate_type_desc, pr.predicate_definition,
       OBJECT_NAME(pr.target_object_id) AS Tabla
FROM sys.security_policies   AS p
JOIN sys.security_predicates AS pr ON pr.object_id = p.object_id;
GO

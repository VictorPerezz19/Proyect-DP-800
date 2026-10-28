/* =============================================================================
   09_pruebas_rls.sql
   -----------------------------------------------------------------------------
   Fase 4. Validación: la misma pregunta devuelve resultados distintos según el
   rol de quien la hace.

   Se ejecuta desde la sesión de administrador (autenticación de Windows) y se
   suplanta a cada usuario de prueba con EXECUTE AS USER ... REVERT. Es lo
   mismo que hará Copilot @mssql en la demo (docs/demo_copilot.md).

   Resultados esperados:
     - ana_rrhh          -> solo General + Recursos Humanos
     - carlos_ventas     -> solo General + Ventas
     - lucia_it          -> solo General + Tecnología (IT)
     - marta_direccion   -> todos los departamentos
     - invitado_externo  -> 0 filas (tiene permisos de objeto pero ningún rol)
   ============================================================================= */
USE NormativaRAG;
GO

/* ---------------------------------------------------------------------------
   Prueba 1. Filas visibles por usuario (SELECT directo, sin vectores)
   --------------------------------------------------------------------------- */
EXECUTE AS USER = 'ana_rrhh';
    SELECT USER_NAME() AS Usuario, d.Nombre AS Departamento, COUNT(*) AS Filas
    FROM dbo.Normativas n JOIN dbo.Departamentos d ON d.DepartamentoId = n.DepartamentoId
    GROUP BY d.Nombre;
REVERT;

EXECUTE AS USER = 'carlos_ventas';
    SELECT USER_NAME() AS Usuario, d.Nombre AS Departamento, COUNT(*) AS Filas
    FROM dbo.Normativas n JOIN dbo.Departamentos d ON d.DepartamentoId = n.DepartamentoId
    GROUP BY d.Nombre;
REVERT;

EXECUTE AS USER = 'lucia_it';
    SELECT USER_NAME() AS Usuario, d.Nombre AS Departamento, COUNT(*) AS Filas
    FROM dbo.Normativas n JOIN dbo.Departamentos d ON d.DepartamentoId = n.DepartamentoId
    GROUP BY d.Nombre;
REVERT;

EXECUTE AS USER = 'marta_direccion';
    SELECT USER_NAME() AS Usuario, d.Nombre AS Departamento, COUNT(*) AS Filas
    FROM dbo.Normativas n JOIN dbo.Departamentos d ON d.DepartamentoId = n.DepartamentoId
    GROUP BY d.Nombre;
REVERT;

EXECUTE AS USER = 'invitado_externo';
    SELECT USER_NAME() AS Usuario, COUNT(*) AS FilasVisibles FROM dbo.Normativas;   -- esperado: 0
REVERT;
GO

/* ---------------------------------------------------------------------------
   Prueba 2. Misma pregunta, distinto rol (búsqueda semántica)
   "Mudanza": RRHH e IT reciben la norma general (1 día); Ventas recibe además
   la de traslado por cambio de zona (3 días y gastos pagados).
   --------------------------------------------------------------------------- */
DECLARE @p NVARCHAR(1000) = N'¿Qué días de permiso me corresponden por mudanza según las políticas de mi departamento?';

EXECUTE AS USER = 'ana_rrhh';
    EXEC dbo.usp_BuscarNormativa @Pregunta = @p, @TopN = 3;
REVERT;

EXECUTE AS USER = 'carlos_ventas';
    EXEC dbo.usp_BuscarNormativa @Pregunta = @p, @TopN = 3;
REVERT;
GO

/* ---------------------------------------------------------------------------
   Prueba 3. Teletrabajo: General (2 días), IT (3 días), Ventas (movilidad),
   Dirección (viernes).
   --------------------------------------------------------------------------- */
DECLARE @p NVARCHAR(1000) = N'¿Cuántos días a la semana puedo teletrabajar?';

EXECUTE AS USER = 'lucia_it';
    EXEC dbo.usp_BuscarNormativa @Pregunta = @p, @TopN = 3;
REVERT;

EXECUTE AS USER = 'carlos_ventas';
    EXEC dbo.usp_BuscarNormativa @Pregunta = @p, @TopN = 3;
REVERT;

EXECUTE AS USER = 'marta_direccion';
    EXEC dbo.usp_BuscarNormativa @Pregunta = @p, @TopN = 5;
REVERT;
GO

/* ---------------------------------------------------------------------------
   Prueba 4. Información confidencial: un empleado de IT pregunta por la
   retribución de directivos y por las bandas salariales. RLS no le devuelve
   DIR-RET-01a/b ni RRHH-SAL-01a/b, aunque sean los fragmentos más parecidos.
   --------------------------------------------------------------------------- */
DECLARE @p NVARCHAR(1000) = N'¿Cuál es la retribución variable de los directivos y las bandas salariales?';

EXECUTE AS USER = 'lucia_it';
    EXEC dbo.usp_BuscarNormativa @Pregunta = @p, @TopN = 3;   -- sin DIR-* ni RRHH-*
REVERT;

EXECUTE AS USER = 'marta_direccion';
    EXEC dbo.usp_BuscarNormativa @Pregunta = @p, @TopN = 3;   -- incluye fragmentos DIR-RET-01a/b y RRHH-SAL-01a/b
REVERT;
GO

/* ---------------------------------------------------------------------------
   Prueba 5. Usuario sin rol: permiso EXECUTE sobre el procedimiento, pero RLS
   no le devuelve ninguna fila.
   --------------------------------------------------------------------------- */
EXECUTE AS USER = 'invitado_externo';
    EXEC dbo.usp_BuscarNormativa @Pregunta = N'¿Cuántos días de vacaciones tengo?', @TopN = 3;   -- 0 filas
REVERT;
GO

/* ---------------------------------------------------------------------------
   Prueba 6. Contexto del administrador (sin suplantar).
   Un sysadmin entra en la base de datos como dbo, y dbo no puede pertenecer a
   ningún rol: IS_MEMBER() devuelve 0 para todos y el administrador ve 0
   normativas. RLS también se aplica a dbo, y para consultar como un empleado
   hay que usar EXECUTE AS USER.
   --------------------------------------------------------------------------- */
SELECT
    SUSER_SNAME()              AS LoginWindows,
    USER_NAME()                AS UsuarioBD,
    IS_MEMBER(N'Rol_Empleado')  AS Es_Empleado,
    IS_MEMBER(N'Rol_RRHH')      AS Es_RRHH,
    IS_MEMBER(N'Rol_Ventas')    AS Es_Ventas,
    IS_MEMBER(N'Rol_IT')        AS Es_IT,
    IS_MEMBER(N'Rol_Direccion') AS Es_Direccion,
    (SELECT COUNT(*) FROM dbo.Normativas) AS FilasVisibles;
GO

/* ---------------------------------------------------------------------------
   Prueba 7. Plan de ejecución: el predicado de seguridad aparece como un
   filtro (Filter / Nested Loops sobre Departamentos) ANTES del Top N Sort por
   distancia. Activa "Incluir plan de ejecución real" y ejecuta:
   --------------------------------------------------------------------------- */
-- EXECUTE AS USER = 'lucia_it';
--     EXEC dbo.usp_BuscarNormativa @Pregunta = N'guardias fuera de horario', @TopN = 3;
-- REVERT;

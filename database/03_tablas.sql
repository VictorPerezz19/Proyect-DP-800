/* =============================================================================
   03_tablas.sql
   -----------------------------------------------------------------------------
   Fase 2. Modelo relacional: Departamentos, Empleados y Normativas.

   Decisiones de diseño:
   - Departamentos.RolBD guarda el nombre del rol de base de datos que da
     acceso a las normativas de ese departamento. La función de RLS lo consulta
     con IS_MEMBER(), así que añadir un departamento no obliga a cambiar código.
   - Departamentos.EsGeneral = 1 marca las normativas comunes a toda la
     plantilla (visibles para cualquier miembro de Rol_Empleado).
   - Empleados.UsuarioBD relaciona cada empleado con su usuario de base de
     datos (USER_NAME()), lo que permite la vista dbo.vw_MiPerfil.
   - Normativas.Embedding es VECTOR(384), las dimensiones de all-MiniLM-L6-v2.
     No se crea ningún índice sobre la columna VECTOR: la búsqueda es exacta
     (k-NN por fuerza bruta con VECTOR_DISTANCE), que con decenas o cientos de
     fragmentos es rápida y devuelve el resultado exacto. Los índices
     vectoriales aproximados (CREATE VECTOR INDEX, DiskANN) son preview y no
     tienen sentido con este volumen.
   - Índice FULL-TEXT en español (LANGUAGE 3082) sobre Titulo y Contenido
     para la búsqueda híbrida de 08: FREETEXTTABLE aporta coincidencia por
     palabras con lematización en español, que complementa al modelo de
     embeddings (entrenado en inglés). Con CHANGE_TRACKING = AUTO, las
     normativas nuevas se indexan solas. Medición en 10_evaluacion_recuperacion.sql.
   ============================================================================= */
USE NormativaRAG;
GO

CREATE TABLE dbo.Departamentos
(
    DepartamentoId  INT           NOT NULL CONSTRAINT PK_Departamentos PRIMARY KEY,
    Nombre          NVARCHAR(100) NOT NULL CONSTRAINT UQ_Departamentos_Nombre UNIQUE,
    RolBD           SYSNAME       NOT NULL,   -- rol de BD que da acceso a sus normativas
    EsGeneral       BIT           NOT NULL CONSTRAINT DF_Departamentos_EsGeneral DEFAULT (0)
);
GO

CREATE TABLE dbo.Empleados
(
    EmpleadoId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Empleados PRIMARY KEY,
    Nombre          NVARCHAR(100) NOT NULL,
    Apellidos       NVARCHAR(150) NOT NULL,
    Email           NVARCHAR(200) NOT NULL CONSTRAINT UQ_Empleados_Email UNIQUE,
    Puesto          NVARCHAR(100) NOT NULL,
    FechaAlta       DATE          NOT NULL,
    DepartamentoId  INT           NOT NULL
        CONSTRAINT FK_Empleados_Departamentos REFERENCES dbo.Departamentos (DepartamentoId),
    UsuarioBD       SYSNAME       NULL        -- usuario de BD del empleado (si tiene)
);
GO

CREATE TABLE dbo.Normativas
(
    NormativaId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Normativas PRIMARY KEY,
    DepartamentoId  INT           NOT NULL
        CONSTRAINT FK_Normativas_Departamentos REFERENCES dbo.Departamentos (DepartamentoId),
    Codigo          VARCHAR(20)   NOT NULL CONSTRAINT UQ_Normativas_Codigo UNIQUE,  -- p. ej. GEN-PER-01a (sufijo a/b = fragmento)
    Titulo          NVARCHAR(200) NOT NULL,
    Contenido       NVARCHAR(2000) NOT NULL,  -- un fragmento por fila (tokenizer.json trunca a 128 tokens)
    FechaVigencia   DATE          NOT NULL,
    Embedding       VECTOR(384)   NULL        -- lo rellena 05_generar_embeddings.sql
);
GO

-- Índice B-tree sobre la columna que usa el predicado de RLS (no sobre el vector)
CREATE NONCLUSTERED INDEX IX_Normativas_DepartamentoId ON dbo.Normativas (DepartamentoId);
CREATE NONCLUSTERED INDEX IX_Empleados_DepartamentoId  ON dbo.Empleados  (DepartamentoId);
GO

-- Búsqueda de texto completo en español (requiere la característica Full-Text Search)
IF NOT EXISTS (SELECT 1 FROM sys.fulltext_catalogs WHERE name = N'FTC_Normativas')
    CREATE FULLTEXT CATALOG FTC_Normativas;
GO

CREATE FULLTEXT INDEX ON dbo.Normativas
(
    Titulo    LANGUAGE 3082,      -- 3082 = español (alfabetización internacional)
    Contenido LANGUAGE 3082
)
KEY INDEX PK_Normativas ON FTC_Normativas
WITH (CHANGE_TRACKING = AUTO, STOPLIST = SYSTEM);
GO

SELECT t.name AS Tabla, c.name AS Columna, ty.name AS Tipo, c.max_length
FROM sys.tables  AS t
JOIN sys.columns AS c  ON c.object_id = t.object_id
JOIN sys.types   AS ty ON ty.user_type_id = c.user_type_id
WHERE t.name IN (N'Departamentos', N'Empleados', N'Normativas')
ORDER BY t.name, c.column_id;
GO

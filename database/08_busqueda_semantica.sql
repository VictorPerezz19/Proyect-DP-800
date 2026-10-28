/* =============================================================================
   08_busqueda_semantica.sql
   -----------------------------------------------------------------------------
   Fase 4. Motor de búsqueda HÍBRIDA (Retrieval del patrón RAG).

   dbo.usp_BuscarNormativa
     1. Ranking semántico: convierte la pregunta en un VECTOR(384) con
        AI_GENERATE_EMBEDDINGS y el mismo modelo ONNX que se usó para las
        normativas (los vectores solo son comparables si salen del mismo
        modelo), y ordena todas las filas visibles por
        VECTOR_DISTANCE('cosine', ...). Es una búsqueda exacta (k-NN completo).
     2. Ranking por palabras: FREETEXTTABLE sobre el índice full-text en
        español (03), con lematización ("fallece" ~ "fallecimiento").
     3. Fusión con Reciprocal Rank Fusion (RRF):
            puntuación = 1 / (k + rank_vectorial) + 1 / (k + rank_fulltext)
        con k = 60, el valor estándar de la literatura (Cormack et al., 2009).
        No se ha ajustado k a las preguntas de prueba, para no sobreajustar.
        RRF solo usa posiciones, así que no hay que normalizar escalas tan
        distintas como una distancia coseno y el RANK de full-text.
        Medición (10_evaluacion_recuperacion.sql, 12 preguntas): MRR 0,56 con
        solo vectores y 0,81 en híbrido; aciertos en el top 4: 8 frente a 11.
     4. Fragmentos hermanos: las normativas largas están divididas en dos
        fragmentos (código + 'a'/'b', ver 04). Tras elegir los @TopN mejores
        fragmentos, se añade el fragmento hermano de cada normativa recuperada,
        para que Copilot reciba siempre la normativa completa (por ejemplo,
        VEN-TRA-01a con los "3 días" junto a VEN-TRA-01b con los gastos). La
        columna EsFragmentoHermano = 1 marca los añadidos. El resultado tiene
        entre @TopN y 2 × @TopN filas, agrupadas por normativa.
     5. No tiene ningún filtro de seguridad propio: la SECURITY POLICY de 07 se
        aplica automáticamente a dbo.Normativas, también dentro del
        procedimiento, y el contexto de seguridad sigue siendo el del usuario
        que llama (no hay EXECUTE AS). FREETEXTTABLE devuelve claves del índice
        sin pasar por RLS, pero solo se usan al unirlas con dbo.Normativas, y
        ese JOIN sí aplica el predicado. Los dos rankings se calculan, por
        tanto, solo sobre filas autorizadas.

   dbo.vw_MiPerfil
     Devuelve el empleado asociado al usuario conectado (USER_NAME()). Copilot
     puede usarla para saber de qué departamento es quien pregunta.
   ============================================================================= */
USE NormativaRAG;
GO

CREATE OR ALTER PROCEDURE dbo.usp_BuscarNormativa
    @Pregunta NVARCHAR(1000),
    @TopN     INT = 4
AS
BEGIN
    SET NOCOUNT ON;

    IF @Pregunta IS NULL OR LEN(LTRIM(RTRIM(@Pregunta))) = 0
        THROW 50001, N'La pregunta no puede estar vacía.', 1;

    IF @TopN IS NULL OR @TopN NOT BETWEEN 1 AND 10
        THROW 50002, N'@TopN debe estar entre 1 y 10.', 1;

    DECLARE @K INT = 60;   -- constante de RRF

    -- Pregunta -> vector (modelo ONNX local, sin servicios externos)
    DECLARE @VectorPregunta VECTOR(384) =
        AI_GENERATE_EMBEDDINGS(@Pregunta USE MODEL ModeloEmbeddingsLocal);

    WITH Vectorial AS (          -- 1. ranking semántico (k-NN exacto)
        SELECT n.NormativaId,
               VECTOR_DISTANCE('cosine', n.Embedding, @VectorPregunta) AS Distancia,
               ROW_NUMBER() OVER (ORDER BY VECTOR_DISTANCE('cosine', n.Embedding, @VectorPregunta)) AS RankVectorial
        FROM dbo.Normativas AS n
        WHERE n.Embedding IS NOT NULL
    ),
    TextoCompleto AS (           -- 2. ranking por palabras (el JOIN aplica RLS)
        SELECT n.NormativaId,
               ROW_NUMBER() OVER (ORDER BY ft.[RANK] DESC) AS RankFullText
        FROM FREETEXTTABLE(dbo.Normativas, (Titulo, Contenido), @Pregunta, LANGUAGE 3082) AS ft
        JOIN dbo.Normativas AS n ON n.NormativaId = ft.[KEY]
    ),
    Fusion AS (                  -- 3. Reciprocal Rank Fusion
        SELECT v.NormativaId, v.Distancia, v.RankVectorial, t.RankFullText,
               1.0 / (@K + v.RankVectorial) + ISNULL(1.0 / (@K + t.RankFullText), 0) AS PuntuacionRRF,
               -- Código de la normativa sin el sufijo de fragmento: GEN-PER-01a -> GEN-PER-01
               CASE WHEN n.Codigo LIKE '%[0-9][ab]' THEN LEFT(n.Codigo, LEN(n.Codigo) - 1)
                    ELSE n.Codigo END AS CodigoBase
        FROM Vectorial AS v
        JOIN dbo.Normativas AS n ON n.NormativaId = v.NormativaId
        LEFT JOIN TextoCompleto AS t ON t.NormativaId = v.NormativaId
    ),
    Seleccion AS (               -- 4. los @TopN mejores fragmentos
        SELECT TOP (@TopN) NormativaId, CodigoBase, PuntuacionRRF
        FROM Fusion
        ORDER BY PuntuacionRRF DESC, RankVectorial
    ),
    Recuperadas AS (             -- 5. normativas recuperadas y su mejor puntuación
        SELECT CodigoBase, MAX(PuntuacionRRF) AS MejorRRF
        FROM Seleccion
        GROUP BY CodigoBase
    )
    -- 6. Todos los fragmentos de esas normativas: si se recuperó el 'a', se añade
    --    el 'b' y viceversa. El hermano sale de Fusion, que ya está filtrada por
    --    RLS (siempre pertenece al mismo departamento, así que es visible).
    SELECT
        n.Codigo,
        d.Nombre                                   AS Departamento,
        n.Titulo,
        n.Contenido,
        CAST(f.PuntuacionRRF AS DECIMAL(7,5))      AS PuntuacionRRF,
        f.RankVectorial,
        f.RankFullText,                            -- NULL = sin coincidencia de palabras
        CAST(f.Distancia AS DECIMAL(6,4))          AS DistanciaCoseno,
        CAST(CASE WHEN s.NormativaId IS NULL THEN 1 ELSE 0 END AS BIT) AS EsFragmentoHermano,  -- 1 = añadido, no estaba en el TopN
        USER_NAME()                                AS ConsultadoPor
    FROM Fusion AS f
    JOIN Recuperadas        AS g ON g.CodigoBase = f.CodigoBase
    LEFT JOIN Seleccion     AS s ON s.NormativaId = f.NormativaId
    JOIN dbo.Normativas     AS n ON n.NormativaId = f.NormativaId
    JOIN dbo.Departamentos  AS d ON d.DepartamentoId = n.DepartamentoId
    ORDER BY g.MejorRRF DESC, n.Codigo;   -- normativas por relevancia; dentro de cada una, a antes que b
END;
GO

CREATE OR ALTER VIEW dbo.vw_MiPerfil
AS
    SELECT e.Nombre, e.Apellidos, e.Puesto, d.Nombre AS Departamento, e.UsuarioBD
    FROM dbo.Empleados     AS e
    JOIN dbo.Departamentos AS d ON d.DepartamentoId = e.DepartamentoId
    WHERE e.UsuarioBD = USER_NAME();
GO

-- Permisos: ejecutar la búsqueda y ver el propio perfil.
-- Gracias al encadenamiento de propiedad (todo es de dbo), no hace falta
-- conceder SELECT sobre dbo.Empleados.
GRANT EXECUTE ON dbo.usp_BuscarNormativa TO Rol_Empleado;
GRANT SELECT  ON dbo.vw_MiPerfil         TO Rol_Empleado;
GRANT EXECUTE ON dbo.usp_BuscarNormativa TO invitado_externo;   -- para la prueba "sin rol"
GO

-- Prueba rápida como administrador: devuelve 0 filas. Un sysadmin entra como
-- dbo y, según la documentación de IS_MEMBER, para dbo siempre devuelve 0 en
-- los roles de base de datos. Para consultar como empleado se usa EXECUTE AS
-- USER (ver 09).
EXEC dbo.usp_BuscarNormativa @Pregunta = N'¿Cuántos días de vacaciones tengo?', @TopN = 4;
GO

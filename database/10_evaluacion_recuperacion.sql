/* =============================================================================
   10_evaluacion_recuperacion.sql
   -----------------------------------------------------------------------------
   Fase 4. Medición de la calidad de la recuperación (Retrieval).

   12 preguntas típicas con su normativa correcta conocida. Para cada pregunta
   se anota la posición del primer fragmento (a/b) de esa normativa con tres
   métodos:
     - Vectorial : solo VECTOR_DISTANCE (coseno), k-NN exacto.
     - FullText  : solo FREETEXTTABLE (español, LANGUAGE 3082).
     - Hibrida   : Reciprocal Rank Fusion de ambos, k = 60. Es la que usa
                   dbo.usp_BuscarNormativa.
   Además se ejecuta el procedimiento real para comprobar que su top 4 coincide
   con lo medido para la búsqueda híbrida.

   Métricas:
     - Acierto_Top1 / Acierto_Top4: preguntas con la normativa correcta en 1.ª
       posición o entre las 4 primeras (el @TopN que usa Copilot).
     - MRR (Mean Reciprocal Rank): media de 1/posición; 1 = siempre primera.
       Si un método no encuentra la normativa, esa pregunta suma 0.

   Se ejecuta como marta_direccion (Rol_Direccion ve todas las normativas), de
   modo que se evalúa todo el corpus. El administrador (dbo) no vería filas
   por el RLS.

   Resultados del 27/10/2026 (72 fragmentos, modelo minilm-sin-padding):
     Vectorial  Top1 5  Top4  8  MRR 0,563
     FullText   Top1 8  Top4 10  MRR 0,753
     Hibrida    Top1 8  Top4 11  MRR 0,808
   ============================================================================= */
USE NormativaRAG;
GO

EXECUTE AS USER = 'marta_direccion';
SET NOCOUNT ON;

DECLARE @p TABLE (Id INT IDENTITY, Pregunta NVARCHAR(300), Esperada VARCHAR(20));
INSERT INTO @p (Pregunta, Esperada) VALUES
 (N'¿Cuántos días de permiso tengo por mudanza?',                    'GEN-PER-01'),
 (N'¿Cuántos días de vacaciones tengo al año?',                      'GEN-VAC-01'),
 (N'¿Cuántos días a la semana puedo teletrabajar?',                  'GEN-TEL-01'),
 (N'¿Cuántos días de permiso me dan si me caso?',                    'GEN-PER-02'),
 (N'¿Qué pasa si fallece un familiar?',                              'GEN-PER-04'),
 (N'¿Cuánto me pagan por kilómetro y cuáles son las dietas?',        'VEN-GAS-01'),
 (N'¿Cuánto se cobra por una semana de guardia?',                    'IT-GUA-01'),
 (N'¿Qué hago si pierdo el portátil?',                               'IT-EQU-01'),
 (N'¿Qué descuento puedo aplicar a un cliente sin aprobación?',      'VEN-DES-01'),
 (N'¿Cuál es la retribución variable de los directivos?',            'DIR-RET-01'),
 (N'¿Quién aprueba una inversión de 100.000 euros?',                 'DIR-GAS-01'),
 (N'¿Cómo se investiga una denuncia de acoso?',                      'RRHH-ACO-01');

DECLARE @r    TABLE (Id INT, Metodo VARCHAR(20), Posicion INT);
DECLARE @proc TABLE (Codigo VARCHAR(20), Departamento NVARCHAR(100), Titulo NVARCHAR(200), Contenido NVARCHAR(2000),
                     PuntuacionRRF DECIMAL(7,5), RankVectorial BIGINT, RankFullText BIGINT,
                     DistanciaCoseno DECIMAL(6,4), EsFragmentoHermano BIT, ConsultadoPor SYSNAME);
DECLARE @procTop4 TABLE (Id INT, EnTop4 BIT);

DECLARE @i INT = 1, @n INT = (SELECT COUNT(*) FROM @p), @q NVARCHAR(300), @e VARCHAR(20), @v VECTOR(384);
WHILE @i <= @n
BEGIN
    SELECT @q = Pregunta, @e = Esperada FROM @p WHERE Id = @i;
    SET @v = AI_GENERATE_EMBEDDINGS(@q USE MODEL ModeloEmbeddingsLocal);

    WITH vec AS (
        SELECT NormativaId, ROW_NUMBER() OVER (ORDER BY VECTOR_DISTANCE('cosine', Embedding, @v)) AS RankV
        FROM dbo.Normativas
        WHERE Embedding IS NOT NULL),
    ft AS (
        SELECT n.NormativaId, ROW_NUMBER() OVER (ORDER BY f.[RANK] DESC) AS RankFT
        FROM FREETEXTTABLE(dbo.Normativas, (Titulo, Contenido), @q, LANGUAGE 3082) AS f
        JOIN dbo.Normativas AS n ON n.NormativaId = f.[KEY]),
    base AS (
        SELECT n.Codigo, v.RankV, ft.RankFT
        FROM dbo.Normativas AS n
        JOIN vec AS v ON v.NormativaId = n.NormativaId
        LEFT JOIN ft ON ft.NormativaId = n.NormativaId),
    pos AS (
        SELECT Codigo, 'Vectorial' AS Metodo, RankV AS Pos FROM base
        UNION ALL
        SELECT Codigo, 'FullText', RankFT FROM base WHERE RankFT IS NOT NULL
        UNION ALL
        SELECT Codigo, 'Hibrida',
               ROW_NUMBER() OVER (ORDER BY 1.0 / (60 + RankV) + ISNULL(1.0 / (60 + RankFT), 0) DESC, RankV)
        FROM base)
    INSERT INTO @r
    SELECT @i, Metodo, MIN(Pos)
    FROM pos
    WHERE Codigo LIKE @e + '%'
    GROUP BY Metodo;

    -- Procedimiento real
    DELETE FROM @proc;
    INSERT INTO @proc EXEC dbo.usp_BuscarNormativa @Pregunta = @q, @TopN = 4;
    INSERT INTO @procTop4
    SELECT @i, CASE WHEN EXISTS (SELECT 1 FROM @proc WHERE Codigo LIKE @e + '%') THEN 1 ELSE 0 END;

    SET @i += 1;
END;

-- Detalle por pregunta (NULL en FullText = no hubo coincidencia de palabras)
SELECT p.Esperada,
       MAX(CASE WHEN r.Metodo = 'Vectorial' THEN r.Posicion END) AS Vectorial,
       MAX(CASE WHEN r.Metodo = 'FullText'  THEN r.Posicion END) AS FullText,
       MAX(CASE WHEN r.Metodo = 'Hibrida'   THEN r.Posicion END) AS Hibrida,
       MAX(CAST(t.EnTop4 AS INT))                                AS Procedimiento_EnTop4,
       p.Pregunta
FROM @p AS p
LEFT JOIN @r AS r        ON r.Id = p.Id
LEFT JOIN @procTop4 AS t ON t.Id = p.Id
GROUP BY p.Id, p.Esperada, p.Pregunta
ORDER BY p.Id;

-- Resumen por método
SELECT m.Metodo,
       SUM(CASE WHEN r.Posicion = 1  THEN 1 ELSE 0 END)        AS Acierto_Top1,
       SUM(CASE WHEN r.Posicion <= 4 THEN 1 ELSE 0 END)        AS Acierto_Top4,
       CAST(SUM(ISNULL(1.0 / r.Posicion, 0)) / COUNT(*) AS DECIMAL(4,3)) AS MRR
FROM (VALUES ('Vectorial'), ('FullText'), ('Hibrida')) AS m(Metodo)
CROSS JOIN @p AS p
LEFT JOIN @r AS r ON r.Id = p.Id AND r.Metodo = m.Metodo
GROUP BY m.Metodo
ORDER BY MRR DESC;

-- Comprobación: el procedimiento debe acertar en el top 4 lo mismo que la fila "Hibrida"
SELECT SUM(CAST(EnTop4 AS INT)) AS Procedimiento_Acierto_Top4, COUNT(*) AS Preguntas
FROM @procTop4;

REVERT;
GO

/* =============================================================================
   05_generar_embeddings.sql
   -----------------------------------------------------------------------------
   Fase 2. Convierte cada normativa en un vector con el modelo ONNX local.

   AI_GENERATE_EMBEDDINGS(texto USE MODEL modelo) tokeniza el texto
   (tokenizers_cpp.dll + tokenizer.json), ejecuta model.onnx en ONNX Runtime
   dentro de AIRuntimeHost y devuelve un array JSON. Al asignarlo a una columna
   VECTOR(384), SQL Server lo convierte implícitamente.

   Por qué no PREDICT: PREDICT puntúa modelos ONNX con entradas numéricas
   tabulares y no tokeniza texto, así que no sirve para generar embeddings de
   frases. Es el error que tenía la versión anterior del proyecto.

   Se vectoriza Título + Contenido para que el título también aporte
   significado a la búsqueda.

   Orden de ejecución: este script se ejecuta ANTES de activar RLS (07). Si la
   política ya existe, se desactiva temporalmente, porque el filter predicate
   también se aplica a los UPDATE y el administrador no vería las filas.
   ============================================================================= */
USE NormativaRAG;
GO

IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = N'PoliticaNormativas')
    EXEC (N'ALTER SECURITY POLICY Seguridad.PoliticaNormativas WITH (STATE = OFF);');
GO

-- Solo las filas sin vector, para poder añadir normativas nuevas y volver a ejecutar
UPDATE n
SET    n.Embedding = AI_GENERATE_EMBEDDINGS(CONCAT(n.Titulo, N'. ', n.Contenido) USE MODEL ModeloEmbeddingsLocal)
FROM   dbo.Normativas AS n
WHERE  n.Embedding IS NULL;

SELECT @@ROWCOUNT AS NormativasVectorizadas;
GO

-- Las comprobaciones se hacen antes de reactivar RLS: el administrador (dbo)
-- no es miembro de ningún Rol_* y, con la política activa, no vería filas.

-- Verificación: no debe quedar ninguna fila sin vector
SELECT
    COUNT(*)                                          AS Total,
    SUM(CASE WHEN Embedding IS NULL THEN 1 ELSE 0 END) AS SinVector
FROM dbo.Normativas;

-- Muestra: dimensiones y comienzo del vector de algunas filas
SELECT TOP (5)
    Codigo,
    Titulo,
    VECTORPROPERTY(Embedding, 'Dimensions')            AS Dimensiones,
    LEFT(CAST(Embedding AS NVARCHAR(MAX)), 80) + N'...' AS InicioVector
FROM dbo.Normativas
ORDER BY NormativaId;
GO

-- Prueba de cordura sin RLS: la normativa más parecida a una pregunta
DECLARE @q VECTOR(384) = AI_GENERATE_EMBEDDINGS(N'¿Cuántos días de permiso tengo por mudanza?' USE MODEL ModeloEmbeddingsLocal);

SELECT TOP (3)
    Codigo,
    Titulo,
    VECTOR_DISTANCE('cosine', Embedding, @q) AS DistanciaCoseno
FROM dbo.Normativas
ORDER BY DistanciaCoseno;
GO

IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = N'PoliticaNormativas')
    EXEC (N'ALTER SECURITY POLICY Seguridad.PoliticaNormativas WITH (STATE = ON);');
GO

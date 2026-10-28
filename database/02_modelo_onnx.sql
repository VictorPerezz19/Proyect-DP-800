/* =============================================================================
   02_modelo_onnx.sql
   -----------------------------------------------------------------------------
   Fase 1. Registra el modelo de embeddings ONNX local como EXTERNAL MODEL.

   Estructura de carpetas esperada (la crean scripts\descargar_modelo.py y
   scripts\preparar_onnx_runtime.ps1):
     C:\onnx_runtime\onnxruntime.dll          <- ONNX Runtime >= 1.19 (carpeta lib)
     C:\onnx_runtime\tokenizers_cpp.dll       <- tokenizador (ver README.md)
     C:\onnx_runtime\model\minilm-sin-padding\model.onnx
     C:\onnx_runtime\model\minilm-sin-padding\tokenizer.json   <- "padding": null

   - LOCATION           -> carpeta con model.onnx y tokenizer.json. Se usa la
                           variante SIN PADDING y no la carpeta original del
                           ejemplo oficial: con el relleno fijo a 128 tokens,
                           AIRuntimeHost promedia también los [PAD], las
                           distancias se comprimen de 3 a 5 veces y aparece un
                           sesgo por longitud del texto (prueba documentada en
                           docs/instalacion_onnx.md, "Prueba del padding").
   - LOCAL_RUNTIME_PATH -> carpeta con onnxruntime.dll y tokenizers_cpp.dll
   - PARAMETERS         -> la documentación indica que en SQL Server 2025 es
                           obligatorio un JSON de relleno con el runtime ONNX.

   Modelo: nsense/all-MiniLM-L6-v2-onnx (licencia MIT), 384 dimensiones.
   Es el modelo del ejemplo oficial de Microsoft Learn.
   ============================================================================= */
USE NormativaRAG;
GO

-- Recrear el modelo si ya existía (no hay vistas SCHEMABINDING que dependan de él)
IF EXISTS (SELECT 1 FROM sys.external_models WHERE name = N'ModeloEmbeddingsLocal')
    DROP EXTERNAL MODEL ModeloEmbeddingsLocal;
GO

CREATE EXTERNAL MODEL ModeloEmbeddingsLocal
WITH (
    LOCATION           = 'C:\onnx_runtime\model\minilm-sin-padding',
    API_FORMAT         = 'ONNX Runtime',
    MODEL_TYPE         = EMBEDDINGS,
    MODEL              = 'allMiniLM',
    PARAMETERS         = '{"valid":"JSON"}',
    LOCAL_RUNTIME_PATH = 'C:\onnx_runtime\'
);
GO

-- Metadatos del modelo registrado
SELECT *
FROM sys.external_models;
GO

-- Prueba: la primera llamada arranca AIRuntimeHost y carga las DLL.
-- Debe devolver un array JSON de 384 números.
SELECT AI_GENERATE_EMBEDDINGS(N'Prueba de embeddings en SQL Server 2025' USE MODEL ModeloEmbeddingsLocal) AS EmbeddingJSON;
GO

-- Comprobación de dimensiones: al convertirlo a VECTOR(384) falla si no son 384
DECLARE @v VECTOR(384) = AI_GENERATE_EMBEDDINGS(N'Comprobación de dimensiones' USE MODEL ModeloEmbeddingsLocal);
SELECT VECTORPROPERTY(@v, 'Dimensions') AS Dimensiones;   -- esperado: 384
GO

/* -----------------------------------------------------------------------------
   Diagnóstico (solo si la prueba falla). Captura las trazas de AIRuntimeHost:

   CREATE EVENT SESSION ai_onnx_trace ON SERVER
   ADD EVENT ai_generate_embeddings_airuntime_trace
       (ACTION (sqlserver.sql_text, sqlserver.session_id))
   ADD TARGET package0.ring_buffer
   WITH (MAX_MEMORY = 4096 KB, EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
         MAX_DISPATCH_LATENCY = 30 SECONDS, TRACK_CAUSALITY = ON, STARTUP_STATE = OFF);
   ALTER EVENT SESSION ai_onnx_trace ON SERVER STATE = START;

   Después vuelve a lanzar la prueba y lee el ring_buffer (consulta completa en
   docs/instalacion_onnx.md).
   ----------------------------------------------------------------------------- */

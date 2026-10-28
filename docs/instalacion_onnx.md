# Runtime ONNX local en SQL Server 2025: detalle y diagnóstico

Fuentes, comprobadas en octubre de 2026:

- [CREATE EXTERNAL MODEL (Microsoft Learn)](https://learn.microsoft.com/sql/t-sql/statements/create-external-model-transact-sql): sección *Example with ONNX Runtime running locally*.
- [AI_GENERATE_EMBEDDINGS (Microsoft Learn)](https://learn.microsoft.com/sql/t-sql/functions/ai-generate-embeddings-transact-sql).
- [Create embeddings in SQL Server 2025 RC0 with a local ONNX model on Windows (Azure SQL Dev Corner)](https://devblogs.microsoft.com/azure-sql/create-embeddings-in-sql-server-2025-rc0-with-a-local-onnx-model-on-windows/).

## Cómo funciona

1. `AI_GENERATE_EMBEDDINGS(texto USE MODEL m)` comprueba que el usuario tiene `EXECUTE` sobre
   `EXTERNAL MODEL::m`.
2. Como `API_FORMAT = 'ONNX Runtime'`, SQL Server pide a **Launchpad** que arranque el proceso
   **AIRuntimeHost** (por eso hace falta Machine Learning Services y la opción
   `external AI runtimes enabled`).
3. AIRuntimeHost carga `onnxruntime.dll` y `tokenizers_cpp.dll` desde `LOCAL_RUNTIME_PATH`, y
   `model.onnx` y `tokenizer.json` desde `LOCATION`.
4. Tokeniza, ejecuta el modelo y devuelve el embedding como un array JSON, que SQL Server
   convierte a `VECTOR(n)` al asignarlo.

## Requisitos verificados

| Requisito | Dónde se aplica |
|---|---|
| `ALTER DATABASE SCOPED CONFIGURATION SET PREVIEW_FEATURES = ON` | `01_configuracion_instancia.sql` |
| `sp_configure 'external AI runtimes enabled', 1` | `01_configuracion_instancia.sql` |
| Machine Learning Services instalado (Launchpad) | Instalador de SQL Server |
| ONNX Runtime 1.19 o superior (`onnxruntime.dll`) | `C:\onnx_runtime\` |
| DLL de tokenizador llamada exactamente `tokenizers_cpp.dll` | `C:\onnx_runtime\` |
| `PARAMETERS = '{"valid":"JSON"}'` (relleno obligatorio en SQL Server 2025) | `02_modelo_onnx.sql` |
| Permisos de `MSSQLLaunchpad` sobre la carpeta | `scripts/preparar_onnx_runtime.ps1` |
| `GRANT EXECUTE ON EXTERNAL MODEL::...` a quien genere embeddings | `06_roles_y_usuarios.sql` |

**No** se habilita `external rest endpoint enabled`: la documentación lo pide para los modelos que
llaman a endpoints REST (Azure OpenAI, OpenAI, Ollama), y aquí no se llama a ninguno.
**Comprobado** en SQL Server 2025 17.0.1000.7: con esta opción a 0, `AI_GENERATE_EMBEDDINGS` funciona con el
runtime ONNX local. La instancia queda con la superficie de ataque mínima: no puede hacer llamadas
REST salientes.

## El tokenizador (`tokenizers_cpp.dll`)

[mlc-ai/tokenizers-cpp](https://github.com/mlc-ai/tokenizers-cpp) genera por defecto bibliotecas
**estáticas** (`tokenizers_c`, `sentencepiece`, `tokenizers_cpp`). SQL Server necesita una DLL
**compartida** compilada con MSVC. Una propuesta de cambio a la documentación oficial
(MicrosoftDocs/sql-docs PR 10338, cerrada sin fusionar) describía un export
`extern "C" __declspec(dllexport) LoadBlobJsonAndEncode(...)`, y avisaba de que esa firma podía
cambiar. El blog oficial de Azure SQL enlaza una DLL precompilada (`PARTHSQL/tokenizers-cpp`, release
`v0.1.1`). Este proyecto **no usa ese binario**, porque no tiene firma ni checksums publicados.
Se ha **compilado desde el código fuente** del mismo repositorio.

### Compilación usada en este proyecto (27/10/2026)

**Revisión del código.** El repositorio `PARTHSQL/tokenizers-cpp` en el tag `v0.1.1`
(commit `c424a48`) es el `mlc-ai/tokenizers-cpp` original hasta el commit `aae1209`, más dos
commits propios:
- `c6d0f8f`: añade la opción `BUILD_SHARED_LIBS` en `CMakeLists.txt` y el archivo
  `src/static_exports.cc` (65 líneas). Ese archivo solo envuelve el tokenizador en funciones
  `extern "C" __declspec(dllexport)`, como `LoadBlobJsonAndEncode`, sin acceso a red,
  archivos ni procesos.
- `c424a48`: cambia solo el README.

**Herramientas.**
- Visual Studio 2022 Build Tools (MSVC 14.44).
- CMake 4.4.4.
- **Rust 1.87.0**. Las versiones de Rust desde la 1.89 rechazan el código original por el lint
  `dangerous_implicit_autorefs`, en una función de *decode* que no se usa.

**Dependencias.**
- Submódulos: `google/sentencepiece` `f2219b5` y `msgpack/msgpack-c` `8c602e8`.
- Crate `tokenizers` fijado a **0.21.1** con `cargo update -p tokenizers --precise 0.21.1`.
  El repositorio no incluye `Cargo.lock`, y la 0.21.4 rompe la compilación.

**Comandos** (desde un *Developer Command Prompt* x64, con `RUSTUP_TOOLCHAIN=1.87.0` y desde
una ruta corta: las rutas largas provocan el error `C1083`):

```bat
cmake -S <repo> -B <build> -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release ^
  -DBUILD_SHARED_LIBS=ON -DTOKENIZERS_CPP_MSVC_RUNTIME_LIBRARY=MD -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build <build> --target tokenizers_cpp
```

`/MD` (runtime de C dinámico) es necesario porque la interfaz pasa `std::string` y
`std::vector` entre módulos: la DLL y el proceso que la carga tienen que compartir el mismo
montón de memoria del CRT.

**Verificación.**
- `dumpbin /exports` muestra las 8 funciones `LoadBlob*`.
- Dependencias: solo Windows y el runtime de Visual C++ (`MSVCP140`, `VCRUNTIME140`).
- Un programa de prueba que carga la DLL con `LoadLibrary` tokeniza `"Hello world"` como
  `[7592, 2088]`, los IDs correctos del vocabulario BERT del modelo.
- Resultado: `tokenizers_cpp.dll`, 4.511.744 bytes, SHA-256
  `AB7290947DA58912A431548E626B6051E6BEF38818484A639A4927953D76C8A8`.

### Longitud máxima: 128 tokens

El `tokenizer.json` de `nsense/all-MiniLM-L6-v2-onnx` tiene `truncation.max_length = 128` y
`padding = Fixed(128)`. Con el vocabulario inglés del modelo, el español se divide en muchos
subtokens: «Permiso retribuido por mudanza» son 10 tokens. Medido con la DLL, **35 de las 37
normativas** originales (título + contenido) llegaban al límite y se truncaban.

**Solución aplicada en `04_datos_prueba.sql`.** Cada una se dividió en dos fragmentos
(`<código>a` / `<código>b`), cortando entre frases por el punto que equilibra los dos tamaños, y
se repitió el título en ambos. En `GEN-PER-03` la primera frase no cabía por sí sola, así que se
dividió en su coordinación («…, o de cualquier persona que conviva…») con un mínimo cambio de
redacción. Verificación con `tokenizers_cpp.dll`: **72 fragmentos, entre 47 y 126 tokens,
ninguno truncado**. Al unir `a` + `b` se obtiene exactamente el texto original (salvo en
GEN-PER-03).

### Prueba del padding (27/10/2026): por qué `LOCATION` apunta a `minilm-sin-padding`

**Síntoma.** Con el modelo registrado tal como en el ejemplo oficial, las distancias coseno eran
muy pequeñas y estaban muy juntas: 0,054 entre "A cat is sitting on the mat" y "A kitten rests
on a rug", frente a 0,138 con "The stock market crashed yesterday". Para este modelo lo habitual
son valores mucho más separados. Además, la norma L2 de los vectores ronda 7–8 (no están
normalizados).

**Hipótesis.** El `tokenizer.json` original tiene `padding = Fixed(128)`: todo texto se rellena
con `[PAD]` hasta 128 posiciones. Si AIRuntimeHost hace *mean pooling* sobre las 128 posiciones,
cada vector es una mezcla del texto real y de una gran componente común de `[PAD]`, cuyo peso
depende de lo corto que sea el texto. sentence-transformers solo promedia los tokens reales.

**Experimento.** Se copió `model.onnx` a `C:\onnx_runtime\model\minilm-sin-padding\` con un
`tokenizer.json` idéntico salvo `"padding": null` (se mantiene la truncación a 128). Con la DLL se
comprobó que ahora devuelve solo los tokens reales (`Hello world` → `[7592, 2088]`, sin ceros). Se
registró un segundo `EXTERNAL MODEL` temporal y se compararon los mismos pares con ambos:

```sql
-- Modelo temporal (se borró al terminar con DROP EXTERNAL MODEL ModeloPrueba_SinPadding)
CREATE EXTERNAL MODEL ModeloPrueba_SinPadding
WITH (LOCATION = 'C:\onnx_runtime\model\minilm-sin-padding', API_FORMAT = 'ONNX Runtime',
      MODEL_TYPE = EMBEDDINGS, MODEL = 'allMiniLM', PARAMETERS = '{"valid":"JSON"}',
      LOCAL_RUNTIME_PATH = 'C:\onnx_runtime\');

SELECT CAST(VECTOR_DISTANCE('cosine',
            CAST(AI_GENERATE_EMBEDDINGS(N'A cat is sitting on the mat' USE MODEL ModeloPrueba_SinPadding) AS VECTOR(384)),
            CAST(AI_GENERATE_EMBEDDINGS(N'A kitten rests on a rug'     USE MODEL ModeloPrueba_SinPadding) AS VECTOR(384)))
       AS DECIMAL(6,4));
-- (igual con el resto de pares y con ModeloEmbeddingsLocal)
```

| Par | Con padding (original) | Sin padding |
|---|---|---|
| EN gato / gatito (similar) | 0,0544 | 0,2206 |
| EN gato / bolsa (distinto) | 0,1384 | 0,4266 |
| ES mudanza / traslado (similar) | 0,0429 | 0,2401 |
| ES mudanza / seguridad (distinto) | 0,0492 | 0,2135  |
| ES pregunta de vacaciones / norma de vacaciones (similar) | 0,0893 | 0,2727 |
| ES pregunta de vacaciones / plan de comisiones (distinto) | 0,1050 | 0,3247 |

**Conclusiones.**
1. **Hipótesis confirmada.** Sin padding, las distancias se multiplican por 3–5: el `[PAD]` estaba
   entrando en el promedio.
2. **El problema de fondo es el sesgo por longitud.** El peso del `[PAD]` crece cuanto más corto es
   el texto, así que preguntas y fragmentos cortos (los `b`) se acercan entre sí por ser cortos, no
   por su significado. Sin padding se promedian solo los tokens reales, como en el entrenamiento
   del modelo.
3. **El español sigue siendo débil en ambas versiones.** El par mudanza/seguridad sale en el orden
   equivocado sin padding, y con padding las dos distancias eran casi iguales (0,043 frente a
   0,049). Es la limitación del vocabulario inglés del modelo; la calidad real se mide con las
   pruebas de `09_pruebas_rls.sql` sobre las normativas. La mejora natural sería un modelo
   multilingüe de 384 dimensiones, sin cambiar el esquema.

**Decisión.** `02_modelo_onnx.sql` registra la carpeta `minilm-sin-padding`, que genera
`scripts/descargar_modelo.py`. La carpeta original se conserva para poder repetir la comparación.

## Diagnóstico con Extended Events

```sql
CREATE EVENT SESSION ai_onnx_trace ON SERVER
ADD EVENT ai_generate_embeddings_airuntime_trace
    (ACTION (sqlserver.sql_text, sqlserver.session_id))
ADD TARGET package0.ring_buffer
WITH (MAX_MEMORY = 4096 KB, EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
      MAX_DISPATCH_LATENCY = 30 SECONDS, TRACK_CAUSALITY = ON, STARTUP_STATE = OFF);
GO
ALTER EVENT SESSION ai_onnx_trace ON SERVER STATE = START;
GO

-- Vuelve a lanzar la prueba de 02_modelo_onnx.sql y después:
SELECT event_data.value('(@timestamp)[1]', 'datetime2')                                  AS [timestamp],
       event_data.value('(data[@name = "model_name"]/value)[1]', 'nvarchar(200)')        AS model_name,
       event_data.value('(data[@name = "phase_name"]/value)[1]', 'nvarchar(100)')        AS phase,
       event_data.value('(data[@name = "message"]/value)[1]', 'nvarchar(max)')           AS message,
       event_data.value('(data[@name = "error_code"]/value)[1]', 'bigint')               AS error_code
FROM (SELECT CAST(t.target_data AS XML) AS target_data
      FROM sys.dm_xe_sessions AS s
      JOIN sys.dm_xe_session_targets AS t ON s.address = t.event_session_address
      WHERE s.name = 'ai_onnx_trace' AND t.target_name = 'ring_buffer') AS d
CROSS APPLY target_data.nodes('//RingBufferTarget/event') AS x(event_data);
GO

-- Al terminar
DROP EVENT SESSION ai_onnx_trace ON SERVER;
```

## Seguridad del runtime

La documentación avisa de que un modelo o una DLL comprometidos podrían sacar datos del servidor o
ejecutar código. Medidas que aplica el proyecto:

- El modelo sale del repositorio que usa el ejemplo oficial y `descargar_modelo.py` muestra su SHA-256.
- Solo `Rol_Empleado` (y el usuario de la prueba sin rol) tiene `EXECUTE` sobre el modelo.
- Los binarios (`*.onnx`, `*.dll`, `tokenizer.json`) se excluyen de Git con `.gitignore`.

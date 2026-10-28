# NormativaRAG: RAG de auditoría normativa con RLS en SQL Server 2025

Proyecto para la certificación **Microsoft DP-800 (SQL AI Developer Associate)**.
Autor: Víctor Pérez.

Es un sistema de consulta de normativas internas en lenguaje natural que sigue el
patrón **RAG** (Retrieval-Augmented Generation) con una arquitectura **Zero-App**:

- **Embeddings:** se generan **dentro de SQL Server 2025** con un modelo ONNX local
  (`CREATE EXTERNAL MODEL` + `AI_GENERATE_EMBEDDINGS`). No se usa Azure ni ningún servicio externo.
- **Retrieval:** búsqueda **híbrida** en un procedimiento almacenado T-SQL. Combina el ranking
  semántico (`VECTOR_DISTANCE` sobre una columna `VECTOR(384)`) y el ranking por palabras
  (índice full-text en español con `FREETEXTTABLE`) mediante **Reciprocal Rank Fusion**.
  Medido con 12 preguntas, el MRR pasa de 0,56 (solo vectores) a 0,81.
- **Seguridad:** la aporta **Row-Level Security** con roles de base de datos e `IS_MEMBER()`.
  El motor quita las filas no autorizadas antes de calcular la similitud.
- **Generation:** la hace **GitHub Copilot** (extensión MSSQL de VS Code), que ejecuta el
  procedimiento y redacta la respuesta solo con los fragmentos que devuelve SQL Server.

No hay ninguna aplicación intermedia: ni API, ni scripts Python en tiempo de
ejecución, ni tokens guardados en el código.

Especificación original: [docs/propuesta_de_proyecto_dp_800.md](docs/propuesta_de_proyecto_dp_800.md).
Arquitectura y decisiones: [docs/arquitectura.md](docs/arquitectura.md) y
[docs/defensa_dp800.md](docs/defensa_dp800.md).

---

## Estructura del repositorio

```
├── database/                       Scripts T-SQL, en orden de ejecución
│   ├── 00_reset_opcional.sql         Borra los objetos del proyecto (y los de la versión anterior)
│   ├── 01_configuracion_instancia.sql  Crea la BD, activa 'external AI runtimes enabled' y PREVIEW_FEATURES
│   ├── 02_modelo_onnx.sql            CREATE EXTERNAL MODEL (ONNX Runtime local) y prueba
│   ├── 03_tablas.sql                 Departamentos, Empleados, Normativas (VECTOR(384))
│   ├── 04_datos_prueba.sql           5 departamentos, 13 empleados, 37 normativas en 72 fragmentos
│   ├── 05_generar_embeddings.sql     UPDATE con AI_GENERATE_EMBEDDINGS
│   ├── 06_roles_y_usuarios.sql       Roles Rol_* y usuarios de prueba WITHOUT LOGIN
│   ├── 07_rls.sql                    TVF con IS_MEMBER() + SECURITY POLICY
│   ├── 08_busqueda_semantica.sql     dbo.usp_BuscarNormativa (híbrida, RRF) y dbo.vw_MiPerfil
│   ├── 09_pruebas_rls.sql            Validación: misma pregunta, distinto rol
│   └── 10_evaluacion_recuperacion.sql  Calidad de la recuperación: 12 preguntas, Top1/Top4/MRR
├── scripts/                        Solo para la instalación (no forman parte del RAG)
│   ├── descargar_modelo.py           Descarga model.onnx + tokenizer.json
│   └── preparar_onnx_runtime.ps1     Carpetas y permisos para MSSQLLaunchpad
├── docs/
│   ├── propuesta_de_proyecto_dp_800.md
│   ├── arquitectura.md
│   ├── instalacion_onnx.md           Detalle del runtime ONNX y diagnóstico
│   ├── demo_copilot.md               Guion de la demo con Copilot
│   ├── defensa_dp800.md              Justificación de cada decisión
│   └── img/                          Capturas de la demo con Copilot
├── presentation/
│   └── presentacion_defensa_dp800.pptx  Presentación de la defensa (17 diapositivas con notas)
├── .github/copilot-instructions.md   Reglas RAG para Copilot (responder solo con lo recuperado)
└── README.md
```

---

## Requisitos

| Componente | Detalle |
|---|---|
| Sistema operativo | Windows 11 (el runtime ONNX local solo existe en Windows) |
| SQL Server | **SQL Server 2025 (17.x) Developer**, instancia por defecto, autenticación de Windows |
| Característica de instalación | **Machine Learning Services and Language Extensions** (instala el servicio *SQL Server Launchpad*, que lanza `AIRuntimeHost`) |
| Característica de instalación | **Full-Text and Semantic Extractions for Search** (índice full-text en español para la búsqueda híbrida) |
| ONNX Runtime | `onnxruntime.dll` **1.19 o superior** (Windows x64) |
| Tokenizador | `tokenizers_cpp.dll` (ver el paso 3) |
| Modelo | [`nsense/all-MiniLM-L6-v2-onnx`](https://huggingface.co/nsense/all-MiniLM-L6-v2-onnx) (MIT, 384 dimensiones) |
| IDE | VS Code con la extensión **SQL Server (mssql)** y **GitHub Copilot** (Chat / modo agente) |
| Python (solo para la instalación) | 3.10 o superior con `huggingface_hub`, para descargar el modelo |

> ⚠️ El runtime ONNX local de `CREATE EXTERNAL MODEL` es una **característica en preview**
> de SQL Server 2025 y necesita `PREVIEW_FEATURES = ON`. La sintaxis se ha comprobado con
> la documentación de Microsoft Learn de octubre de 2026 y puede cambiar.

---

## Instalación paso a paso

### 1. SQL Server 2025 con Machine Learning Services

En el instalador de SQL Server 2025 Developer, marca **Machine Learning Services and Language
Extensions** (no hace falta instalar R ni Python). Si SQL Server ya está instalado, añade la
característica con *Agregar características a una instalación existente*.

Comprueba que el servicio **SQL Server Launchpad (MSSQLSERVER)** existe y está iniciado
(`services.msc`).

### 2. ONNX Runtime

1. Descarga `onnxruntime-win-x64-<versión>.zip` (1.19 o superior) de
   <https://github.com/microsoft/onnxruntime/releases>.
2. Descomprímelo y copia `lib\onnxruntime.dll` a `C:\onnx_runtime\`.

Otra opción, que es la que se usó en este proyecto (versión 1.31.0): descargar el paquete oficial
[`Microsoft.ML.OnnxRuntime`](https://www.nuget.org/packages/Microsoft.ML.OnnxRuntime) de nuget.org
(un `.nupkg` es un zip), comprobar su SHA-512 con el que publica NuGet y extraer
`runtimes\win-x64\native\onnxruntime.dll`. Comprueba que la DLL tiene una firma Authenticode válida de
*Microsoft Corporation* (`Get-AuthenticodeSignature`).

### 3. Tokenizador `tokenizers_cpp.dll`

`AI_GENERATE_EMBEDDINGS` tokeniza el texto con una DLL que debe llamarse exactamente
**`tokenizers_cpp.dll`** y estar en `C:\onnx_runtime\`. Hay dos opciones:

- **A. Compilarla (es lo que se hizo en este proyecto)** a partir del código fuente de
  `PARTHSQL/tokenizers-cpp` `v0.1.1`, que es `mlc-ai/tokenizers-cpp` más las funciones
  exportadas que espera `AIRuntimeHost`. Necesitas VS 2022 Build Tools (C++), CMake y Rust 1.87.
  Los pasos exactos, las versiones y el hash del resultado están en
  [docs/instalacion_onnx.md](docs/instalacion_onnx.md#compilación-usada-en-este-proyecto-27102026).
- **B. Usar la DLL precompilada** que enlaza el blog oficial *Azure SQL Dev Corner*
  ([artículo](https://devblogs.microsoft.com/azure-sql/create-embeddings-in-sql-server-2025-rc0-with-a-local-onnx-model-on-windows/)):
  `tokenizers_cpp-release.dll` de la release `v0.1.1` de `PARTHSQL/tokenizers-cpp`,
  **renombrada** a `tokenizers_cpp.dll`.

> 🔒 Una DLL nativa se carga en un proceso del servidor. Úsala solo si confías en su origen
> y verifica su hash antes de copiarla.

### 4. Modelo ONNX y tokenizador

```powershell
pip install huggingface_hub
python scripts\descargar_modelo.py
```

El script deja `model.onnx` y `tokenizer.json` en `C:\onnx_runtime\model\all-MiniLM-L6-v2-onnx\`
(el original) y crea **`C:\onnx_runtime\model\minilm-sin-padding\`**, con el mismo modelo y el
`tokenizer.json` con `"padding": null`. **Esta segunda carpeta es la que registra el script 02.**
Con el relleno fijo a 128 tokens del original, AIRuntimeHost promedia también los `[PAD]`: las
distancias se comprimen y aparece un sesgo por longitud del texto. La prueba está en
[docs/instalacion_onnx.md](docs/instalacion_onnx.md#prueba-del-padding-27102026-por-qué-location-apunta-a-minilm-sin-padding).

Estructura final:

```
C:\onnx_runtime\
├── onnxruntime.dll
├── tokenizers_cpp.dll
└── model\
    ├── all-MiniLM-L6-v2-onnx\        (original, solo como referencia)
    │   ├── model.onnx
    │   └── tokenizer.json
    └── minilm-sin-padding\           (LOCATION del EXTERNAL MODEL)
        ├── model.onnx
        └── tokenizer.json            "padding": null
```

### 5. Permisos de carpeta

En PowerShell **como administrador**:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\preparar_onnx_runtime.ps1
```

El script comprueba que están los cuatro archivos y da a `MSSQLLaunchpad` acceso a `C:\onnx_runtime`.

### 6. Scripts de base de datos

Conéctate a `localhost` con autenticación de Windows (VS Code mssql o SSMS) y ejecuta en orden.
Los scripts están en UTF-8; si usas `sqlcmd`, añade `-f 65001` para que los acentos se carguen bien.

| # | Script | Qué comprobar |
|---|---|---|
| 00 | `00_reset_opcional.sql` | Solo si la BD ya tiene objetos de una versión anterior |
| 01 | `01_configuracion_instancia.sql` | `value_in_use = 1` y `PREVIEW_FEATURES = 1` |
| 02 | `02_modelo_onnx.sql` | La prueba devuelve un array JSON y `Dimensiones = 384` |
| 03 | `03_tablas.sql` | Tres tablas creadas |
| 04 | `04_datos_prueba.sql` | 19 / 14 / 13 / 14 / 12 fragmentos por departamento (72) |
| 05 | `05_generar_embeddings.sql` | `SinVector = 0` y `Dimensiones = 384`. La prueba final usa solo vectores: puede no traer la normativa correcta (la calidad se mide en el script 10) |
| 06 | `06_roles_y_usuarios.sql` | Lista de pertenencia a roles |
| 07 | `07_rls.sql` | Política `PoliticaNormativas` activa |
| 08 | `08_busqueda_semantica.sql` | La prueba como administrador devuelve 0 filas (RLS también afecta a dbo) |
| 09 | `09_pruebas_rls.sql` | Cada usuario ve solo lo suyo; `invitado_externo` ve 0 filas |
| 10 | `10_evaluacion_recuperacion.sql` | Híbrida ≥ vectorial en Top4 y MRR; el procedimiento acierta en el top 4 lo mismo que la fila "Hibrida" |

> **El orden importa:** los embeddings (05) se generan antes de activar RLS (07). Si se
> vuelve a ejecutar 04 o 05 con la política ya creada, los scripts la desactivan y la
> reactivan al terminar, porque el *filter predicate* también filtra `UPDATE` y `DELETE`.

### 7. Demo RAG con Copilot

Sigue [docs/demo_copilot.md](docs/demo_copilot.md). Por ejemplo, en el chat de Copilot
(modo agente) con la conexión `localhost / NormativaRAG` activa:

```
Actúa como el usuario carlos_ventas y responde: ¿Qué días de permiso me corresponden
por mudanza según las políticas de mi departamento?
```

Copilot ejecuta `EXECUTE AS USER = 'carlos_ventas'; EXEC dbo.usp_BuscarNormativa ...; REVERT;`
(pide tu confirmación) y redacta la respuesta a partir de los fragmentos devueltos.

---

## Solución de problemas

| Síntoma | Causa probable |
|---|---|
| Error al crear el modelo o en la primera llamada a `AI_GENERATE_EMBEDDINGS` | `PREVIEW_FEATURES` desactivado en la BD, o falta `external AI runtimes enabled` |
| La llamada falla o se queda bloqueada | Launchpad detenido o Machine Learning Services sin instalar |
| Error al cargar la DLL | `tokenizers_cpp.dll` con otro nombre, versión incorrecta de `onnxruntime.dll` o permisos de `MSSQLLaunchpad` |
| Error de conversión a `VECTOR(384)` | El modelo no es el esperado (las dimensiones no coinciden) |
| La búsqueda devuelve 0 filas | Te has conectado como administrador sin `EXECUTE AS USER` (RLS funcionando como debe) |

Para un diagnóstico detallado, usa la sesión de Extended Events `ai_generate_embeddings_airuntime_trace`
([docs/instalacion_onnx.md](docs/instalacion_onnx.md)).

---

## Limitaciones conocidas

- El `tokenizer.json` del modelo **trunca a 128 tokens**. Por eso las normativas largas están
  divididas en dos fragmentos (`a`/`b`), y se ha comprobado con la DLL que ninguno llega al límite.
  Si añades normativas nuevas, mide sus tokens
  (ver [docs/instalacion_onnx.md](docs/instalacion_onnx.md#longitud-máxima-128-tokens)).

- `all-MiniLM-L6-v2` se entrenó sobre todo con textos en inglés. Por sí solo, en español da un
  MRR de 0,56. La búsqueda híbrida con full-text en español lo compensa (MRR 0,81, ver
  `10_evaluacion_recuperacion.sql`). Un modelo multilingüe de 384 dimensiones (por ejemplo
  `paraphrase-multilingual-MiniLM-L12-v2` exportado a ONNX) mejoraría además la parte semántica
  sin cambiar el esquema.
- La búsqueda es exacta (fuerza bruta). Con el volumen del proyecto (decenas de fragmentos) es lo
  correcto. Con millones de filas habría que valorar `CREATE VECTOR INDEX` (DiskANN, en preview).
- Los usuarios de prueba son `WITHOUT LOGIN` y se usan con `EXECUTE AS USER`. En un despliegue real
  cada empleado se conectaría con su identidad de Windows o Entra ID, asignada a un usuario de BD
  que pertenece a su rol (ver [docs/defensa_dp800.md](docs/defensa_dp800.md)).

---

## Créditos

- Modelo: [nsense/all-MiniLM-L6-v2-onnx](https://huggingface.co/nsense/all-MiniLM-L6-v2-onnx) (MIT),
  derivado de `sentence-transformers/all-MiniLM-L6-v2`.
- Documentación consultada:
  [CREATE EXTERNAL MODEL](https://learn.microsoft.com/sql/t-sql/statements/create-external-model-transact-sql),
  [AI_GENERATE_EMBEDDINGS](https://learn.microsoft.com/sql/t-sql/functions/ai-generate-embeddings-transact-sql),
  [Copilot agent mode (MSSQL)](https://learn.microsoft.com/sql/tools/visual-studio-code-extensions/github-copilot/agent-mode).
- La empresa *Normatech S.L.* y sus datos son ficticios.

# Defensa del proyecto: decisiones técnicas y su justificación

Este documento explica **por qué** el proyecto está construido así, para poder defenderlo
ante el tribunal de la certificación DP-800.

---

## 1. Cambios respecto a la versión anterior

| Antes | Problema | Ahora |
|---|---|---|
| Scripts Python (`sentence-transformers` + `pyodbc`) generaban los embeddings | Contradecía la arquitectura Zero-App de la propuesta: la IA estaba fuera del motor | `CREATE EXTERNAL MODEL` (ONNX Runtime) + `AI_GENERATE_EMBEDDINGS` dentro de SQL Server |
| La respuesta la generaba GPT-4o mediante la API de GitHub Models desde Python | Había una app intermedia y un **token escrito en el código fuente** | Copilot en VS Code hace la generación; no hay ningún secreto en el repositorio |
| El ONNX se guardaba en una tabla `VARBINARY(MAX)` y se usaba `PREDICT` | `PREDICT` puntúa modelos tabulares numéricos, no tokeniza texto: **no puede generar embeddings de frases** | El modelo se registra como `EXTERNAL MODEL`; el tokenizador va en `tokenizers_cpp.dll` |
| `CREATE NONCLUSTERED INDEX` sobre la columna `VECTOR` con el comentario "HNSW" | Un índice B-tree no admite `VECTOR`, y SQL Server 2025 no usa HNSW: su índice vectorial es **DiskANN** (`CREATE VECTOR INDEX`, en preview) | Sin índice; búsqueda **exacta** con `VECTOR_DISTANCE` |
| RLS con `SESSION_CONTEXT(N'Departamento')` | Lo establece el cliente con `sp_set_session_context`; Copilot no puede hacerlo y, además, cualquier cliente podría falsearlo si no se marca `@read_only` | RLS con roles de base de datos e `IS_MEMBER()` |
| Columna `RolAcceso` de texto libre en una única tabla | Sin modelo relacional y sin integridad | `Departamentos` / `Empleados` / `Normativas` con claves ajenas |
| Script 03 que no insertaba datos y numeración duplicada (dos 03, dos 05) | El proyecto no se podía reproducir | Scripts `00`–`10` en orden de ejecución y 37 normativas de prueba (72 fragmentos) |

---

## 2. Decisiones clave

### 2.1 ¿Por qué ONNX local y no Azure OpenAI?
- Requisito de la propuesta: todo en local y sin servicios externos.
- **Confidencialidad:** el texto de las normativas (incluidas las confidenciales) no sale del
  servidor para vectorizarse.
- Coste cero por llamada y sin latencia de red.
- Contrapartida conocida: es una **característica en preview** (`PREVIEW_FEATURES = ON`), solo
  existe en Windows y necesita Machine Learning Services.

### 2.2 ¿Por qué `all-MiniLM-L6-v2` (384 dimensiones)?
- Es el modelo del ejemplo oficial de Microsoft (`nsense/all-MiniLM-L6-v2-onnx`), que garantiza
  que el formato de entrada y salida es compatible con AIRuntimeHost.
- Es ligero (unos 90 MB) y genera 384 dimensiones: con `float32` son 1,5 KB por vector.
- **No se usa tal cual viene en el ejemplo oficial.** Su `tokenizer.json` rellena todos los textos
  hasta 128 tokens, y AIRuntimeHost promedia también esos `[PAD]`. Se comprobó con pares de frases
  conocidos: las distancias se comprimían de 3 a 5 veces y había un sesgo por longitud del texto.
  El proyecto registra una copia con `"padding": null`
  ([prueba completa](instalacion_onnx.md#prueba-del-padding-27102026-por-qué-location-apunta-a-minilm-sin-padding)).
  Es un ejemplo de validar con datos un ejemplo oficial en lugar de copiarlo sin más.
- Limitación reconocida: está optimizado para inglés. La columna `VECTOR(384)` permitiría
  cambiar a un modelo multilingüe de 384 dimensiones sin tocar el esquema.

### 2.3 ¿Por qué búsqueda exacta y sin índice?
- `VECTOR_DISTANCE` calcula la distancia contra todas las filas visibles: es un **k-NN exacto**
  con recall del 100 %.
- Con decenas o cientos de fragmentos, el coste es despreciable.
- Un índice ANN (DiskANN con `CREATE VECTOR INDEX` y `VECTOR_SEARCH`) es aproximado, está en
  preview y solo compensa con cientos de miles o millones de vectores.
- **Interacción con RLS:** con la búsqueda exacta, el predicado de seguridad se aplica antes del
  `TOP N`, de modo que siempre se devuelven los N mejores fragmentos **autorizados**. Con un
  índice aproximado habría que comprobar cómo se combina el filtrado con la búsqueda en el índice.

### 2.4 ¿Por qué distancia coseno?
- Los embeddings de sentence-transformers se comparan por ángulo. La distancia coseno
  (1 − similitud) va de 0 (idénticos) a 2 (opuestos) y no depende de la longitud del vector.

### 2.5 ¿Por qué `IS_MEMBER()` y no `SESSION_CONTEXT`?
- `IS_MEMBER()` evalúa la **identidad real** del usuario de base de datos. La pertenencia a roles
  la gestiona el administrador con `ALTER ROLE`, y el cliente no puede cambiarla.
- `SESSION_CONTEXT` depende de que una **aplicación de confianza** lo establezca en cada
  conexión. En una arquitectura Zero-App no hay esa aplicación, y Copilot no tiene ningún
  mecanismo para hacerlo.
- `IS_MEMBER()` también admite **grupos de Windows** (`DOMINIO\Grupo`) y de Entra ID: en
  producción, un grupo de Active Directory se puede asignar a cada rol.

### 2.6 ¿Por qué el rol se lee de la tabla `Departamentos`?
- El predicado `IS_MEMBER(d.RolBD) = 1` no tiene departamentos escritos en el código. Para añadir
  uno basta con insertar una fila y crear su rol, sin tocar la función ni la política.
- `Rol_Direccion` es la única excepción explícita (ve todo), porque es una regla de negocio
  transversal.

### 2.7 ¿Por qué `SCHEMABINDING` en la función y en la política?
- Impide modificar o eliminar las columnas y tablas que usa el predicado mientras la política
  existe, así que la seguridad no se puede romper por accidente con un `ALTER TABLE`.
- Con `SCHEMABINDING = ON` en la política (el valor por defecto), la función de predicado tiene
  que estar enlazada al esquema. Además, al ser una TVF **inline**, el optimizador la integra en
  el plan de cada consulta como si fuera un `WHERE` más (se ve en el plan de ejecución, prueba 7
  de `09_pruebas_rls.sql`).

### 2.8 ¿Por qué usuarios `WITHOUT LOGIN` y `EXECUTE AS USER`?
- Permiten probar el RLS con varias identidades **sin crear logins ni guardar contraseñas**.
- La conexión de Copilot es la del desarrollador (`sysadmin` → `dbo`). Como `dbo` no puede
  pertenecer a ningún rol, `IS_MEMBER()` le devuelve 0 y **no ve nada**: el RLS no tiene una
  excepción oculta para el administrador.
- **En producción** cada empleado se conectaría con su propia identidad
  (`CREATE USER [DOMINIO\ana] FROM LOGIN [DOMINIO\ana]` o un usuario de Entra ID) y no habría
  ningún `EXECUTE AS`. El procedimiento y la política no cambiarían.

### 2.9 ¿Por qué el procedimiento no tiene `EXECUTE AS OWNER`?
- Si lo tuviera, el contexto de seguridad sería el del propietario (`dbo`) y `IS_MEMBER()`
  evaluaría al propietario y no a quien llama, con lo que el RLS dejaría de funcionar.
- Sin `EXECUTE AS`, el **encadenamiento de propiedad** (todo pertenece a `dbo`) permite leer las
  tablas sin dar `SELECT` sobre `Empleados`, y el RLS sigue evaluando al usuario que llama.
- **El encadenamiento de propiedad no cubre el modelo externo.** Se probó en una base de datos
  temporal con un usuario sin `EXECUTE` sobre el modelo: lo deniegan tanto la llamada directa como
  la llamada a través del procedimiento (error 15151, que además no revela si el modelo existe). Por
  eso `06_roles_y_usuarios.sql` concede `EXECUTE ON EXTERNAL MODEL` a `Rol_Empleado`. Es necesario,
  no redundante, y permite controlar por separado quién puede usar el modelo de IA.

### 2.10 ¿Por qué se generan los embeddings antes de activar el RLS?
- El *filter predicate* se aplica también a `UPDATE` y `DELETE`. Con la política activa, el
  administrador (`dbo`) no vería ninguna fila y el `UPDATE` vectorizaría 0 filas sin dar error.
- Los scripts 04 y 05 desactivan la política temporalmente si ya existe y la reactivan al final.

### 2.11 ¿Por qué búsqueda híbrida (vectores + full-text) con Reciprocal Rank Fusion?
- **Se midió antes de decidir.** Con solo vectores, 12 preguntas típicas daban: acierto en 1.ª
  posición 5/12, en el top 4 8/12, MRR 0,56. La pregunta de ejemplo de la propuesta (mudanza)
  salía en la posición 11 y la de acoso en la 33. La causa es que el modelo de embeddings se
  entrenó en inglés.
- **Los dos métodos se complementan.** Full-text en español (`LANGUAGE 3082`, con lematización)
  acierta cuando coinciden las palabras: acoso pasa de la posición 33 a la 1. Los vectores aportan
  cuando cambian las palabras pero no el significado: en fallecimiento, full-text la deja 6.ª y la
  fusión 2.ª.
- **RRF** puntúa cada fila con `1/(k + rank_vectorial) + 1/(k + rank_fulltext)`. Solo usa
  posiciones, así que no hay que normalizar escalas incomparables (una distancia coseno de 0 a 2
  frente al `RANK` de full-text, que no tiene límite superior).
- **k = 60**, el valor estándar (Cormack, Clarke y Büttcher, 2009). k = 20 daba una pregunta más
  en el top 4, pero elegir k con las mismas 12 preguntas de prueba sería **sobreajustar** a la
  evaluación.
- **Resultado** (`10_evaluacion_recuperacion.sql`): top 1 8/12, top 4 11/12, MRR 0,81.
- **Fragmentos hermanos.** Al dividir las normativas en `a`/`b`, el top N podía traer solo una
  mitad. En la prueba con `carlos_ventas` sobre la mudanza, llegaba VEN-TRA-01b (gastos) sin
  VEN-TRA-01a (los 3 días). Por eso, después de elegir los N mejores fragmentos, el procedimiento
  añade el hermano de cada normativa recuperada: se recupera por fragmento, pero se entrega la
  normativa completa (patrón *small-to-big* o *parent document retrieval*). La columna
  `EsFragmentoHermano` lo deja visible.
- **Todo sigue dentro del motor** (Zero-App) y el RLS se mantiene: `FREETEXTTABLE` devuelve claves
  del índice, pero solo se usan al unirlas con `dbo.Normativas`, y esa unión aplica el predicado
  de seguridad. Los dos rankings se calculan solo sobre filas autorizadas.

---

## 3. Otras preguntas posibles

**¿Puede Copilot (el LLM) saltarse el RLS?**
No. Copilot solo recibe las filas que devuelve SQL Server, y el motor aplica el predicado antes de
devolverlas. Aunque la instrucción al LLM se manipule (*prompt injection*), no puede leer lo que
no recibe. El único riesgo es que alguien ejecute `EXECUTE AS USER` con otro usuario; para eso
hace falta el permiso `IMPERSONATE` o ser `sysadmin`, y en producción ningún empleado lo tendría.

**¿Y los ataques por canal lateral contra el RLS?**
Microsoft documenta que, con consultas diseñadas a propósito (por ejemplo, errores de división
por cero), se podrían deducir valores de filas filtradas. Aquí se mitiga porque los usuarios no
tienen permisos de escritura ni de consulta ad hoc en producción: solo `EXECUTE` sobre el
procedimiento.

**¿Qué pasa si la pregunta no tiene relación con ninguna normativa?**
El procedimiento devuelve igualmente las N filas más cercanas, con distancias altas. Las
instrucciones de Copilot le obligan a decir que no hay normativa aplicable si los fragmentos no
responden a la pregunta. Una mejora sería añadir un parámetro `@DistanciaMaxima`.

**¿Por qué no se usa `AI_GENERATE_CHUNKS`?**
Porque el troceado tenía que ser **por frases y comprobado con el tokenizador real**.
`AI_GENERATE_CHUNKS` (`CHUNK_TYPE = FIXED`) corta por número de caracteres, sin saber de tokens ni
de frases. El `tokenizer.json` del modelo **trunca a 128 tokens** sin avisar, y con su vocabulario
inglés el español se divide en muchos subtokens: 35 de las 37 normativas superaban el límite y
solo se habría vectorizado su comienzo. Por eso cada una se dividió en dos fragmentos (`a`/`b`)
cortando entre frases, y se midió cada fragmento (título + contenido, lo que vectoriza el script
05) con la propia `tokenizers_cpp.dll`. Resultado: 72 fragmentos, el más largo de 126 tokens y
ninguno truncado. Se repite el título en cada fragmento para que ambos conserven el tema
(*contextual chunking*).

**¿Qué partes están en preview?**
El runtime ONNX local de `CREATE EXTERNAL MODEL` / `AI_GENERATE_EMBEDDINGS` (necesita
`PREVIEW_FEATURES`). El tipo `VECTOR` y `VECTOR_DISTANCE` no necesitan `PREVIEW_FEATURES` en
SQL Server 2025; los índices vectoriales y `VECTOR_SEARCH` siguen en preview y no se usan.

# Propuesta de Proyecto: Sistema RAG de Auditoría Normativa con Seguridad RLS en SQL Server 2025

**Autor:** Víctor Pérez  
**Certificación Objetivo:** Microsoft DP-800 (SQL AI Developer Associate)  

---

## 1. Objetivo de la Propuesta

El objetivo de este proyecto es diseñar, implementar y documentar una solución de base de datos íntegramente local basada en SQL Server 2025, que actuará como un sistema seguro de consulta de normativas y políticas empresariales.

El proyecto resuelve el problema crítico de la confidencialidad en los sistemas de IA generativa corporativos. Se implementará un patrón RAG (Retrieval-Augmented Generation) utilizando capacidades vectoriales nativas y Row-Level Security (RLS). La innovación de este enfoque radica en su arquitectura Zero-App: el usuario final (en este caso, operando desde el entorno de desarrollo) interactuará en lenguaje natural a través de GitHub Copilot (extensión MSSQL). Copilot interpretará la pregunta, ejecutará la búsqueda de similitud vectorial en la base de datos protegida y redactará la respuesta final basándose única y exclusivamente en los fragmentos de texto devueltos por SQL Server a los que el rol del usuario tenga permiso.

Esta solución cubre de forma transversal los Bloques A, B, C, E, F y G requeridos por la certificación DP-800, demostrando un dominio avanzado de las características de IA nativas de SQL Server 2025.

---

## 2. Tecnologías y Herramientas

Todo el ecosistema se ejecutará de manera local (Windows 11) empleando las siguientes tecnologías:

*   **Motor de Base de Datos:** SQL Server 2025 Developer Edition.
*   **Modelos de IA Integrados:** ONNX Runtime ejecutado nativamente dentro de SQL Server (`CREATE EXTERNAL MODEL`) para generar los embeddings (vectores) matemáticos de los textos de forma local y ligera, sin depender de servicios externos.
*   **Entorno de Desarrollo:** Visual Studio o Visual Studio Code, configurado con la extensión oficial de SQL Server (mssql).
*   **Motor RAG y Asistente SQL:** GitHub Copilot (Agent Mode). Se utilizará el participante `@mssql` en el chat del IDE para:
    1.  Asistir en la creación del código T-SQL durante el desarrollo.
    2.  Actuar como el LLM del sistema RAG: recibiendo consultas en lenguaje natural, conectándose a la base de datos para recuperar los vectores similares y redactando la respuesta final al usuario a partir de los datos leídos.
*   **Control de Versiones:** Git y GitHub para la gestión del código y la documentación (`README.md`).

---

## 3. Fases de Desarrollo (Etapas)

El proyecto se construirá de manera iterativa siguiendo estas fases, alineadas con la rúbrica de evaluación:

### Fase 1: Configuración de la Base de Datos y Modelo ONNX
*   Instalación del entorno SQL Server 2025.
*   Habilitación de las configuraciones necesarias para la ejecución de scripts externos.
*   Carga de un modelo ligero de embeddings en formato ONNX directamente en el motor de SQL Server mediante el comando `CREATE EXTERNAL MODEL`.

### Fase 2: Estructura, Datos de Prueba y Embeddings
*   Diseño del modelo relacional asistido por Copilot (Departamentos, Empleados, Normativas).
*   Creación de la tabla Normativas incorporando la nueva columna nativa tipo `VECTOR`.
*   Inserción de datos de prueba (textos de convenios, políticas, cláusulas).
*   Desarrollo de un script T-SQL que utilice la función predictiva nativa sobre el modelo ONNX para convertir los textos introducidos en vectores y guardarlos en la base de datos.

### Fase 3: Seguridad de Datos Estricta - RLS 
*   Creación de roles de seguridad (ej. `Rol_RRHH`, `Rol_Ventas`, `Rol_Direccion`).
*   Desarrollo de una Función de Valores de Tabla (TVF) que evalúe si el rol del usuario conectado tiene permisos sobre el ID de departamento de la fila.
*   Implementación de la `SECURITY POLICY` (RLS) sobre la tabla de normativas para garantizar que las búsquedas vectoriales posteriores sean intrínsecamente seguras a nivel de fila.

### Fase 4: Motor de Búsqueda Vectorial 
*   Creación de funciones y procedimientos almacenados T-SQL para la búsqueda semántica.
*   Uso de la función matemática `VECTOR_DISTANCE` para medir la similitud entre la pregunta del usuario (convertida a vector con ONNX) y las normativas almacenadas.
*   Validación de la consulta: comprobación de que el motor SQL filtra previamente por RLS antes de devolver los fragmentos con menor distancia (mayor coincidencia).

### Fase 5: Ejecución del Patrón RAG con Copilot
*   **Interacción Text-to-SQL:** Uso del chat de GitHub Copilot en Visual Studio (`@mssql`) para realizar la petición en lenguaje natural (ej. *"¿Qué días de permiso me corresponden por mudanza según las políticas de mi departamento?"*).
*   **Retrieval:** Copilot ejecutará la consulta de búsqueda vectorial diseñada en la Fase 4.
*   **Generation:** Copilot leerá la respuesta tabular segura devuelta por SQL Server y generará una respuesta redactada, completando así el flujo RAG directamente en la interfaz del IDE.

### Fase 6: Documentación y Preparación de Entregables
*   Estructuración del repositorio en GitHub (`/database`, `/docs`, etc.).
*   Redacción del `README.md` con las instrucciones detalladas de instalación y reproducción del proyecto.
*   Elaboración de la presentación (`.pptx`) para la defensa, mostrando el diagrama de arquitectura y la ejecución interactiva en Visual Studio.
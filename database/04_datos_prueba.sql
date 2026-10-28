/* =============================================================================
   04_datos_prueba.sql
   -----------------------------------------------------------------------------
   Fase 2. Datos de prueba: departamentos, empleados y normativas.

   La empresa (Normatech S.L.) es ficticia. Las normativas de "General" se basan
   en la legislación laboral española vigente (Estatuto de los Trabajadores tras
   el RDL 5/2023, Ley 10/2021 de trabajo a distancia, art. 88 LOPDGDD,
   Ley 2/2023 de protección del informante) y en ellas la empresa mejora
   algunos mínimos legales. Las de cada departamento son políticas internas
   inventadas para el proyecto.

   Diseño pensado para la demostración de RLS: hay preguntas cuya respuesta
   cambia según el departamento (teletrabajo, mudanza o traslado, gastos,
   guardias), de modo que dos usuarios que preguntan lo mismo reciben
   fragmentos distintos.

   Fragmentación (chunking): el tokenizer.json del modelo trunca a 128 tokens
   y, con su vocabulario inglés, el español ocupa muchos subtokens. Por eso
   cada normativa que pasaba de 128 tokens se ha dividido en dos fragmentos
   por frases, con el mismo título y código más sufijo: GEN-PER-01a y
   GEN-PER-01b son la misma normativa. Se repite el título en cada fragmento
   para que ambos conserven el contexto. Resultado: 37 normativas en 72
   fragmentos. Se ha comprobado con tokenizers_cpp.dll que, con
   Título + ". " + Contenido (lo que vectoriza el script 05), ninguno llega a
   128 tokens (el máximo es 126). Ver docs/instalacion_onnx.md.
   Se puede volver a ejecutar: vacía y recarga las tablas.
   ============================================================================= */
USE NormativaRAG;
GO

-- Si la política de RLS ya existe, se desactiva para poder recargar los datos
-- (el filter predicate también filtra los DELETE). Se reactiva al final.
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = N'PoliticaNormativas')
    EXEC (N'ALTER SECURITY POLICY Seguridad.PoliticaNormativas WITH (STATE = OFF);');
GO

DELETE FROM dbo.Normativas;
DELETE FROM dbo.Empleados;
DELETE FROM dbo.Departamentos;
GO

/* ---------------------------------------------------------------------------
   1. Departamentos
   --------------------------------------------------------------------------- */
INSERT INTO dbo.Departamentos (DepartamentoId, Nombre, RolBD, EsGeneral)
VALUES
    (1, N'General (toda la plantilla)', N'Rol_Empleado',  1),
    (2, N'Recursos Humanos',            N'Rol_RRHH',      0),
    (3, N'Ventas',                      N'Rol_Ventas',    0),
    (4, N'Tecnología (IT)',             N'Rol_IT',        0),
    (5, N'Dirección',                   N'Rol_Direccion', 0);
GO

/* ---------------------------------------------------------------------------
   2. Empleados (los que tienen UsuarioBD se usan en las pruebas de RLS)
   --------------------------------------------------------------------------- */
INSERT INTO dbo.Empleados (Nombre, Apellidos, Email, Puesto, FechaAlta, DepartamentoId, UsuarioBD)
VALUES
    (N'Ana',     N'García Ruiz',      N'ana.garcia@normatech.example',     N'Técnica de RRHH',            '2021-03-01', 2, N'ana_rrhh'),
    (N'Javier',  N'Moreno Díaz',      N'javier.moreno@normatech.example',  N'Responsable de Selección',   '2019-09-16', 2, NULL),
    (N'Elena',   N'Navarro Gil',      N'elena.navarro@normatech.example',  N'Administración de Personal', '2022-01-10', 2, NULL),
    (N'Carlos',  N'López Martín',     N'carlos.lopez@normatech.example',   N'Comercial de zona Norte',    '2020-05-04', 3, N'carlos_ventas'),
    (N'Sofía',   N'Romero Castro',    N'sofia.romero@normatech.example',   N'Key Account Manager',        '2018-11-12', 3, NULL),
    (N'Daniel',  N'Ortega Vidal',     N'daniel.ortega@normatech.example',  N'Comercial de zona Sur',      '2023-02-20', 3, NULL),
    (N'Laura',   N'Serrano Blanco',   N'laura.serrano@normatech.example',  N'Jefa de Ventas',             '2017-06-01', 3, NULL),
    (N'Lucía',   N'Fernández Torres', N'lucia.fernandez@normatech.example',N'Ingeniera DevOps',           '2022-09-05', 4, N'lucia_it'),
    (N'Pablo',   N'Jiménez Herrera',  N'pablo.jimenez@normatech.example',  N'Administrador de Sistemas',  '2016-04-18', 4, NULL),
    (N'Irene',   N'Molina Prieto',    N'irene.molina@normatech.example',   N'Desarrolladora Backend',     '2024-01-15', 4, NULL),
    (N'Raúl',    N'Delgado Suárez',   N'raul.delgado@normatech.example',   N'Responsable de Seguridad',   '2019-02-11', 4, NULL),
    (N'Marta',   N'Sánchez Vega',     N'marta.sanchez@normatech.example',  N'Directora General',          '2015-01-07', 5, N'marta_direccion'),
    (N'Andrés',  N'Ramos Iglesias',   N'andres.ramos@normatech.example',   N'Director Financiero',        '2016-10-03', 5, NULL);
GO

/* ---------------------------------------------------------------------------
   3. Normativas
   --------------------------------------------------------------------------- */

-- 3.1 General (toda la plantilla) -------------------------------------------
INSERT INTO dbo.Normativas (DepartamentoId, Codigo, Titulo, Contenido, FechaVigencia)
VALUES
(1, 'GEN-PER-01a', N'Permiso retribuido por mudanza o traslado de domicilio',
 N'Toda persona trabajadora tiene derecho a un día laborable de permiso retribuido por traslado de su domicilio habitual, conforme al artículo 37.3.c del Estatuto de los Trabajadores.',
 '2026-01-01'),
(1, 'GEN-PER-01b', N'Permiso retribuido por mudanza o traslado de domicilio',
 N'El permiso debe solicitarse en el portal del empleado con al menos 5 días de antelación y justificarse después con el certificado de empadronamiento o el contrato de alquiler o compraventa. Si el cambio de domicilio lo impone la empresa, se aplica la política específica del departamento.',
 '2026-01-01'),
(1, 'GEN-PER-02', N'Permiso por matrimonio o registro de pareja de hecho',
 N'Por matrimonio o por registro de pareja de hecho se conceden 15 días naturales de permiso retribuido. El permiso puede empezar el primer día laborable siguiente al hecho causante y debe solicitarse con 15 días de antelación. Se justifica con el certificado del Registro Civil o del registro de parejas de hecho correspondiente.',
 '2026-01-01'),
(1, 'GEN-PER-03a', N'Permiso por accidente, enfermedad grave u hospitalización de familiares',
 N'Se conceden 5 días laborables de permiso retribuido por accidente o enfermedad grave, hospitalización o intervención quirúrgica sin hospitalización que necesite reposo domiciliario del cónyuge, de la pareja de hecho o de parientes hasta el segundo grado de consanguinidad o afinidad.',
 '2026-01-01'),
(1, 'GEN-PER-03b', N'Permiso por accidente, enfermedad grave u hospitalización de familiares',
 N'El permiso de 5 días también se aplica cuando el afectado es cualquier persona que conviva con el trabajador y necesite su cuidado efectivo. Los días pueden disfrutarse mientras dure el hecho causante.',
 '2026-01-01'),
(1, 'GEN-PER-04a', N'Permiso por fallecimiento de familiares',
 N'Por fallecimiento del cónyuge, de la pareja de hecho o de parientes hasta el segundo grado de consanguinidad o afinidad se conceden 2 días de permiso retribuido, que pasan a 4 días cuando sea necesario desplazarse fuera de la provincia.',
 '2026-01-01'),
(1, 'GEN-PER-04b', N'Permiso por fallecimiento de familiares',
 N'Normatech mejora este mínimo legal y concede 3 días sin desplazamiento y 5 días con desplazamiento.',
 '2026-01-01'),
(1, 'GEN-PER-05a', N'Ausencias por fuerza mayor y permiso parental',
 N'Por motivos familiares urgentes e imprevisibles relacionados con familiares o convivientes, cuando la presencia inmediata sea indispensable, la persona trabajadora puede ausentarse hasta 4 días al año retribuidos, en días completos o en horas.',
 '2026-01-01'),
(1, 'GEN-PER-05b', N'Ausencias por fuerza mayor y permiso parental',
 N'Además, para el cuidado de hijos o menores acogidos de más de un año y hasta que cumplan 8 años se puede solicitar el permiso parental de hasta 8 semanas, continuas o discontinuas, con 10 días de preaviso.',
 '2026-01-01'),
(1, 'GEN-VAC-01a', N'Vacaciones anuales',
 N'La plantilla disfruta de 23 días laborables de vacaciones al año, que mejoran el mínimo legal de 30 días naturales. Al menos 10 días laborables seguidos deben disfrutarse entre el 15 de junio y el 15 de septiembre.',
 '2026-01-01'),
(1, 'GEN-VAC-01b', N'Vacaciones anuales',
 N'Las vacaciones se solicitan en el portal del empleado antes del 31 de marzo y se conocen como mínimo con dos meses de antelación. Los días no disfrutados pueden pasarse hasta el 31 de enero del año siguiente.',
 '2026-01-01'),
(1, 'GEN-TEL-01a', N'Política general de teletrabajo',
 N'Con carácter general se pueden teletrabajar hasta 2 días por semana, siempre que el puesto lo permita y se firme el acuerdo individual de trabajo a distancia exigido por la Ley 10/2021. El teletrabajo es voluntario y reversible.',
 '2026-01-01'),
(1, 'GEN-TEL-01b', N'Política general de teletrabajo',
 N'La empresa entrega portátil, pantalla y silla ergonómica y paga una compensación de gastos de 35 euros al mes. Los departamentos pueden tener reglas propias que sustituyen a esta.',
 '2026-01-01'),
(1, 'GEN-JOR-01a', N'Jornada, horario flexible y registro de jornada',
 N'La jornada ordinaria es de 38,5 horas semanales. La entrada es flexible entre las 7:30 y las 9:30 y el tiempo de presencia obligatoria va de 9:30 a 14:00.',
 '2026-01-01'),
(1, 'GEN-JOR-01b', N'Jornada, horario flexible y registro de jornada',
 N'Los viernes y del 1 de julio al 31 de agosto hay jornada intensiva de 7 horas. Todas las personas deben fichar el inicio y el final de la jornada en la aplicación de registro horario, como exige el artículo 34.9 del Estatuto de los Trabajadores.',
 '2026-01-01'),
(1, 'GEN-DES-01a', N'Derecho a la desconexión digital',
 N'Fuera del horario laboral, durante las vacaciones y en los permisos no hay obligación de responder correos, mensajes ni llamadas, de acuerdo con el artículo 88 de la LOPDGDD.',
 '2026-01-01'),
(1, 'GEN-DES-01b', N'Derecho a la desconexión digital',
 N'Las reuniones no pueden convocarse después de las 17:00 ni los viernes por la tarde. Las personas responsables de equipo deben programar el envío de los correos que escriban fuera de horario. Solo se excluyen los turnos de guardia regulados.',
 '2026-01-01'),
(1, 'GEN-ETI-01a', N'Canal interno de información y código ético',
 N'Cualquier persona puede comunicar infracciones normativas, fraudes o conductas contrarias al código ético a través del canal interno de información, también de forma anónima, conforme a la Ley 2/2023.',
 '2026-01-01'),
(1, 'GEN-ETI-01b', N'Canal interno de información y código ético',
 N'Queda prohibida cualquier represalia contra quien informe de buena fe. El responsable del sistema acusa recibo en un plazo máximo de 7 días y resuelve en 3 meses como máximo.',
 '2026-01-01');
GO

-- 3.2 Recursos Humanos ------------------------------------------------------
INSERT INTO dbo.Normativas (DepartamentoId, Codigo, Titulo, Contenido, FechaVigencia)
VALUES
(2, 'RRHH-SEL-01a', N'Procedimiento de selección de personal',
 N'Toda vacante se publica primero internamente durante 7 días antes de abrirla al exterior. Cada proceso necesita una terna de candidaturas como mínimo y dos entrevistas: una con RRHH y otra técnica con el área solicitante.',
 '2026-01-01'),
(2, 'RRHH-SEL-01b', N'Procedimiento de selección de personal',
 N'Está prohibido preguntar por estado civil, intención de tener hijos, religión, afiliación sindical o salud. Los currículums descartados se eliminan a los 12 meses salvo que la persona consienta conservarlos.',
 '2026-01-01'),
(2, 'RRHH-DAT-01a', N'Custodia de expedientes de personal y datos de salud',
 N'Los expedientes de personal solo los pueden consultar el equipo de RRHH y, si hace falta, la Dirección.',
 '2026-01-01'),
(2, 'RRHH-DAT-01b', N'Custodia de expedientes de personal y datos de salud',
 N'Los datos de salud (partes de baja, adaptaciones de puesto, certificados de discapacidad) son una categoría especial según el RGPD: se guardan en la carpeta cifrada de RRHH, nunca se envían por correo sin cifrar y no se comparten con los responsables de equipo, que solo reciben la fecha prevista de reincorporación.',
 '2026-01-01'),
(2, 'RRHH-DIS-01a', N'Procedimiento disciplinario',
 N'Antes de sancionar una falta grave o muy grave, RRHH abre un expediente contradictorio y da a la persona trabajadora 5 días hábiles para presentar alegaciones. Si es afiliada a un sindicato, se avisa a los delegados sindicales.',
 '2026-01-01'),
(2, 'RRHH-DIS-01b', N'Procedimiento disciplinario',
 N'La sanción se comunica por escrito, con la fecha y los hechos. Las faltas leves prescriben a los 10 días, las graves a los 20 y las muy graves a los 60 días desde que la empresa las conoce.',
 '2026-01-01'),
(2, 'RRHH-ACO-01a', N'Instrucción de denuncias de acoso laboral y sexual',
 N'Cuando RRHH recibe una denuncia de acoso, debe constituir la comisión instructora en 3 días hábiles, adoptar medidas cautelares como separar físicamente a las partes o cambiar de turno, y terminar la investigación en 30 días naturales como máximo.',
 '2026-01-01'),
(2, 'RRHH-ACO-01b', N'Instrucción de denuncias de acoso laboral y sexual',
 N'Todo el proceso es confidencial. La comisión entrevista por separado a las partes y a los testigos y emite un informe con las conclusiones y las medidas propuestas.',
 '2026-01-01'),
(2, 'RRHH-NOM-01a', N'Calendario de nóminas e incidencias',
 N'Las incidencias de nómina (horas extra, guardias, comisiones, bajas y altas) se cierran el día 20 de cada mes. La nómina se paga el penúltimo día hábil del mes.',
 '2026-01-01'),
(2, 'RRHH-NOM-01b', N'Calendario de nóminas e incidencias',
 N'Los partes de incapacidad temporal deben llegar a RRHH en 3 días como máximo desde su emisión para comunicarlos a la Seguridad Social mediante el sistema RED. Los anticipos se pueden pedir hasta el día 10 y no pueden superar el 50 % del salario neto.',
 '2026-01-01'),
(2, 'RRHH-SAL-01a', N'Bandas salariales y revisión anual (confidencial)',
 N'Las bandas salariales de 2026 son: técnico junior de 24.000 a 30.000 euros, técnico senior de 32.000 a 42.000, responsable de equipo de 45.000 a 58.000 y director de área de 65.000 a 90.000 euros brutos anuales.',
 '2026-01-01'),
(2, 'RRHH-SAL-01b', N'Bandas salariales y revisión anual (confidencial)',
 N'La revisión anual se aplica en abril, con un presupuesto del 3,5 % de la masa salarial. Todo cambio fuera de banda necesita la aprobación de la Dirección Financiera. Esta información es confidencial y no puede compartirse fuera de RRHH.',
 '2026-01-01'),
(2, 'RRHH-ONB-01a', N'Acogida de nuevas incorporaciones',
 N'RRHH envía el contrato y la documentación de bienvenida 5 días antes de la incorporación. El primer día la persona recibe el equipo informático, la formación obligatoria en prevención de riesgos laborales y protección de datos y la asignación de un compañero mentor durante 3 meses.',
 '2026-01-01'),
(2, 'RRHH-ONB-01b', N'Acogida de nuevas incorporaciones',
 N'A los 30 y a los 90 días RRHH hace una entrevista de seguimiento. El período de prueba es de 6 meses para personal técnico titulado y de 2 meses para el resto.',
 '2026-01-01');
GO

-- 3.3 Ventas ----------------------------------------------------------------
INSERT INTO dbo.Normativas (DepartamentoId, Codigo, Titulo, Contenido, FechaVigencia)
VALUES
(3, 'VEN-TRA-01a', N'Traslado de domicilio por cambio de zona comercial',
 N'Cuando la empresa asigna a una persona del equipo comercial una zona que obliga a cambiar de domicilio a otra provincia, se conceden 3 días laborables de permiso retribuido para la mudanza, en lugar del día general.',
 '2026-01-01'),
(3, 'VEN-TRA-01b', N'Traslado de domicilio por cambio de zona comercial',
 N'Además se pagan los gastos de mudanza con factura, hasta 2.500 euros, y una ayuda de alojamiento de 600 euros al mes durante los 3 primeros meses. Si la mudanza es por decisión personal se aplica la política general.',
 '2026-01-01'),
(3, 'VEN-TEL-01a', N'Trabajo en movilidad del equipo comercial',
 N'El personal comercial de campo no tiene días fijos de teletrabajo: trabaja en movilidad y visita a clientes al menos 3 días por semana. Los días sin visitas puede trabajar desde casa sin límite semanal, siempre que mantenga actualizada la agenda del CRM.',
 '2026-01-01'),
(3, 'VEN-TEL-01b', N'Trabajo en movilidad del equipo comercial',
 N'La reunión semanal del equipo es presencial los lunes a las 9:30 en la oficina de la zona. El personal de ventas interno sigue la política general de 2 días de teletrabajo.',
 '2026-01-01'),
(3, 'VEN-COM-01', N'Plan de comisiones comerciales',
 N'La retribución variable comercial es del 4 % de la facturación cobrada de clientes nuevos y del 2 % de la de clientes ya existentes. Se liquida cada trimestre, en la nómina del mes siguiente al cierre. Al superar el 120 % del objetivo anual se cobra un bono adicional de 3.000 euros. Las ventas que se cancelen o no se cobren en 90 días se descuentan de la siguiente liquidación.',
 '2026-01-01'),
(3, 'VEN-GAS-01a', N'Gastos de viaje y dietas del equipo comercial',
 N'Los desplazamientos con vehículo propio se pagan a 0,26 euros por kilómetro. La dieta completa con pernoctación es de 53,34 euros diarios en España y de 91,35 euros en el extranjero.',
 '2026-01-01'),
(3, 'VEN-GAS-01b', N'Gastos de viaje y dietas del equipo comercial',
 N'La media dieta sin pernoctación es de 26,67 euros. El hotel no puede superar 110 euros por noche, o 150 en Madrid y Barcelona. Los gastos se registran en la aplicación de gastos con foto del tique antes del día 5 del mes siguiente.',
 '2026-01-01'),
(3, 'VEN-DES-01a', N'Descuentos y condiciones comerciales autorizadas',
 N'Cada comercial puede aplicar hasta un 10 % de descuento sobre la tarifa sin aprobación. Entre el 10 % y el 20 % necesita la aprobación de la Jefatura de Ventas y por encima del 20 % la de la Dirección.',
 '2026-01-01'),
(3, 'VEN-DES-01b', N'Descuentos y condiciones comerciales autorizadas',
 N'El plazo de pago estándar es de 30 días, con un máximo legal de 60 días. Toda oferta debe registrarse en el CRM antes de enviarse al cliente y tiene una validez de 30 días.',
 '2026-01-01'),
(3, 'VEN-REG-01a', N'Regalos, invitaciones y prevención de la corrupción',
 N'El personal de ventas no puede ofrecer ni aceptar regalos o invitaciones de más de 100 euros por persona y año. Por encima de ese importe hace falta una autorización por escrito de Cumplimiento Normativo.',
 '2026-01-01'),
(3, 'VEN-REG-01b', N'Regalos, invitaciones y prevención de la corrupción',
 N'Nunca se puede ofrecer nada a empleados públicos. Todas las invitaciones a clientes se registran en el CRM con fecha, asistentes e importe. Incumplir esta norma es una falta muy grave.',
 '2026-01-01'),
(3, 'VEN-VEH-01a', N'Vehículo de empresa para comerciales',
 N'El equipo comercial de campo con más de 20.000 kilómetros al año tiene asignado un vehículo de renting con tarjeta de combustible.',
 '2026-01-01'),
(3, 'VEN-VEH-01b', N'Vehículo de empresa para comerciales',
 N'El uso personal se permite los fines de semana y en vacaciones dentro de España y tributa como retribución en especie. Las multas son responsabilidad de quien conduce. Cualquier accidente debe comunicarse a la gestora de flota en 24 horas.',
 '2026-01-01');
GO

-- 3.4 Tecnología (IT) -------------------------------------------------------
INSERT INTO dbo.Normativas (DepartamentoId, Codigo, Titulo, Contenido, FechaVigencia)
VALUES
(4, 'IT-TEL-01a', N'Teletrabajo en el departamento de Tecnología',
 N'El personal de Tecnología puede teletrabajar hasta 3 días por semana, uno más que la política general. El martes es el día presencial común del equipo.',
 '2026-01-01'),
(4, 'IT-TEL-01b', N'Teletrabajo en el departamento de Tecnología',
 N'Para teletrabajar es obligatorio usar la VPN corporativa con autenticación multifactor y no se pueden usar redes wifi públicas sin VPN. Se puede pedir un período de teletrabajo completo de hasta 4 semanas al año desde otra ciudad de España, con aprobación de la persona responsable.',
 '2026-01-01'),
(4, 'IT-GUA-01a', N'Guardias y disponibilidad fuera de horario',
 N'Las guardias de sistemas son semanales, de lunes a lunes, con un máximo de una semana de cada cuatro por persona. Cada semana de guardia se paga con 300 euros brutos.',
 '2026-01-01'),
(4, 'IT-GUA-01b', N'Guardias y disponibilidad fuera de horario',
 N'Cada intervención fuera de horario se compensa además con el doble del tiempo trabajado en tiempo libre o se paga como hora extra, a elección de la persona. El tiempo de respuesta ante una alerta crítica es de 30 minutos. Es la única excepción al derecho a la desconexión digital.',
 '2026-01-01'),
(4, 'IT-ACC-01a', N'Gestión de accesos y cuentas privilegiadas',
 N'Los accesos se conceden con el principio de mínimo privilegio y siempre mediante una solicitud aprobada en la herramienta de tickets. Las cuentas de administrador son nominativas, separadas de la cuenta de uso diario y protegidas con MFA.',
 '2026-01-01'),
(4, 'IT-ACC-01b', N'Gestión de accesos y cuentas privilegiadas',
 N'El acceso a producción se pide como elevación temporal de hasta 8 horas. Los permisos se revisan cada trimestre y las cuentas de quien deja la empresa se desactivan el mismo día de la baja.',
 '2026-01-01'),
(4, 'IT-SEG-01a', N'Gestión de incidentes de seguridad',
 N'Cualquier sospecha de incidente de seguridad (phishing, malware, pérdida de un portátil o acceso no autorizado) se comunica al equipo de seguridad en menos de 1 hora a través del canal de incidentes.',
 '2026-01-01'),
(4, 'IT-SEG-01b', N'Gestión de incidentes de seguridad',
 N'Si el incidente afecta a datos personales, el Delegado de Protección de Datos valora si hay que notificarlo a la Agencia Española de Protección de Datos, que tiene que recibirlo en 72 horas como máximo desde que se conoce.',
 '2026-01-01'),
(4, 'IT-CAM-01a', N'Cambios en entornos de producción',
 N'Todo cambio en producción necesita una petición de cambio aprobada por el comité de cambios, que se reúne los martes y jueves, con plan de marcha atrás y pruebas en preproducción.',
 '2026-01-01'),
(4, 'IT-CAM-01b', N'Cambios en entornos de producción',
 N'No se despliega los viernes a partir de las 13:00 ni en vísperas de festivo, salvo cambios de emergencia aprobados por la persona responsable de guardia. Todo el código pasa por una revisión de un compañero (pull request) antes de fusionarse en la rama principal.',
 '2026-01-01'),
(4, 'IT-IA-01a', N'Uso de herramientas de IA generativa',
 N'Solo se pueden usar las herramientas de IA generativa aprobadas por la empresa con licencia corporativa, como GitHub Copilot Business.',
 '2026-01-01'),
(4, 'IT-IA-01b', N'Uso de herramientas de IA generativa',
 N'Está prohibido pegar en herramientas públicas código fuente propiedad de la empresa, credenciales, datos personales de clientes o empleados o información confidencial. El código generado con IA se revisa igual que cualquier otro código y la persona que lo integra es responsable de él.',
 '2026-01-01'),
(4, 'IT-EQU-01a', N'Equipos portátiles y cifrado',
 N'Todos los portátiles corporativos tienen el disco cifrado con BitLocker, bloqueo automático a los 5 minutos y antivirus gestionado. No se puede instalar software sin licencia ni desactivar las actualizaciones automáticas.',
 '2026-01-01'),
(4, 'IT-EQU-01b', N'Equipos portátiles y cifrado',
 N'Los equipos se renuevan cada 4 años. Si se pierden o los roban, hay que avisar en 1 hora al equipo de seguridad para hacer el borrado remoto y presentar la denuncia en 48 horas.',
 '2026-01-01');
GO

-- 3.5 Dirección (confidencial) ----------------------------------------------
INSERT INTO dbo.Normativas (DepartamentoId, Codigo, Titulo, Contenido, FechaVigencia)
VALUES
(5, 'DIR-RET-01a', N'Retribución variable de directivos (confidencial)',
 N'Las personas directivas tienen una retribución variable de hasta el 25 % del salario fijo, ligada en un 60 % a los objetivos de EBITDA de la compañía y en un 40 % a objetivos individuales.',
 '2026-01-01'),
(5, 'DIR-RET-01b', N'Retribución variable de directivos (confidencial)',
 N'Se liquida en marzo, cuando se aprueban las cuentas anuales. Hay una cláusula de devolución (clawback) durante 2 años si los resultados que sirvieron de base se reformulan. La comisión de retribuciones la revisa cada año.',
 '2026-01-01'),
(5, 'DIR-GAS-01a', N'Niveles de aprobación de gastos e inversiones',
 N'Las personas responsables de departamento aprueban gastos de hasta 10.000 euros. Entre 10.000 y 50.000 euros los aprueba la Dirección Financiera.',
 '2026-01-01'),
(5, 'DIR-GAS-01b', N'Niveles de aprobación de gastos e inversiones',
 N'Las inversiones de más de 50.000 euros y los contratos de más de 2 años necesitan acuerdo del Comité de Dirección, y por encima de 500.000 euros la aprobación del Consejo de Administración. Está prohibido dividir un gasto para no superar un límite de aprobación.',
 '2026-01-01'),
(5, 'DIR-RES-01a', N'Información privilegiada y comunicación de resultados',
 N'Los resultados trimestrales y las operaciones corporativas en estudio (fusiones, adquisiciones o ventas de unidades de negocio) son información privilegiada hasta que se anuncian.',
 '2026-01-01'),
(5, 'DIR-RES-01b', N'Información privilegiada y comunicación de resultados',
 N'Solo el Comité de Dirección y las personas incluidas en la lista de iniciados pueden conocerlos. Está prohibido compartirlos con el resto de la plantilla, con familiares o en redes sociales. Toda comunicación externa la coordina la Dirección General.',
 '2026-01-01'),
(5, 'DIR-REE-01a', N'Procedimiento de reestructuración y despidos colectivos',
 N'Cualquier plan de reestructuración que afecte a puestos de trabajo debe aprobarlo el Comité de Dirección antes de comunicarse.',
 '2026-01-01'),
(5, 'DIR-REE-01b', N'Procedimiento de reestructuración y despidos colectivos',
 N'Si se superan los umbrales del despido colectivo del artículo 51 del Estatuto de los Trabajadores, se abre un período de consultas de 30 días como máximo con la representación legal de la plantilla y se notifica a la autoridad laboral. RRHH y Asesoría Jurídica preparan la memoria explicativa antes de la apertura.',
 '2026-01-01'),
(5, 'DIR-CON-01a', N'Conflictos de interés de la alta dirección',
 N'Cada año, las personas directivas declaran por escrito sus participaciones en otras sociedades, sus cargos externos y sus relaciones familiares con proveedores o clientes.',
 '2026-01-01'),
(5, 'DIR-CON-01b', N'Conflictos de interés de la alta dirección',
 N'Quien tenga un conflicto de interés debe abstenerse de participar en la decisión afectada y comunicarlo al Comité de Auditoría. Las operaciones con partes vinculadas de más de 30.000 euros necesitan la aprobación del Consejo.',
 '2026-01-01'),
(5, 'DIR-TEL-01a', N'Disponibilidad y teletrabajo de la Dirección',
 N'El Comité de Dirección trabaja de forma presencial de lunes a jueves y puede teletrabajar los viernes.',
 '2026-01-01'),
(5, 'DIR-TEL-01b', N'Disponibilidad y teletrabajo de la Dirección',
 N'Las personas directivas deben estar localizables para asuntos críticos también fuera de horario, a cambio de un complemento de disponibilidad incluido en su salario fijo. En vacaciones se nombra un sustituto con poderes de aprobación para todo el período de ausencia.',
 '2026-01-01');
GO

-- Reactivar la política si existía
IF EXISTS (SELECT 1 FROM sys.security_policies WHERE name = N'PoliticaNormativas')
    EXEC (N'ALTER SECURITY POLICY Seguridad.PoliticaNormativas WITH (STATE = ON);');
GO

-- Resumen de la carga
SELECT d.Nombre AS Departamento, COUNT(n.NormativaId) AS Fragmentos
FROM dbo.Departamentos AS d
LEFT JOIN dbo.Normativas AS n ON n.DepartamentoId = d.DepartamentoId
GROUP BY d.DepartamentoId, d.Nombre
ORDER BY d.DepartamentoId;

SELECT COUNT(*) AS Empleados FROM dbo.Empleados;
GO

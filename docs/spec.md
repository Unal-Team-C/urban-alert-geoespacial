# Especificación: Servicio Geoespacial

- **ID**: 001-servicio-geoespacial
- **Estado**: implementada
- **Creada**: 2026-10-01
- **Entrada original**: fuentes/Contratos UrbanAlert.docx (sección Geoespacial; tipos de daño, estados, niveles de emergencia, validación de coordenadas), fuentes/delivery1-team-C.docx (RF01, RF08, RF09), fuentes/delivery3-team-C-revisión.docx (QAS-05, ADR-03/04/05) + indicaciones del usuario: "contrato en inglés; consulta de reportes cercanos a un punto a una distancia x con parámetros de consulta y filtro opcional por tipo; Geoespacial NO emite evento de duplicados; despliegue en Docker local para pruebas; sin distinción por localidades; de momento solo la base de datos con PostGIS y el microservicio, sin mecanismos de cola de mensajes; la asignación llega por REST como llamado síncrono dentro del flujo de creación de reporte, con el contrato acordado; Geoespacial usa únicamente la información del contrato (identificador de reporte y coordenada); la distancia máxima de consulta es el semieje mayor de Bogotá (luego cambiada por el usuario a 6 km)".

## 1. Resumen

El Servicio Geoespacial es el dueño de la ubicación de los reportes de daño urbano de UrbanAlert. Durante la creación de un reporte, el servicio de Reportes le pide de forma síncrona registrar la coordenada, y Geoespacial devuelve un identificador de coordenada. Además responde qué reportes hay cerca de un punto del mapa dentro de una distancia dada. Solo conoce la información del contrato: identificador de reporte y coordenada. Esta versión incluye solo el microservicio y su base de datos espacial, desplegados en contenedores locales para pruebas; la mensajería entre servicios queda para una fase posterior.

## 2. Problema y contexto

- El mapa debe mostrar solo los reportes de la zona que el usuario está mirando, para responder rápido y sin transferir datos innecesarios. _(fuente: delivery1 RF08)_
- El filtrado por tipo de daño (delivery1 RF09) no se resuelve en Geoespacial, que no conoce el tipo de daño (ver §8).
- El servicio de Reportes no guarda la ubicación en bruto: guarda un identificador de coordenada que obtiene de Geoespacial durante la creación del reporte. _(fuente: Contratos, Reportes POST "IdCoordenada (Post a geoespacial)"; indicación del usuario)_
- Una ráfaga de consultas al mapa no debe degradar la creación de reportes en el núcleo. Por eso Geoespacial es una unidad aislada, con almacenamiento y recursos propios. _(fuente: delivery3 QAS-05, ADR-03/05)_

## 3. Usuarios y actores

- **Ciudadano / funcionario (usuario del mapa)**: obtener los reportes cercanos al punto que mira y crear un reporte seleccionando un punto en el mapa (la creación la gestiona el servicio de Reportes).
- **Servicio de Reportes**: dentro del flujo de creación de un reporte, registrar su coordenada y obtener el identificador de forma inmediata.
- **Clientes que necesitan lat/lon de un reporte** (p. ej. Reportes al listar): resolver una coordenada a partir de su identificador.
- **Equipo de desarrollo**: levantar el servicio y su base de datos en local para pruebas.

## 4. Historias de usuario

### HU-1: Asignar localización durante la creación de un reporte (Prioridad: P1)

Como servicio de Reportes quiero registrar de forma síncrona la coordenada de un reporte que estoy creando, para guardar en él el identificador de coordenada antes de confirmar la creación al ciudadano.

**Criterios de aceptación**
1. Dado un identificador de reporte y una coordenada dentro del rango de Bogotá, cuando se solicita asignar la localización, entonces se responde de inmediato con un identificador de coordenada nuevo, el identificador del reporte y la coordenada.
2. Dada una coordenada fuera del rango de Bogotá o mal formada, cuando se solicita asignarla, entonces se rechaza como parámetro inválido y no se registra nada.
3. Dada una solicitud ya atendida para el mismo reporte (p. ej. un reintento), cuando llega de nuevo, entonces se responde con el mismo identificador de coordenada y no se crea un registro nuevo.

### HU-2: Consultar reportes cercanos a un punto (Prioridad: P1)

Como usuario del mapa quiero obtener los reportes a una distancia dada de un punto para ver solo los daños de la zona que estoy mirando.

**Criterios de aceptación**
1. Dados un reporte a 300 m y otro a 800 m de un punto, cuando se consultan los reportes a 500 m de ese punto, entonces solo se devuelve el de 300 m.
2. Dado un reporte exactamente a 500 m de un punto, cuando se consulta con distancia 500 m, entonces se incluye en la respuesta.
3. Dado un punto sin reportes dentro de la distancia indicada, cuando se consulta, entonces la respuesta es exitosa y contiene una colección vacía.
4. Dado que el usuario hace zoom o desplaza el mapa, cuando se consulta con un punto o una distancia diferentes, entonces se devuelven únicamente los reportes dentro de la nueva distancia desde el nuevo punto.
5. Cada reporte devuelto incluye solo su identificador de reporte, su identificador de coordenada y su coordenada. El tipo, estado y nivel de emergencia los obtiene el cliente de otro servicio.
6. Dada una distancia de 6000 m, cuando se consulta, entonces se acepta; dada una distancia de 6001 m, entonces se rechaza como parámetro inválido.

### HU-3: Filtrar por tipo de daño — FUERA DE ALCANCE

Geoespacial solo conoce identificador de reporte y coordenada, así que no filtra por tipo de daño. Ver §8.

### HU-4: Mantener el mapa al día por eventos — DIFERIDA

Diferida a la fase de mensajería: el consumo del anuncio de reporte creado (y de cambios de estado) requiere la cola de mensajes, que no se implementa en esta versión. Ver §8.

### HU-5: Resolver una coordenada por su identificador (Prioridad: P2)

Como cliente que tiene el identificador de coordenada de un reporte quiero obtener su latitud y longitud para mostrar o devolver la ubicación.

**Criterios de aceptación**
1. Dado un identificador de coordenada existente, cuando se consulta, entonces se devuelven el identificador del reporte, la latitud y la longitud.
2. Dado un identificador inexistente, cuando se consulta, entonces se responde "no encontrado".

### HU-6: Entorno local de pruebas (Prioridad: P1)

Como integrante del equipo quiero levantar el servicio y su base de datos con un único comando en local para probarlo sin infraestructura en la nube.

**Criterios de aceptación**
1. Dado un equipo con el motor de contenedores instalado, cuando se ejecuta el comando de arranque, entonces el servicio y su base de datos espacial quedan disponibles y el servicio reporta estado saludable.
2. Dado el entorno recién levantado, cuando se consulta un punto de Bogotá cubierto por los datos de prueba, entonces se devuelven reportes sin depender del servicio de Reportes.

### Casos borde

- Latitud o longitud no numéricas, ausentes o fuera del rango de Bogotá (al asignar o al consultar) → rechazo por parámetro inválido.
- Distancia ausente, cero, negativa o mayor que 6 km (6000 m) → rechazo por parámetro inválido.
- Punto cerca del borde del rango de Bogotá con una distancia que se sale del rango → se devuelven solo los reportes existentes, sin error.
- Solicitud de asignación repetida para el mismo reporte con una coordenada distinta → pendiente, se resuelve en `/sdd-clarify` (supuesto actual: se rechaza como conflicto y se conserva la original).
- Base de datos no disponible → la asignación y la consulta fallan con un error de servicio no disponible, sin respuestas parciales, y el indicador de salud lo refleja.
- Parámetros con contenido malicioso (p. ej. intento de inyección) → rechazo sin llegar al almacenamiento. _(fuente: delivery3 QAS-01.2)_

## 5. Requisitos funcionales

- **RF-001**: El sistema DEBE atender de forma síncrona la solicitud de asignación de localización (identificador de reporte + coordenada), asignar un identificador de coordenada único y responder en la misma petición con identificador de coordenada, identificador de reporte y coordenada. _(fuente: Contratos, Geoespacial › AsignarLocalizacion / LocalizacionAsignada; indicación del usuario: llamado síncrono por REST)_
- **RF-002**: El sistema DEBE rechazar toda coordenada fuera del rango geográfico de Bogotá, tanto al asignar como al consultar. _(fuente: Contratos, "Validación de coordenadas: rango de bogotá")_
- **RF-003**: El sistema DEBE ser idempotente ante solicitudes de asignación repetidas para el mismo reporte: devuelve el mismo identificador de coordenada y no crea registros duplicados. _(fuente: reintentos del flujo de creación; supuesto S-3)_
- **RF-004**: El sistema DEBE devolver los reportes cuya ubicación está a una distancia menor o igual a la indicada (en metros) desde un punto dado. _(fuente: Contratos, Geoespacial › GET (lat,lon)/(rango)/reportes; delivery1 RF08; indicación del usuario)_
- **RF-005**: Una consulta sin resultados DEBE responder con éxito y colección vacía. _(fuente: delivery1 RF08 "Área sin reportes")_
- **RF-006**: _Fuera de alcance_ — filtrar por tipo de daño. Geoespacial no conoce el tipo de daño (decisión del usuario: solo información del contrato). _(fuente: delivery1 RF09)_
- **RF-007**: Cada reporte devuelto DEBE incluir únicamente identificador de reporte, identificador de coordenada y coordenada (latitud, longitud). _(fuente: Contratos, LocalizacionAsignada; decisión del usuario)_
- **RF-008**: _Diferido_ — incorporar reportes a partir del anuncio de creación del servicio de Reportes. Requiere la cola de mensajes (§8). _(fuente: Contratos, evento reporteCreado)_
- **RF-009**: El sistema DEBE permitir obtener latitud, longitud e identificador de reporte a partir de un identificador de coordenada. _(fuente: indicación del usuario, sugerido para resolver coordenadas en el listado de Reportes)_
- **RF-010**: El sistema DEBE rechazar como parámetro inválido toda entrada que no cumpla el formato esperado, antes de acceder al almacenamiento. _(fuente: delivery3 QAS-01.2)_
- **RF-011**: El sistema DEBE rechazar las consultas cuya distancia supere 6 km (6000 m). _(fuente: delivery3 QAS-05 "acotar las búsquedas al marco cartográfico"; decisión del usuario)_
- **RF-012**: El sistema DEBE ofrecer a los clientes del mapa solo operaciones de consulta; la única operación de escritura es la asignación de localización, invocada por el servicio de Reportes. Cuando un reporte se crea seleccionando un punto en el mapa, el cliente envía la coordenada al servicio de Reportes y este la registra en Geoespacial; el cliente del mapa no escribe directamente en Geoespacial. _(fuente: delivery3 tabla de persistencia "Acceso de sólo lectura, sin escritura directa desde clientes externos"; delivery1 RF02 "crear un reporte señalando su ubicación sobre el mapa"; decisión del usuario)_

## 6. Requisitos no funcionales

- **RNF-001**: El percentil 95 del tiempo de respuesta de la consulta de reportes cercanos es menor a 200 ms con los datos de prueba. _(fuente: delivery3 QAS-05)_
- **RNF-002**: Geoespacial usa una base de datos y recursos propios, con un máximo de 50 conexiones concurrentes a su base de datos, separada de la base del núcleo. _(fuente: delivery3 QAS-05, ADR-03, ADR-05)_
- **RNF-003**: Ninguna consulta al almacenamiento se construye concatenando datos de entrada (0 casos). _(fuente: delivery3 QAS-01.2)_
- **RNF-004**: El servicio no guarda estado de sesión entre peticiones, de modo que cualquier instancia puede atender cualquier petición. _(fuente: delivery3 ADR-04)_
- **RNF-005**: El entorno local (servicio y base de datos espacial, con datos de prueba) se levanta con un único comando. La configuración se toma de variables de entorno y el repositorio no contiene secretos. _(fuente: indicación del usuario)_
- **RNF-006**: El servicio expone un indicador de salud consultable por el entorno de contenedores, que refleja la disponibilidad de su base de datos. _(fuente: delivery3 "Failure Detection / Health Checks")_
- **RNF-007**: Los nombres de campos, operaciones y valores del contrato están en inglés. _(fuente: Contratos "Ajustar Inglés"; indicación del usuario)_

## 7. Entidades clave

- **Coordenada**: punto geográfico asignado a un reporte. Atributos: identificador de coordenada, identificador de reporte, latitud, longitud.
- **Rango de Bogotá**: zona geográfica válida para coordenadas.

Tipo de daño, estado y nivel de emergencia NO son datos de Geoespacial: pertenecen al servicio de Reportes.

## 8. Fuera de alcance

- **Cola de mensajes y eventos** en esta versión: no se publican ni consumen mensajes (ni solicitud/respuesta de asignación por eventos, ni anuncio de reporte creado, ni cambios de estado). HU-4 y RF-008 quedan diferidos. _(indicación del usuario)_
- Detección y emisión de eventos de posibles duplicados (RF10 de delivery1). Geoespacial no emite ese evento; la consulta de cercanía (RF-004) puede usarse por quien la necesite. _(indicación del usuario)_
- Distinción o filtrado por localidades. _(indicación del usuario)_
- Filtrado por tipo de daño (delivery1 RF09) y datos de tipo, estado o nivel de emergencia en las respuestas: Geoespacial solo maneja la información del contrato. El filtro y los datos para ícono/color (delivery1 RF01) se resuelven fuera de este servicio. _(decisión del usuario)_
- Autenticación, autorización por rol y API Gateway. En local, el servicio se prueba sin token.
- Caché distribuida y CDN (ADR-04), particionamiento por cuadrante (QAS-05) y despliegue en la nube con autoescalado (ADR-03).
- Consulta por recuadro (bounding box) del área visible. Se sustituye por punto + distancia por decisión del usuario.

## 9. Supuestos

- **S-1**: El área visible del mapa (RF08) se aproxima con un círculo: el centro del mapa como punto y una distancia que cubre la vista. El cliente calcula la distancia.
- **S-2**: La distancia se expresa en metros y el límite es inclusivo (≤).
- **S-3**: El servicio de Reportes puede reintentar la solicitud de asignación ante errores de red, así que pueden llegar solicitudes repetidas.
- **S-4**: El rango de Bogotá es un recuadro fijo de latitud/longitud que cubre el Distrito Capital. Su valor exacto se fija en el plan.
- **S-5**: Los datos de prueba incluyen reportes repartidos en varios puntos de Bogotá a distancias conocidas entre sí.
- **S-6**: No hay tope de cantidad de reportes por respuesta; la distancia máxima acota el volumen. Se revisa si la RNF-001 no se cumple.
- **S-7**: Mientras no exista la cola de mensajes, los reportes conocidos por Geoespacial son los asignados por el flujo de creación y los de los datos de prueba.

## 10. Métricas de éxito

- **MS-001**: El 100 % de los criterios de aceptación de HU-1, HU-2, HU-5 y HU-6 se cumplen en el entorno local.
- **MS-002**: p95 < 200 ms en la consulta de reportes cercanos, con los datos de prueba y carga 5x nominal.
- **MS-003**: 0 registros duplicados tras repetir dos veces cada solicitud de asignación de una prueba.

## 11. Clarificaciones

### Sesión 2026-10-01
- P: ¿La asignación de localización es una petición síncrona o un intercambio de mensajes? → R: Síncrona por REST, como parte del flujo de creación de reporte, usando el contrato acordado (AssignLocation → LocationAssigned). Sin cola de mensajes en esta versión.
- P: ¿Qué hacer con un anuncio de reporte creado sin coordenada previa? → R: Ya no aplica: no se consumen eventos en esta versión.
- P: ¿Distinción por localidades? → R: No; los criterios se expresan solo con punto y distancia.

- P: ¿Cómo conoce Geoespacial el tipo de daño, el estado y el nivel de emergencia? → R: No los necesita; se usa únicamente la información del contrato (identificador de reporte y coordenada). El filtro por tipo queda fuera de alcance.
- P: ¿Cuál es la distancia máxima por consulta? → R: Inicialmente el semieje mayor de Bogotá; reconsiderado: 6 km (6000 m). Con ese radio, el círculo cubre la vista completa hasta el zoom 15 en escritorio y el zoom 14 en móvil (escala de teselas de 256 px); con más alejamiento, el cliente debe acotar la consulta.

- P: Si desde el mapa se puede crear un reporte seleccionando un punto, ¿quién registra la coordenada en Geoespacial? → R: El servicio de Reportes, con el mismo llamado síncrono de HU-1; el mapa solo envía lat/lon a Reportes.

### Pendientes

- Ninguno bloqueante.
- Supuesto a validar: solicitud de asignación repetida para el mismo reporte con coordenada distinta → rechazo por conflicto, se conserva la original.

---

### Checklist de calidad (autorrevisión antes de entregar)

- [x] Sin detalles de implementación (lenguajes, frameworks, APIs, estructura de código)
- [x] Cada requisito es testeable y no ambiguo
- [x] Criterios de aceptación con resultado observable
- [x] Casos borde identificados
- [x] Alcance acotado (fuera de alcance explícito)
- [x] Como máximo 3 `[NEEDS CLARIFICATION]` pendientes
- [x] Coherente con `.sdd/constitution.md` (constitución sin rellenar: no hay principios contra los que validar)

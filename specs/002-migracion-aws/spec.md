# Especificación: Migración del Servicio Geoespacial a AWS

- **ID**: 002-migracion-aws
- **Estado**: aprobada <!-- borrador | aclarada | aprobada | implementada -->
- **Creada**: 2026-10-10
- **Entrada original**: "Migración del servicio geoespacial a AWS (rama aws-provisioning): adaptar el código para la nube y crear CI/CD con GitHub Actions usando Terraform como base. Un flujo se ejecuta al hacer commit a main, que es el de aprovisionamiento. El otro flujo se ejecuta manualmente." + alcance acordado en la conversación: configuración para la nube (cadena de conexión desde el almacén de secretos, conexión cifrada, valores de producción, logs para CloudWatch), imagen apta para ECS Express Mode, solo el esquema en RDS PostgreSQL 17 + PostGIS (sin datos semilla ni base de pruebas), infraestructura como código con estado remoto, documentación de despliegue y de variables/secretos. **Revisión v2 (2026-10-11)**: "el API Gateway es el que debe exponer el servicio" → Amazon API Gateway compartido de la plataforma `Unal-Team-C/urban-alert-plataforma`, accesible solo a través de él.

## 1. Resumen

Llevar el Servicio Geoespacial, que hoy solo se ejecuta en contenedores locales, a un entorno gestionado en AWS: base de datos espacial gestionada y servicio de contenedores con escalado automático, desplegados en la red privada compartida de UrbanAlert y publicados **solo** a través del API Gateway compartido, con toda la infraestructura descrita como código. El aprovisionamiento y el despliegue se automatizan con dos flujos de GitHub Actions: uno de aprovisionamiento que se ejecuta en cada commit a `main` y otro de desaprovisionamiento que se lanza manualmente. El contrato de la API no cambia.

## 2. Problema y contexto

- El servicio solo se puede usar en la máquina de cada integrante (`docker-compose`), así que los demás servicios de UrbanAlert y el frontend no tienen una instancia compartida a la que llamar.
- Crear la infraestructura a mano en la consola no es repetible ni revisable: no queda registro de qué se cambió, ni se puede reconstruir el entorno si se borra.
- La configuración actual está pensada para local: credenciales de ejemplo por defecto, pool de 50 conexiones por proceso (rompe el presupuesto total de 50 conexiones al escalar, ver decisión D-013 de `docs/plan.md`) y conexión sin cifrar.
- La plataforma compartida (`Unal-Team-C/urban-alert-plataforma`, ya aprovisionada) ofrece la red privada (VPC con subredes privadas y salida a internet por NAT) y el API Gateway por el que se exponen todos los microservicios. Publica su contrato en SSM Parameter Store (`/urban-alert/plataforma/`) y una guía de integración (`docs/integracion.md` de ese repo).
- Ya existen en la cuenta de AWS (348364742283, us-east-2), creados a mano: el proveedor OIDC de GitHub y el rol que asumen los workflows (política `github-actions-urban-alertPolicy`, válido para todos los repos de `Unal-Team-C`), los roles `urban-alert-ecs-execution-role` y `urban-alert-ecs-infrastructure-role`, y el repositorio de imágenes `urban-alert-geoespacial` (tags inmutables).

## 3. Usuarios y actores

- **Equipo de desarrollo**: publicar cambios del servicio y de la infraestructura con un commit a `main`, sin pasos manuales en la consola, y poder eliminar el entorno a mano cuando no se usa.
- **Frontend (consumidor público)**: consultar los reportes cercanos y resolver coordenadas a través de la URL del API Gateway.
- **Servicio de Reportes (consumidor interno)**: asignar localizaciones a través del API Gateway con una petición firmada con su identidad de AWS; ningún cliente anónimo puede asignarlas.
- **Revisor / docente**: entender desde el repositorio qué infraestructura existe, cómo se despliega y qué variables y secretos hacen falta.

## 4. Historias de usuario

### HU-1: Aprovisionar y desplegar con un commit a `main` (Prioridad: P1)

Como integrante del equipo quiero que un commit a `main` aprovisione la infraestructura y deje desplegada la versión del servicio de ese commit, para no depender de pasos manuales.

**Criterios de aceptación**
1. Dado un commit a `main` con cambios en el código del servicio, cuando termina el flujo de aprovisionamiento, entonces el servicio responde con la versión de ese commit a través de la URL del API Gateway y su comprobación de salud interna es saludable.
2. Dado un commit a `main` que hace fallar las pruebas, cuando se ejecuta el flujo, entonces no se modifica la infraestructura ni se despliega nada, y el flujo queda en rojo.
3. Dado un commit a `main` sin cambios de infraestructura, cuando se ejecuta el flujo, entonces el aprovisionamiento informa de que no hay cambios en la infraestructura.
4. Dados dos commits seguidos a `main`, cuando sus flujos coinciden en el tiempo, entonces se ejecutan uno detrás de otro, nunca a la vez sobre la misma infraestructura.

### HU-2: Desaprovisionar el entorno a mano (Prioridad: P1)

Como integrante del equipo quiero lanzar a mano un flujo que elimine el entorno de la nube, para no generar costes cuando no se usa y poder recrearlo después con un commit a `main`.

**Criterios de aceptación**
1. Dado el repositorio en GitHub, cuando un integrante lanza el flujo de desaprovisionamiento y confirma la operación, entonces se eliminan los recursos del servicio gestionados como código y el resultado queda registrado en la ejecución del flujo.
2. Dado que se lanza el flujo sin la confirmación explícita, cuando se ejecuta, entonces no elimina nada y termina indicando que falta la confirmación.
3. Dada la base de datos con datos, cuando se desaprovisiona, entonces antes de eliminarla queda una copia final de la que se puede restaurar.
4. Dado el entorno desaprovisionado, cuando se hace un nuevo commit a `main`, entonces el flujo de aprovisionamiento recrea el entorno completo y el servicio vuelve a estar saludable.
5. Dado el entorno desaprovisionado, cuando se vuelve a lanzar el flujo de aprovisionamiento o de desaprovisionamiento, entonces los flujos siguen pudiendo autenticarse en AWS (los recursos de arranque no se eliminan).
6. El flujo nunca se ejecuta por un commit; solo bajo demanda.

### HU-3: Base de datos gestionada con el esquema del servicio (Prioridad: P1)

Como equipo queremos una base PostgreSQL con PostGIS gestionada en la nube, con solo el esquema del servicio, para no administrar servidores ni mezclar datos de prueba con datos reales.

**Criterios de aceptación**
1. Dado el entorno recién aprovisionado, cuando se consulta la base, entonces existe la extensión espacial, la tabla de coordenadas con su índice espacial y ningún dato.
2. Dado el entorno aprovisionado, cuando se intenta conectar a la base desde internet, entonces la conexión no es posible; solo las tareas del servicio llegan a ella.
3. Dado el servicio desplegado, cuando se conecta a la base, entonces la conexión va cifrada y usa un usuario que solo puede leer e insertar coordenadas.

### HU-4: Servicio apto para la nube (Prioridad: P1)

Como equipo queremos que el servicio se configure, registre su actividad y se apague como espera la plataforma de contenedores, para operar y diagnosticar en la nube.

**Criterios de aceptación**
1. Dado el servicio desplegado, cuando recibe peticiones, entonces cada petición y cada error quedan en los logs del servicio en la consola de AWS, una entrada por evento, con nivel y marca de tiempo.
2. Dado que la plataforma detiene una tarea (escalado hacia abajo o nuevo despliegue), cuando la tarea recibe la señal de parada, entonces termina las peticiones en curso y cierra sus conexiones a la base antes de salir.
3. Dado un nuevo despliegue, cuando se reemplazan las tareas, entonces el servicio sigue respondiendo durante el cambio.

### HU-5: Entender y reproducir el despliegue (Prioridad: P2)

Como revisor o nuevo integrante quiero encontrar en el repositorio cómo se despliega el servicio y qué hay que configurar, para reproducir el entorno desde cero.

**Criterios de aceptación**
1. Dada una cuenta de AWS con solo los recursos de arranque, cuando se siguen los pasos documentados y se hace un commit a `main`, entonces se obtiene el entorno completo funcionando.
2. Dado el README, cuando se busca la lista de variables y secretos de GitHub, entonces cada uno aparece con su propósito y un valor de ejemplo (sin valores secretos reales).

### HU-6: Exponer el servicio solo a través del API Gateway compartido (Prioridad: P1)

Como equipo queremos que el servicio sea accesible únicamente por el API Gateway de la plataforma, para tener un punto de entrada común a todos los microservicios y no exponer el servicio directamente a internet.

**Criterios de aceptación**
1. Dado el servicio desplegado, cuando un cliente llama a `GET <gateway>/api/v1/geoespacial/reports?lat=…&lon=…&radius=…`, entonces recibe la misma respuesta que daría `GET /api/v1/geospatial/reports` del servicio.
2. Dado el servicio desplegado, cuando un cliente llama a `GET <gateway>/api/v1/geoespacial/coordinates/{id}`, entonces recibe la coordenada (o 404) como en local.
3. Dado un cliente sin firma de AWS (o con una identidad sin permiso), cuando llama a `POST <gateway>/api/v1/geoespacial/coordinates`, entonces el gateway responde 403 y la petición no llega al servicio.
4. Dada una petición firmada por una identidad con permiso de invocación, cuando llama a `POST <gateway>/api/v1/geoespacial/coordinates`, entonces el servicio asigna la localización como en local (201/200/409/400).
5. Dado el servicio desplegado, cuando se intenta llegar a él desde internet sin pasar por el gateway, entonces no es posible: no tiene URL pública propia ni sus tareas tienen IP pública.
6. Dada una ruta del gateway fuera de las registradas por el servicio (p. ej. `DELETE /api/v1/geoespacial/coordinates/{id}` o `/health`), cuando se llama, entonces el gateway responde 404.

### Casos borde

- El flujo de aprovisionamiento falla a mitad (p. ej. error de permisos o de cuota) → el siguiente commit a `main` retoma desde el estado registrado sin duplicar recursos.
- Alguien cambia a mano en la consola un recurso gestionado como código → el siguiente aprovisionamiento muestra la diferencia y la devuelve a lo definido en el repositorio.
- Primer despliegue: la base aún no existe o tarda varios minutos en estar disponible → el servicio no se da por desplegado hasta que `/health` responde saludable.
- La base de datos no está disponible tras el despliegue → `/health` devuelve no disponible y la plataforma no envía tráfico a esas tareas.
- El escalado llega al máximo de tareas → el total de conexiones a la base no supera 50.
- Se intenta borrar la base desde el código por error en el flujo de aprovisionamiento → la base tiene protección contra borrado y el aprovisionamiento falla en lugar de borrarla.
- Se lanza el desaprovisionamiento con el entorno ya eliminado → termina sin error indicando que no hay nada que eliminar.
- Se lanza el desaprovisionamiento mientras corre un aprovisionamiento → espera a que termine (RF-015).
- El registro de imágenes tiene imágenes al desaprovisionar → se eliminan junto con el registro.
- Un recurso del inventario ya no existe en AWS al importarlo → la importación falla indicando qué recurso falta, sin crear uno nuevo a ciegas.
- El flujo de aprovisionamiento se lanza desde una rama distinta de `main` o desde un fork → no obtiene credenciales de AWS.
- La plataforma compartida no está aprovisionada → el aprovisionamiento falla antes de cambiar nada, indicando que falta la plataforma.
- Otra feature ya registró una ruta con la misma clave en el gateway → el aprovisionamiento falla con conflicto y la ruta existente no cambia.
- Se desaprovisiona el servicio → sus rutas desaparecen del gateway (responden 404) y la plataforma no se toca.

## 5. Requisitos funcionales

- **RF-001**: El servicio DEBE leer toda su configuración del entorno de ejecución; la cadena de conexión a la base en la nube DEBE venir del almacén de secretos de AWS y no aparecer en el repositorio, en la imagen ni en los logs de los flujos.
- **RF-002**: En la nube, la conexión del servicio a la base DEBE ir cifrada; si no se puede establecer cifrada, el servicio DEBE fallar en lugar de conectarse sin cifrar.
- **RF-003**: El tamaño del pool de conexiones en la nube DEBE cumplir `conexiones por tarea × tareas máximas ≤ 50` (presupuesto total de la decisión D-013).
- **RF-004**: El servicio DEBE escribir sus logs en la salida estándar, una entrada por línea en formato estructurado (con nivel, marca de tiempo y mensaje), incluyendo una entrada por petición con método, ruta, código de respuesta y duración.
- **RF-005**: Al recibir la señal de parada, el servicio DEBE dejar de aceptar peticiones nuevas, terminar las que están en curso y cerrar el pool de conexiones antes de salir, dentro del margen de parada de la plataforma.
- **RF-006**: La imagen del servicio DEBE escuchar en el puerto 8000, exponer `/health` como comprobación de salud, ejecutarse sin privilegios de administrador y estar construida para la arquitectura de la plataforma de contenedores elegida.
- **RF-007**: Cada imagen publicada DEBE etiquetarse con el identificador del commit del que se construyó, de forma que la versión desplegada se pueda rastrear hasta su commit.
- **RF-008**: El esquema de la base en la nube DEBE salir únicamente de `db/schema.sql`, aplicarse de forma que repetirlo no cause errores ni cambios, y no incluir datos semilla ni la base de pruebas.
- **RF-009**: El servicio DEBE conectarse a la base con un usuario propio con permisos solo de lectura e inserción sobre la tabla de coordenadas, distinto del usuario administrador.
- **RF-010**: Toda la infraestructura del servicio en la nube DEBE estar definida como código en el repositorio: base de datos PostgreSQL 17 con PostGIS, reglas de red de acceso a la base, secreto de conexión, registro de imágenes, roles de ejecución e infraestructura del servicio, servicio de contenedores con escalado automático, comprobación de salud y logs.
- **RF-010b**: Los recursos que ya se crearon a mano (registro de imágenes `urban-alert-geoespacial`, roles `urban-alert-ecs-execution-role` y `urban-alert-ecs-infrastructure-role`, y la base de datos, grupos de seguridad y secreto si ya existen) DEBEN importarse al código sin recrearlos ni perder datos. La lista de recursos importados, con su identificador en AWS, DEBE quedar en el repositorio como un inventario legible (pseudoinventario) que también sirva para importarlos de nuevo si el estado se pierde.
- **RF-010c**: Los recursos de arranque (proveedor OIDC de GitHub, rol de los flujos y almacenamiento del estado) DEBEN quedar fuera de lo que gestiona y elimina el código, y figurar en el inventario como recursos externos de arranque.
- **RF-011**: El estado de la infraestructura como código DEBE guardarse de forma remota, cifrada y con bloqueo, de modo que dos ejecuciones no lo modifiquen a la vez y cualquier ejecución (flujo o local) parta del mismo estado.
- **RF-012**: El flujo de aprovisionamiento DEBE ejecutarse en cada commit (push) a `main` y, en este orden: ejecutar las pruebas unitarias y de integración; construir y publicar la imagen; calcular y aplicar los cambios de infraestructura; aplicar el esquema de la base (RF-016); desplegar la nueva versión del servicio; registrar o actualizar sus rutas en el API Gateway (RF-020); comprobar a través del gateway que el servicio responde. Cualquier paso fallido DEBE detener los siguientes.
- **RF-013**: Debe existir un flujo de desaprovisionamiento que solo se ejecute manualmente (bajo demanda desde GitHub) y que exija una confirmación explícita al lanzarlo (p. ej. escribir el nombre del entorno). Sin la confirmación no elimina nada.
- **RF-013b**: El desaprovisionamiento DEBE eliminar primero las rutas del servicio en el API Gateway y después todos los recursos gestionados como código, salvo los de arranque (RF-010c) y la plataforma compartida, y DEBE dejar una copia final de la base antes de eliminarla. La protección contra borrado de la base (RNF-007) solo la desactiva este flujo, nunca el de aprovisionamiento.
- **RF-014**: Los flujos DEBEN autenticarse en AWS con credenciales temporales (federación de identidad de GitHub), sin claves de acceso de larga duración guardadas en GitHub.
- **RF-015**: Los flujos DEBEN impedir ejecuciones simultáneas sobre la misma infraestructura (las posteriores esperan a que termine la anterior).
- **RF-016**: El flujo de aprovisionamiento DEBE aplicar `db/schema.sql` y los permisos del usuario de la aplicación (RF-009) en cada ejecución, después de aprovisionar la base y antes de desplegar la nueva versión; si la aplicación del esquema falla, no se despliega. Ejecutarlo sobre una base que ya tiene el esquema no produce errores ni cambios (RF-008).
- **RF-017**: El repositorio DEBE documentar: los recursos de arranque que se crean a mano una sola vez y cómo crearlos; la lista de variables y secretos de GitHub con su propósito y un ejemplo; cómo funciona cada flujo; las rutas del servicio en el API Gateway (públicas e internas) y cómo debe firmar las internas el servicio que las llama.
- **RF-018**: El entorno local (`docker-compose` con base de pruebas y datos semilla) DEBE seguir funcionando sin cambios en su forma de uso.
- **RF-019**: El servicio, la base de datos y la tarea del esquema DEBEN desplegarse en la red privada compartida, tomando sus identificadores (VPC, subredes privadas) del contrato publicado por la plataforma en el momento de cada aprovisionamiento, sin copiarlos a mano en el repositorio. El servicio NO DEBE tener URL pública propia y sus tareas NO DEBEN tener IP pública.
- **RF-020**: El servicio DEBE registrar en el API Gateway compartido exactamente estas rutas, siguiendo la convención de la plataforma: `GET /api/v1/geoespacial/reports` → `GET /api/v1/geospatial/reports` y `GET /api/v1/geoespacial/coordinates/{id}` → `GET /api/v1/geospatial/coordinates/{id}`, públicas (sin autenticación de clientes); y `POST /api/v1/geoespacial/coordinates` → `POST /api/v1/geospatial/coordinates`, interna, que exige firma de AWS de una identidad con permiso de invocación. Ninguna otra ruta del servicio (incluida `/health`) queda publicada.
- **RF-021**: Si la plataforma compartida no está aprovisionada, el flujo de aprovisionamiento DEBE fallar antes de modificar ningún recurso, con un mensaje que lo indique.

## 6. Requisitos no funcionales

- **RNF-001 (seguridad)**: Ningún secreto (contraseñas, cadenas de conexión) aparece en el repositorio, en la imagen, en las variables de GitHub ni en los logs de los flujos; la base no tiene acceso público y solo admite conexiones desde las tareas del servicio; el servicio solo es alcanzable desde internet a través del API Gateway; la asignación de localizaciones solo la puede invocar una identidad de AWS autorizada; el estado remoto de la infraestructura está cifrado y no es público.
- **RNF-002 (conexiones)**: Con el escalado al máximo, el número de conexiones simultáneas del servicio a la base no supera 50.
- **RNF-003 (idempotencia)**: Ejecutar el aprovisionamiento dos veces seguidas sobre el mismo commit produce cero cambios de infraestructura en la segunda ejecución.
- **RNF-004 (disponibilidad en despliegue)**: Durante un despliegue de una versión nueva, las rutas públicas del servicio en el API Gateway siguen respondiendo en todo momento (sin ventana de caída).
- **RNF-005 (duración)**: Un flujo de aprovisionamiento sin cambios de base de datos termina en menos de 20 minutos.
- **RNF-006 (coste)**: Se usan los tamaños mínimos adecuados para un proyecto académico (una zona de disponibilidad, instancia de base de datos de la clase más pequeña que admita la carga, mínimo de una tarea), documentados en el repositorio.
- **RNF-007 (protección de datos)**: La base tiene copias de seguridad automáticas con al menos 7 días de retención y protección contra borrado accidental.

## 7. Entidades clave

No hay entidades de datos nuevas: el esquema de coordenadas del servicio no cambia. Recursos del entorno relevantes para la spec:

- **Entorno en la nube**: base de datos espacial, secreto de conexión, registro de imágenes, servicio de contenedores (con balanceador interno), rutas del servicio en el API Gateway, reglas de red y logs.
- **Plataforma compartida** (externa a esta feature): red privada, salida a internet y API Gateway; esta feature solo la consume.
- **Estado de la infraestructura**: registro de qué recursos existen y su configuración, compartido entre ejecuciones.
- **Recursos de arranque**: lo que se crea a mano una vez porque el resto depende de ello (federación OIDC y rol de los flujos, almacenamiento del estado).

## 8. Fuera de alcance

- Varios entornos (staging/producción); hay un único entorno.
- Dominio propio y certificado propio: se usa la URL HTTPS del API Gateway compartido.
- Crear o modificar la plataforma compartida (red, NAT, API Gateway, VPC Link): pertenece a `urban-alert-plataforma`.
- Firmar las peticiones desde el servicio de Reportes y darle permiso de invocación: se hace en el repositorio de Reportes (esta feature solo documenta qué necesita).
- Autenticación de clientes finales en el gateway (no la tiene la plataforma).
- WAF, S3, SQS y DocumentDB: los usarán otros servicios de UrbanAlert; esta feature no los crea.
- RDS Proxy, alta disponibilidad multi-zona y réplicas de lectura.
- Migrar datos existentes: la base de la nube empieza vacía.
- Mensajería entre servicios (HU-4 diferida de la spec 001) y cambios del contrato de la API.
- Configurar el servicio de Reportes o el frontend para que apunten a la nueva URL.
- Paneles y alarmas de monitorización más allá de los que crea la plataforma por defecto.
- Validar el pipeline en pull requests (plan en PRs con rol de solo lectura): queda para una iteración posterior.

## 9. Supuestos

- Región `us-east-2` y una única cuenta de AWS (348364742283).
- Se usa la VPC compartida de la plataforma (subredes privadas en varias zonas, salida por NAT); ya no se usa la VPC predeterminada.
- La plataforma de contenedores es ECS en modo Express (Fargate); en subredes privadas crea un balanceador interno, al que el API Gateway llega por el VPC Link de la plataforma.
- El rol de los workflows ya tiene la política de la plataforma (`github-actions-urban-alert-platform`), que permite registrar rutas en el gateway y leer el contrato de SSM.
- La base es RDS for PostgreSQL 17 con PostGIS, instancia única, con la contraseña del usuario administrador gestionada por AWS.
- El almacenamiento del estado de la infraestructura (bucket) es un recurso de arranque que se crea a mano una vez, igual que el proveedor OIDC y el rol de los flujos.
- Las pruebas de integración en los flujos se ejecutan contra una base PostGIS en contenedor dentro del runner, no contra la base de la nube.
- La aplicación del esquema la ejecuta un usuario con permisos de administrador sobre la base; el usuario de la aplicación nunca altera el esquema.
- El límite de escalado por defecto es de 1 a 10 tareas y 5 conexiones por tarea (respeta RNF-002).
- Los flujos solo obtienen credenciales de AWS desde `main` (restricción ya configurada en el rol OIDC).

## 10. Métricas de éxito

- **MS-001**: Desde un commit a `main` hasta tener la nueva versión respondiendo en la URL pública pasan menos de 20 minutos, sin ninguna acción manual.
- **MS-002**: Las pruebas de contrato de la spec 001 (consultar cercanos y resolver por id sin firma; asignar con petición firmada) pasan contra la URL del API Gateway; la asignación sin firma recibe 403.
- **MS-003**: Una segunda ejecución del aprovisionamiento sin cambios reporta 0 recursos modificados.
- **MS-004**: Ningún secreto aparece al buscar en el repositorio, en la imagen publicada ni en los logs de las ejecuciones de los flujos.

## 11. Clarificaciones

### Sesión 2026-10-10
- P: ¿Qué hace el flujo manual? → R: Es el de **desaprovisionamiento**. Se añadió confirmación explícita, copia final de la base y conservación de los recursos de arranque (HU-2, RF-013, RF-013b).
- P: Los recursos creados a mano, ¿se importan o se referencian? → R: **Se importan** al código y quedan listados en un **pseudoinventario** en el repositorio (RF-010b). Supuesto añadido: los recursos de arranque (OIDC, rol de los flujos, estado) no se importan, para que el desaprovisionamiento no elimine las credenciales de los flujos (RF-010c).
- P: ¿Quién aplica el esquema? → R: **El flujo de aprovisionamiento**, en cada ejecución, antes de desplegar (RF-016).

### Sesión 2026-10-11 (revisión v2)
- P: ¿Cómo se expone el servicio? → R: Por **Amazon API Gateway**, **compartido** por todos los microservicios y gestionado en el repo `urban-alert-plataforma`; el servicio queda accesible **solo** por el gateway (HU-6, RF-019, RF-020, RF-021).
- Convención de rutas, firma IAM de la ruta interna y lectura del contrato por SSM: tomadas de la guía de integración de la plataforma (`docs/integracion.md`). La ruta `POST` es interna porque solo la llama Reportes (confirmado por el usuario: «Déjala privada»).

---

### Checklist de calidad (autorrevisión antes de entregar)

- [x] Sin detalles de implementación (lenguajes, frameworks, APIs, estructura de código) — las plataformas (AWS, GitHub Actions, Terraform, ECS Express, RDS) son restricciones fijadas por el usuario, no decisiones de diseño
- [x] Cada requisito es testeable y no ambiguo
- [x] Criterios de aceptación con resultado observable
- [x] Casos borde identificados
- [x] Alcance acotado (fuera de alcance explícito)
- [x] Como máximo 3 `[NEEDS CLARIFICATION]` pendientes (0 tras la sesión del 2026-10-10)
- [x] Coherente con `.sdd/constitution.md` (plantilla sin principios definidos)

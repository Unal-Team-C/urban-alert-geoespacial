# Especificación: Migración del Servicio Geoespacial a AWS

- **ID**: 002-migracion-aws
- **Estado**: borrador <!-- borrador | aclarada | aprobada | implementada -->
- **Creada**: 2026-10-10
- **Entrada original**: "Migración del servicio geoespacial a AWS (rama aws-provisioning): adaptar el código para la nube y crear CI/CD con GitHub Actions usando Terraform como base. Un flujo se ejecuta al hacer commit a main, que es el de aprovisionamiento. El otro flujo se ejecuta manualmente." + alcance acordado en la conversación: configuración para la nube (cadena de conexión desde el almacén de secretos, conexión cifrada, valores de producción, logs para CloudWatch), imagen apta para ECS Express Mode, solo el esquema en RDS PostgreSQL 17 + PostGIS (sin datos semilla ni base de pruebas), infraestructura como código con estado remoto, documentación de despliegue y de variables/secretos.

## 1. Resumen

Llevar el Servicio Geoespacial, que hoy solo se ejecuta en contenedores locales, a un entorno gestionado en AWS: base de datos espacial gestionada, servicio de contenedores con escalado automático y URL HTTPS, y toda la infraestructura descrita como código. El aprovisionamiento y el despliegue se automatizan con dos flujos de GitHub Actions: uno que se ejecuta en cada commit a `main` y otro que se lanza manualmente. El contrato de la API no cambia.

## 2. Problema y contexto

- El servicio solo se puede usar en la máquina de cada integrante (`docker-compose`), así que los demás servicios de UrbanAlert y el frontend no tienen una instancia compartida a la que llamar.
- Crear la infraestructura a mano en la consola no es repetible ni revisable: no queda registro de qué se cambió, ni se puede reconstruir el entorno si se borra.
- La configuración actual está pensada para local: credenciales de ejemplo por defecto, pool de 50 conexiones por proceso (rompe el presupuesto total de 50 conexiones al escalar, ver decisión D-013 de `docs/plan.md`) y conexión sin cifrar.
- Ya existen en la cuenta de AWS (348364742283, us-east-2), creados a mano: el proveedor OIDC de GitHub y el rol que asumen los workflows (política `github-actions-urban-alertPolicy`, válido para todos los repos de `Unal-Team-C`), los roles `urban-alert-ecs-execution-role` y `urban-alert-ecs-infrastructure-role`, y el repositorio de imágenes `urban-alert-geoespacial` (tags inmutables).

## 3. Usuarios y actores

- **Equipo de desarrollo**: publicar cambios del servicio y de la infraestructura con un commit a `main`, sin pasos manuales en la consola, y poder lanzar a mano la operación del flujo manual.
- **Servicio de Reportes y frontend (consumidores)**: llamar a una URL estable del servicio en la nube con el mismo contrato que en local.
- **Revisor / docente**: entender desde el repositorio qué infraestructura existe, cómo se despliega y qué variables y secretos hacen falta.

## 4. Historias de usuario

### HU-1: Aprovisionar y desplegar con un commit a `main` (Prioridad: P1)

Como integrante del equipo quiero que un commit a `main` aprovisione la infraestructura y deje desplegada la versión del servicio de ese commit, para no depender de pasos manuales.

**Criterios de aceptación**
1. Dado un commit a `main` con cambios en el código del servicio, cuando termina el flujo de aprovisionamiento, entonces la URL pública del servicio responde con la versión de ese commit y `/health` devuelve estado saludable.
2. Dado un commit a `main` que hace fallar las pruebas, cuando se ejecuta el flujo, entonces no se modifica la infraestructura ni se despliega nada, y el flujo queda en rojo.
3. Dado un commit a `main` sin cambios de infraestructura, cuando se ejecuta el flujo, entonces el aprovisionamiento informa de que no hay cambios en la infraestructura.
4. Dados dos commits seguidos a `main`, cuando sus flujos coinciden en el tiempo, entonces se ejecutan uno detrás de otro, nunca a la vez sobre la misma infraestructura.

### HU-2: Operación manual (Prioridad: P1)

Como integrante del equipo quiero lanzar a mano un segundo flujo para [NEEDS CLARIFICATION: ¿qué hace el flujo manual? Opciones: (a) desplegar la aplicación (construir y publicar la imagen y actualizar el servicio) sin tocar la infraestructura; (b) destruir el entorno para no generar costes; (c) aplicar el esquema de la base de datos; (d) otra].

**Criterios de aceptación**
1. Dado el repositorio en GitHub, cuando un integrante lanza el flujo manual, entonces se ejecuta solo bajo demanda (nunca por un commit) y el resultado queda registrado en la ejecución del flujo.

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

### Casos borde

- El flujo de aprovisionamiento falla a mitad (p. ej. error de permisos o de cuota) → el siguiente commit a `main` retoma desde el estado registrado sin duplicar recursos.
- Alguien cambia a mano en la consola un recurso gestionado como código → el siguiente aprovisionamiento muestra la diferencia y la devuelve a lo definido en el repositorio.
- Primer despliegue: la base aún no existe o tarda varios minutos en estar disponible → el servicio no se da por desplegado hasta que `/health` responde saludable.
- La base de datos no está disponible tras el despliegue → `/health` devuelve no disponible y la plataforma no envía tráfico a esas tareas.
- El escalado llega al máximo de tareas → el total de conexiones a la base no supera 50.
- Se intenta borrar la base desde el código por error → la base tiene protección contra borrado y el aprovisionamiento falla en lugar de borrarla.
- El flujo de aprovisionamiento se lanza desde una rama distinta de `main` o desde un fork → no obtiene credenciales de AWS.

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
- **RF-010**: Toda la infraestructura del servicio en la nube DEBE estar definida como código en el repositorio: base de datos PostgreSQL 17 con PostGIS, reglas de red de acceso a la base, secreto de conexión, registro de imágenes, servicio de contenedores con escalado automático, comprobación de salud y logs. [NEEDS CLARIFICATION: los recursos ya creados a mano (registro de imágenes `urban-alert-geoespacial`, roles `urban-alert-ecs-*`, y la base de datos si ya se creó siguiendo la guía) ¿se importan para que los gestione el código o se referencian como recursos externos existentes?]
- **RF-011**: El estado de la infraestructura como código DEBE guardarse de forma remota, cifrada y con bloqueo, de modo que dos ejecuciones no lo modifiquen a la vez y cualquier ejecución (flujo o local) parta del mismo estado.
- **RF-012**: El flujo de aprovisionamiento DEBE ejecutarse en cada commit (push) a `main` y, en este orden: ejecutar las pruebas unitarias y de integración; construir y publicar la imagen; calcular y aplicar los cambios de infraestructura; desplegar la nueva versión del servicio; comprobar que `/health` responde saludable. Cualquier paso fallido DEBE detener los siguientes.
- **RF-013**: Debe existir un segundo flujo que solo se ejecute manualmente (bajo demanda desde GitHub), con el comportamiento que se defina en HU-2.
- **RF-014**: Los flujos DEBEN autenticarse en AWS con credenciales temporales (federación de identidad de GitHub), sin claves de acceso de larga duración guardadas en GitHub.
- **RF-015**: Los flujos DEBEN impedir ejecuciones simultáneas sobre la misma infraestructura (las posteriores esperan a que termine la anterior).
- **RF-016**: La aplicación del esquema en la base [NEEDS CLARIFICATION: ¿la hace el flujo de aprovisionamiento en cada ejecución (antes de desplegar la nueva versión) o es un paso manual documentado?].
- **RF-017**: El repositorio DEBE documentar: los recursos de arranque que se crean a mano una sola vez y cómo crearlos; la lista de variables y secretos de GitHub con su propósito y un ejemplo; cómo funciona cada flujo; y la URL donde queda publicado el servicio.
- **RF-018**: El entorno local (`docker-compose` con base de pruebas y datos semilla) DEBE seguir funcionando sin cambios en su forma de uso.

## 6. Requisitos no funcionales

- **RNF-001 (seguridad)**: Ningún secreto (contraseñas, cadenas de conexión) aparece en el repositorio, en la imagen, en las variables de GitHub ni en los logs de los flujos; la base no tiene acceso público y solo admite conexiones desde las tareas del servicio; el estado remoto de la infraestructura está cifrado y no es público.
- **RNF-002 (conexiones)**: Con el escalado al máximo, el número de conexiones simultáneas del servicio a la base no supera 50.
- **RNF-003 (idempotencia)**: Ejecutar el aprovisionamiento dos veces seguidas sobre el mismo commit produce cero cambios de infraestructura en la segunda ejecución.
- **RNF-004 (disponibilidad en despliegue)**: Durante un despliegue de una versión nueva, `/health` responde saludable en todo momento (sin ventana de caída).
- **RNF-005 (duración)**: Un flujo de aprovisionamiento sin cambios de base de datos termina en menos de 20 minutos.
- **RNF-006 (coste)**: Se usan los tamaños mínimos adecuados para un proyecto académico (una zona de disponibilidad, instancia de base de datos de la clase más pequeña que admita la carga, mínimo de una tarea), documentados en el repositorio.
- **RNF-007 (protección de datos)**: La base tiene copias de seguridad automáticas con al menos 7 días de retención y protección contra borrado accidental.

## 7. Entidades clave

No hay entidades de datos nuevas: el esquema de coordenadas del servicio no cambia. Recursos del entorno relevantes para la spec:

- **Entorno en la nube**: base de datos espacial, secreto de conexión, registro de imágenes, servicio de contenedores con su URL pública, reglas de red y logs.
- **Estado de la infraestructura**: registro de qué recursos existen y su configuración, compartido entre ejecuciones.
- **Recursos de arranque**: lo que se crea a mano una vez porque el resto depende de ello (federación OIDC y rol de los flujos, almacenamiento del estado).

## 8. Fuera de alcance

- Varios entornos (staging/producción); hay un único entorno.
- Dominio propio y certificado propio: se usa la URL HTTPS que asigna la plataforma.
- WAF, S3, SQS y DocumentDB: los usarán otros servicios de UrbanAlert; esta feature no los crea.
- RDS Proxy, alta disponibilidad multi-zona y réplicas de lectura.
- Migrar datos existentes: la base de la nube empieza vacía.
- Mensajería entre servicios (HU-4 diferida de la spec 001) y cambios del contrato de la API.
- Configurar el servicio de Reportes o el frontend para que apunten a la nueva URL.
- Paneles y alarmas de monitorización más allá de los que crea la plataforma por defecto.
- Validar el pipeline en pull requests (plan en PRs con rol de solo lectura): queda para una iteración posterior.

## 9. Supuestos

- Región `us-east-2` y una única cuenta de AWS (348364742283).
- Se usa la VPC predeterminada de la cuenta; no se crea una red propia.
- La plataforma de contenedores es ECS en modo Express (Fargate), con el balanceador, la URL HTTPS y el escalado que crea ese modo.
- La base es RDS for PostgreSQL 17 con PostGIS, instancia única, con la contraseña del usuario administrador gestionada por AWS.
- El almacenamiento del estado de la infraestructura (bucket) es un recurso de arranque que se crea a mano una vez, igual que el proveedor OIDC y el rol de los flujos.
- Las pruebas de integración en los flujos se ejecutan contra una base PostGIS en contenedor dentro del runner, no contra la base de la nube.
- La aplicación del esquema la ejecuta un usuario con permisos de administrador sobre la base; el usuario de la aplicación nunca altera el esquema.
- El límite de escalado por defecto es de 1 a 10 tareas y 5 conexiones por tarea (respeta RNF-002).
- Los flujos solo obtienen credenciales de AWS desde `main` (restricción ya configurada en el rol OIDC).

## 10. Métricas de éxito

- **MS-001**: Desde un commit a `main` hasta tener la nueva versión respondiendo en la URL pública pasan menos de 20 minutos, sin ninguna acción manual.
- **MS-002**: Las pruebas de contrato de la spec 001 (asignar, consultar cercanos, resolver por id, salud) pasan contra la URL pública del servicio.
- **MS-003**: Una segunda ejecución del aprovisionamiento sin cambios reporta 0 recursos modificados.
- **MS-004**: Ningún secreto aparece al buscar en el repositorio, en la imagen publicada ni en los logs de las ejecuciones de los flujos.

## 11. Clarificaciones

<!-- /sdd-clarify añade aquí:
### Sesión AAAA-MM-DD
- P: … → R: … -->

---

### Checklist de calidad (autorrevisión antes de entregar)

- [x] Sin detalles de implementación (lenguajes, frameworks, APIs, estructura de código) — las plataformas (AWS, GitHub Actions, Terraform, ECS Express, RDS) son restricciones fijadas por el usuario, no decisiones de diseño
- [x] Cada requisito es testeable y no ambiguo
- [x] Criterios de aceptación con resultado observable
- [x] Casos borde identificados
- [x] Alcance acotado (fuera de alcance explícito)
- [x] Como máximo 3 `[NEEDS CLARIFICATION]` pendientes
- [x] Coherente con `.sdd/constitution.md` (plantilla sin principios definidos)

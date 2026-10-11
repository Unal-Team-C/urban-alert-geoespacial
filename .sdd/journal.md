# Journal SDD

<!-- Bitácora append-only: añade entradas AL FINAL, no reescribas las anteriores.
     Formato:
     ## AAAA-MM-DD · <feature o "general"> · <evento>
     - detalle (qué, por qué, archivos, verificación)
     Las horas exactas de cada edición/checkpoint quedan en .sdd/activity.log. -->

## 2026-09-24 · general · Arnés SDD instalado
- Hooks (SessionStart, PostToolUse, PreCompact, Stop), 11 comandos /sdd-*, protocolo, plantillas e instalador.
- Probado: rastreo de ediciones, bloqueo en Stop, checkpoint vía STATE.md, reinyección de contexto, instalación/fusión en otro proyecto.

## 2026-10-10 · general · Servicio geoespacial migrado a este repositorio
- Copiado desde el monorepo UrbanAlert (`backend/UrbanAlert.Geoespacial`, commit 46daa1f) a la raíz del repo; arnés SDD conservado.
- README del servicio como README raíz (+ sección SDD); la guía del arnés pasa a `.sdd/GUIA.md`; `.gitignore` fusionado.
- Remoto `origin` → github.com/Unal-Team-C/urban-alert-geoespacial.

## 2026-10-10 · general · Decisión: en AWS solo se aplica el esquema
- RDS PostgreSQL 17 + PostGIS (`urban-alert-geoespacial-db`, us-east-2) se inicializa solo con `db/schema.sql` + usuario `geospatial_app` (SELECT, INSERT).
- Sin datos semilla (`db/seed.sql`) ni base `geospatial_test` en AWS; las pruebas de integración corren en GitHub Actions. Local (compose + 01_init.sh) sin cambios.

## 2026-10-10 · 002-migracion-aws · Creada spec desde descripción
- Migración a AWS: servicio apto para la nube (secreto + TLS, pool ≤ 50 conexiones totales, logs estructurados, apagado ordenado), esquema solo en RDS PostGIS, Terraform con estado remoto, workflow de aprovisionamiento en push a `main` + workflow manual, documentación.
- 18 RF, 7 RNF. 3 dudas abiertas: qué hace el workflow manual (HU-2/RF-013), importar o referenciar recursos creados a mano (RF-010), quién aplica el esquema (RF-016).
- Numerada 002 porque `docs/` contiene la spec 001 original del servicio.
- Nota de entorno: los hooks del arnés invocan `powershell`, no instalado en este Mac; no se ejecutan.

## 2026-10-10 · 002-migracion-aws · Clarificaciones resueltas (spec aclarada)
- Flujo manual = desaprovisionamiento, con confirmación explícita, copia final de la BD y sin tocar recursos de arranque (HU-2, RF-013, RF-013b).
- Recursos creados a mano se importan a Terraform y se listan en un pseudoinventario (RF-010b); OIDC, rol de flujos y bucket de estado quedan fuera como arranque (RF-010c, supuesto para no autodestruir credenciales).
- El esquema lo aplica el flujo de aprovisionamiento en cada ejecución, antes de desplegar (RF-016).

## 2026-10-10 · 002-migracion-aws · Spec aprobada
- Aprobada por el usuario. Confirmado: política de despliegue corregida (ECR urban-alert-*, PassRole), bucket `urban-alert-tfstate-348364742283`, política `github-actions-urban-alert-terraform` adjunta, secretos/variables de GitHub creados. RDS/SG/secreto de BD no existen: los crea Terraform.

## 2026-10-10 · 002-migracion-aws · Plan redactado (borrador)
- D-001 dos stacks Terraform (platform/service); D-002 servicio Express en Terraform; D-003 esquema con tarea ECS puntual `python -m app.db.migrate` con la imagen del servicio; D-004 platform antes del push de imagen (ECR puede no existir tras deprovision).
- D-005 imports.tf de un solo uso + infra/INVENTARIO.md; D-006 VPC predeterminada; D-007 maestro gestionado por RDS + secreto propio de la app; D-008 sslmode=require; D-009 logs JSON stdlib; D-010 uvicorn graceful 20 s; D-011 X86_64.
- D-012/D-013 deprovision con input de confirmación, sin GitHub environments; D-015 precondición pool×tareas ≤ 50; D-019 clúster propio.
- GitHub: solo AWS_ROLE_ARN + AWS_REGION; el resto de variables antiguas sobra. Investigación en research.md.

## 2026-10-10 · 002-migracion-aws · Ajustes al plan
- Terraform solo desde GitHub Actions (sin plan local): riesgo del primer apply en `main` aceptado.
- Política en línea del rol de ejecución: `read-project-secrets` (para imports.tf/INVENTARIO.md). Pendiente confirmar dónde están adjuntas `github-actions-urban-alert-terraform` y `github-actions-urban-alertPolicy` (deben ir en el rol de GitHub, no en los de ECS).

## 2026-10-10 · 002-migracion-aws · Plan aprobado
- El usuario respondió «Adelante»: plan aprobado; se asume la asignación de políticas confirmada (las dos de GitHub en el rol de GitHub; `read-project-secrets` en el rol de ejecución).

## 2026-10-10 · 002-migracion-aws · tasks.md generado: 25 tareas
- Preparación 3, Pruebas 3, Núcleo 13, Integración 2, Pulido 2, Despliegue real 2. Todos los RF/RNF cubiertos.
- Verificación local de Terraform/actionlint/shellcheck con contenedores Podman (no hay binarios instalados).

## 2026-10-10 · 002-migracion-aws · Tareas aprobadas
- Aprobadas por el usuario; fase implement.

## 2026-10-10 · 002-migracion-aws · T001 hecha
- .dockerignore excluye infra/, .github/, scripts/. Verificado: podman build --target runtime OK; /srv solo contiene app y requirements.txt.

## 2026-10-10 · 002-migracion-aws · T002 hecha
- infra/bootstrap/: README (OIDC, rol de GitHub con sus dos políticas, bucket de estado, secretos/variables de GitHub) + 5 JSON (confianza, política de despliegue corregida, política de Terraform, política TLS y ciclo de vida del bucket). Verificado: json.tool sin errores.

## 2026-10-10 · 002-migracion-aws · T003 hecha
- infra/INVENTARIO.md: 6 recursos importados (ECR, 2 roles, 2 adjuntos, read-project-secrets) con ID/dirección/bloque import; recursos que crea Terraform; arranque como no gestionado. La regla de ciclo de vida de ECR no se importa (PutLifecyclePolicy sobrescribe). Verificado: cada importado tiene las tres columnas.

## 2026-10-10 · 002-migracion-aws · T004 hecha
- tests/unit/test_observability.py: formateador (campos base, extras, excepción en una línea, extras no serializables), configure_logging (root + uvicorn), middleware (una línea por petición, sin query string, 500 como ERROR). Verificado: falla solo por ModuleNotFoundError: app.observability.

## 2026-10-10 · 002-migracion-aws · T005 hecha
- tests/integration/test_migrate.py: esquema aplicado (postgis, tabla, índice), dos ejecuciones sin error, privilegios SELECT/INSERT sí y UPDATE/DELETE/TRUNCATE no, sin DDL, contraseña sincronizada (con comillas), sslmode=require falla contra servidor sin TLS. Verificado: falla solo por ModuleNotFoundError: app.db.migrate.

# Tareas: Migración del Servicio Geoespacial a AWS

- **Plan**: ./plan.md
- **Estado**: aprobado <!-- borrador | aprobado -->

Leyenda: `[ ]` pendiente · `[~]` en progreso · `[x]` hecha · `[!]` bloqueada · `[-]` descartada · `[P]` paralelizable

Formato de cada tarea (una línea):
`- [ ] T001 [P] Descripción imperativa — archivos: ruta/a, ruta/b — cubre: RF-001 — verifica: <comando o criterio observable>`

Dependencias: cada fase depende de la anterior; dentro de una fase se ejecuta en orden salvo `[P]`.
Dependencias explícitas: añadir `— depende: T00X`.

**Herramientas de verificación local** (no hay `terraform` ni `actionlint` instalados; se usan contenedores con Podman, con `podman machine start` previo):
- `podman run --rm -v "$PWD":/w -w /w docker.io/hashicorp/terraform:1.16.5 -chdir=infra/<stack> init -backend=false` y luego `validate`, `test`; `fmt -check -recursive infra` (abajo, `$TF` abrevia este comando)
- `podman run --rm -v $PWD:/repo -w /repo docker.io/rhysd/actionlint:1.7.7`
- `podman run --rm -v $PWD:/mnt -w /mnt docker.io/koalaman/shellcheck:stable scripts/*.sh`
- Pruebas Python: `docker-compose --profile test run --rm --build tests` (ver README si falla `docker-credential-desktop`)

## Fase 1: Preparación

- [x] T001 [P] Excluir del contexto de build `infra/`, `.github/` y `scripts/` — archivos: .dockerignore — cubre: RNF-001 — verifica: `podman build --target runtime -t geo:t001 .` termina bien y `podman run --rm geo:t001 ls /srv` no muestra `infra` ni `.github`
- [x] T002 [P] Documentar los recursos de arranque y versionar sus JSON (confianza OIDC con `repo:Unal-Team-C/*`, política de despliegue corregida, política de Terraform, política TLS y ciclo de vida del bucket) — archivos: infra/bootstrap/README.md, infra/bootstrap/github-oidc-trust.json, infra/bootstrap/github-deploy-policy.json, infra/bootstrap/github-terraform-policy.json, infra/bootstrap/tfstate-bucket-policy.json, infra/bootstrap/tfstate-lifecycle.json — cubre: RF-010c, RF-017 — verifica: `for f in infra/bootstrap/*.json; do python3 -m json.tool "$f" >/dev/null || echo FALLA $f; done` sin salida; el README enumera OIDC, rol de GitHub (con sus dos políticas), bucket de estado y los secretos/variables de GitHub (`AWS_ROLE_ARN`, `AWS_REGION`)
- [x] T003 [P] Crear el pseudoinventario: recursos importados (ECR `urban-alert-geoespacial` y su regla de ciclo de vida si existe, roles `urban-alert-ecs-execution-role` / `-infrastructure-role`, sus adjuntos de políticas gestionadas, política en línea `read-project-secrets`) con su ID en AWS, dirección de Terraform y bloque `import`; y recursos externos de arranque — archivos: infra/INVENTARIO.md — cubre: RF-010b, RF-010c — verifica: cada recurso tiene ID, dirección y bloque `import`; los de arranque están marcados como «no gestionados»

## Fase 2: Pruebas

- [x] T004 [P] Escribir pruebas del formateador JSON (campos `timestamp`, `level`, `logger`, `message`, extras, excepción serializada) y del middleware de acceso (una línea con `method`, `path`, `status`, `duration_ms`) — archivos: tests/unit/test_observability.py — cubre: RF-004 — verifica: `docker-compose --profile test run --rm --build tests pytest tests/unit/test_observability.py` falla solo por `ModuleNotFoundError: app.observability`
- [x] T005 [P] Escribir pruebas de la migración: aplica el esquema sobre `geospatial_test`, segunda ejecución sin error, el rol de aplicación (`DB_APP_USER` de prueba) puede `SELECT`/`INSERT` y no `UPDATE`/`DELETE`/`DROP`, el cambio de contraseña se sincroniza, `DB_SSLMODE` se respeta — archivos: tests/integration/test_migrate.py — cubre: RF-002, RF-008, RF-009 — verifica: la prueba falla solo por `ModuleNotFoundError: app.db.migrate`
- [x] T006 [P] Escribir la prueba de apagado: uvicorn en subproceso contra `geospatial_test`, petición lenta en curso + `SIGTERM` → la petición termina con 200, el proceso sale con 0 en < 25 s y el log contiene el cierre del pool — archivos: tests/integration/test_shutdown.py — cubre: RF-005 — verifica: la prueba se ejecuta y falla en la aserción del log de cierre del pool (todavía no se registra)

## Fase 3: Núcleo

- [x] T007 Implementar logs JSON y middleware de acceso; registrarlos en la app y registrar el cierre del pool en el `lifespan` — archivos: app/observability.py, app/main.py — cubre: RF-004 — verifica: `docker-compose --profile test run --rm --build tests pytest tests/unit` en verde — depende: T004
- [x] T008 Implementar `python -m app.db.migrate` (esquema en una transacción, rol de aplicación idempotente con contraseña vía `format('%L')`, permisos `CONNECT`/`USAGE`/`SELECT, INSERT`, `DB_SSLMODE` por defecto `require`) — archivos: app/db/migrate.py, compose.yaml (solo variables del servicio `tests` para la migración) — cubre: RF-002, RF-008, RF-009 — verifica: `docker-compose --profile test run --rm --build tests pytest tests/integration/test_migrate.py` en verde — depende: T005
- [x] T009 Ajustar la imagen: copiar `db/schema.sql` a `/srv/db/`, `CMD` con `--no-access-log --timeout-graceful-shutdown 20 --proxy-headers --forwarded-allow-ips=*` — archivos: Dockerfile — cubre: RF-005, RF-006, RF-018 — verifica: `docker-compose --profile test run --rm --build tests` (suite completa, incluida `test_shutdown.py`) en verde y `docker-compose up -d --build --wait` deja `api` healthy — depende: T006, T007, T008
- [x] T010 Crear la base del stack platform: versiones (`>= 1.10, < 2.0`, `aws ~> 6.0`, `random ~> 3.6`), backend S3 (`urban-alert-tfstate-348364742283`, `geoespacial/platform.tfstate`, `use_lockfile`, `encrypt`), proveedor con `default_tags`, variables (`image_tag`, `allow_destroy`, `final_snapshot_suffix`, tamaños) y `terraform.tfvars`; red: VPC y subredes predeterminadas por data source, SG de tareas y SG de RDS (5432 solo desde el SG de tareas) — archivos: infra/platform/versions.tf, backend.tf, providers.tf, variables.tf, terraform.tfvars, network.tf — cubre: RF-010, RF-011, RNF-001 — verifica: `$TF -chdir=infra/platform init -backend=false && $TF -chdir=infra/platform validate` → «Success»
- [x] T011 Definir ECR (inmutable, scan on push, ciclo de vida de 20 imágenes, `force_delete = var.allow_destroy`) e IAM (roles de ejecución e infraestructura, adjuntos gestionados, `read-project-secrets` ampliada al secreto `rds!…` de esta base y al secreto de la app) — archivos: infra/platform/ecr.tf, infra/platform/iam.tf — cubre: RF-010, RF-013b, RNF-001 — verifica: `validate` en verde — depende: T010
- [x] T012 Definir RDS (PG 17, `db.t4g.micro`, gp3 20→50 GiB, Single-AZ, privada, cifrada, backups 7 días, `manage_master_user_password`, `deletion_protection = !var.allow_destroy`, `skip_final_snapshot = false` con `final_snapshot_identifier` por sufijo) y el secreto de la app (`random_password`, JSON con `DATABASE_URL ...?sslmode=require`, `recovery_window_in_days = 0`) — archivos: infra/platform/rds.tf, infra/platform/secrets.tf — cubre: RF-001, RF-002, RF-009, RF-013b, RNF-001, RNF-006, RNF-007 — verifica: `validate` en verde — depende: T010
- [x] T013 Definir el clúster ECS, los grupos de logs (30 días), la task definition del esquema (Fargate X86_64, imagen `:${image_tag}`, `python -m app.db.migrate`, secretos del maestro y de la app) y las salidas usadas por los workflows — archivos: infra/platform/ecs.tf, infra/platform/logs.tf, infra/platform/schema_task.tf, infra/platform/outputs.tf — cubre: RF-010, RF-016 — verifica: `validate` en verde y `outputs.tf` expone `ecr_repository_url`, `cluster_name`, `schema_task_definition_arn`, `subnet_ids`, `tasks_security_group_id`, `schema_log_group` — depende: T011, T012
- [x] T014 Escribir los bloques `import` de un solo uso según el inventario — archivos: infra/platform/imports.tf, infra/INVENTARIO.md — cubre: RF-010b — verifica: `validate` en verde; cada bloque de `imports.tf` aparece en `INVENTARIO.md` con el mismo ID — depende: T003, T013
- [x] T015 Escribir pruebas del stack platform con `mock_provider "aws"`: `deletion_protection` true por defecto y false con `allow_destroy`, `force_delete` igual; RDS `publicly_accessible=false`, `storage_encrypted=true`, `backup_retention_period>=7`; SG de RDS solo con origen el SG de tareas; secreto con `recovery_window_in_days = 0` — archivos: infra/platform/tests/platform.tftest.hcl — cubre: RNF-001, RNF-007, RF-013b — verifica: `$TF -chdir=infra/platform test` → todas las ejecuciones «pass» — depende: T014
- [x] T016 Crear el stack service: backend `geoespacial/service.tfstate`, `terraform_remote_state` de platform, `aws_ecs_express_gateway_service` (imagen `:${image_tag}`, puerto 8000, `/health`, 512/1024, 1–10 tareas por CPU 60 %, entorno `DB_POOL_MIN=1`/`DB_POOL_MAX=5`/`MAX_RADIUS_M=6000`, secreto `DATABASE_URL`, logs, red, `wait_for_steady_state`), precondición `db_pool_max × max_tasks ≤ 50`, salida `service_url` — archivos: infra/service/versions.tf, backend.tf, providers.tf, variables.tf, terraform.tfvars, main.tf, outputs.tf — cubre: RF-001, RF-003, RF-006, RF-010, RNF-002, RNF-004 — verifica: `$TF -chdir=infra/service init -backend=false && validate` en verde; `terraform init` resuelve un proveedor que incluye `aws_ecs_express_gateway_service`
- [x] T017 Escribir pruebas del stack service con `mock_provider` y `override_data` del estado remoto: 5×10 pasa, 6×10 falla la precondición; el contenedor usa puerto 8000 y `/health`; `DATABASE_URL` viene de un secreto, no de `environment` — archivos: infra/service/tests/service.tftest.hcl — cubre: RF-001, RF-003, RNF-002 — verifica: `$TF -chdir=infra/service test` → «pass» — depende: T016
- [x] T018 [P] Escribir el script que lanza la tarea del esquema (`aws ecs run-task` con `assignPublicIp=ENABLED`, `aws ecs wait tasks-stopped`, imprime logs de CloudWatch, devuelve el `exitCode` del contenedor; falla si la tarea no arranca) — archivos: scripts/run-schema-task.sh — cubre: RF-016 — verifica: `bash -n scripts/run-schema-task.sh` y shellcheck sin avisos
- [x] T019 Generar y versionar los lockfiles de proveedores para `linux_amd64` y `darwin_arm64` y aplicar `fmt` — archivos: infra/platform/.terraform.lock.hcl, infra/service/.terraform.lock.hcl — cubre: RF-010 (D-017) — verifica: `$TF -chdir=infra/<stack> init -backend=false -lockfile=readonly` funciona en ambos stacks y `$TF fmt -check -recursive infra` sin diferencias — depende: T015, T017

## Fase 4: Integración

- [x] T020 Crear el workflow de aprovisionamiento: `push` a `main`, `concurrency` común sin cancelar; job `test` (suite Python en compose, `fmt`/`validate`/`test` de ambos stacks, `actionlint`); job `provision` (OIDC → apply platform con `image_tag=$GITHUB_SHA` → login ECR → build `linux/amd64` + push si el tag no existe → `run-schema-task.sh` → apply service → `curl` con reintentos a `/health` y a una consulta de cercanía → URL en el resumen) — archivos: .github/workflows/provision.yml — cubre: RF-007, RF-012, RF-014, RF-015, RF-016, RNF-005 — verifica: actionlint sin errores; no hay `aws-access-key-id` en el YAML; el orden de pasos coincide con D-004 — depende: T018, T019
- [x] T021 Crear el workflow de desaprovisionamiento: `workflow_dispatch` con input `confirm`, falla sin tocar nada si no es `urban-alert-geoespacial`; misma `concurrency`; destroy service → apply platform con `allow_destroy=true` y `final_snapshot_suffix=${{ github.run_id }}` → destroy platform — archivos: .github/workflows/deprovision.yml — cubre: RF-013, RF-013b, RF-014, RF-015 — verifica: actionlint sin errores; sin `on: push`; el paso de confirmación es el primero y corta el job

## Fase 5: Pulido

- [x] T022 [P] Añadir al README la sección «Despliegue en AWS»: arquitectura, recursos de arranque (enlace a `infra/bootstrap/`), secretos/variables de GitHub, qué hace cada workflow y cómo lanzarlos, inventario, costes aproximados y cómo desaprovisionar, restaurar la copia final y borrar copias antiguas — archivos: README.md — cubre: RF-017, RNF-006 — verifica: la sección cubre los cuatro puntos de RF-017 y enlaza `infra/bootstrap/README.md` e `infra/INVENTARIO.md`
- [x] T023 [P] Actualizar CLAUDE.md con la estructura `infra/` y los comandos de verificación con Podman — archivos: CLAUDE.md — cubre: — (pulido) — verifica: los comandos documentados coinciden con los de este fichero

## Fase 6: Despliegue real (requiere acciones del usuario en GitHub)

- [-] T024 Abrir el PR `aws-provisioning` → `main` (con confirmación del usuario), fusionarlo y seguir la primera ejecución de `provision.yml`; corregir fallos (p. ej. permisos IAM) con commits pequeños a `main`, actualizando `infra/bootstrap/*.json` si cambia alguna política — archivos: los que requiera cada corrección — cubre: RF-010b, RF-012, RF-016, RNF-004 — verifica: ejecución en verde; `curl <service_url>/health` → 200; ECR y roles importados conservan su ARN y fecha de creación — depende: T020, T021, T022 — descartada: sustituida por T037 (revisión v2; el PR #1 se fusionó y el primer Provision falló en OIDC sin crear nada)
- [-] T025 Eliminar `imports.tf` tras la primera importación correcta, marcar en el inventario la fecha de importación y comprobar la idempotencia — archivos: infra/platform/imports.tf (borrado), infra/INVENTARIO.md — cubre: RF-010b, RNF-003 — verifica: la ejecución de `provision.yml` de ese commit muestra «No changes» en platform y solo el cambio de imagen (o ninguno) en service — depende: T024 — descartada: sustituida por T038 (revisión v2)

## Fase 7: Revisión v2 — exposición por el API Gateway compartido (plan §Revisión v2)

- [x] T026 Renombrar el stack `infra/platform` a `infra/base` (backend `geoespacial/base.tfstate`, `Stack = "base"`, prueba `tests/base.tftest.hcl`) y actualizar todas las referencias (workflows, README, INVENTARIO, CLAUDE.md, bootstrap) — archivos: infra/base/**, .github/workflows/*.yml, README.md, infra/INVENTARIO.md, CLAUDE.md — cubre: RF-010 (D-020) — verifica: `$TF -chdir=infra/base init -backend=false && validate && test` en verde; `grep -rn "infra/platform\|platform.tfstate" --exclude-dir=specs --exclude-dir=.sdd .` sin resultados
- [ ] T027 Tomar la red de la plataforma desde SSM (`vpc-id`, `subredes-privadas`) en lugar de la VPC predeterminada; SG y subnet group en la VPC compartida; pruebas con `override_data` de los parámetros — archivos: infra/base/network.tf, infra/base/rds.tf, infra/base/outputs.tf, infra/base/tests/base.tftest.hcl — cubre: RF-019 (D-021) — verifica: `$TF -chdir=infra/base test` en verde, con asserts de VPC del SG = `vpc-id` de SSM y subredes del subnet group = `subredes-privadas` — depende: T026
- [ ] T028 [P] Copiar `buscar-listener-express.sh` de la plataforma y crear `check-platform.sh` (falla con mensaje claro si falta algún parámetro de `/urban-alert/plataforma/`), con una prueba que use un `aws` simulado en el PATH — archivos: scripts/buscar-listener-express.sh, scripts/check-platform.sh, scripts/tests/test-check-platform.sh — cubre: RF-021 (D-025) — verifica: `bash scripts/tests/test-check-platform.sh` pasa (9 parámetros → 0; falta uno → ≠0 y mensaje «plataforma compartida no está aprovisionada»); shellcheck sin avisos
- [ ] T029 [P] Lanzar la tarea del esquema sin IP pública — archivos: scripts/run-schema-task.sh — cubre: RF-019 (D-022) — verifica: `grep -c "assignPublicIp=DISABLED" scripts/run-schema-task.sh` = 1; shellcheck sin avisos
- [ ] T030 Ajustar el stack service: estado remoto `geoespacial/base.tfstate`, salidas `service_endpoint` (host sin esquema), `service_name` y `cluster_name`; pruebas actualizadas (endpoint sin `https://`) — archivos: infra/service/main.tf, infra/service/outputs.tf, infra/service/tests/service.tftest.hcl — cubre: RF-019, RF-020 — verifica: `$TF -chdir=infra/service test` en verde — depende: T026
- [ ] T031 Crear el stack routes: backend `geoespacial/routes.tfstate`, `data` SSM de `api-id`/`vpc-link-id`/`api-endpoint`, variables `express_endpoint` y `express_listener_arn` con validación, 3 integraciones HTTP_PROXY por VPC Link (Host/TLS = endpoint, payload 1.0, reescritura de ruta) y 3 rutas (GET públicas, POST `AWS_IAM`), salidas `gateway_url` y `route_keys`, lockfile multiplataforma — archivos: infra/routes/*.tf, infra/routes/terraform.tfvars, infra/routes/.terraform.lock.hcl — cubre: RF-020 (D-023) — verifica: `$TF -chdir=infra/routes init -backend=false -lockfile=readonly && validate` en verde; `fmt -check` limpio
- [ ] T032 Escribir las pruebas del stack routes con `mock_provider` y `override_data` de SSM: claves de ruta exactas, `authorization_type` por ruta, ninguna `$default`, cada integración con `VPC_LINK`, `connection_id` = `vpc-link-id`, payload 1.0, `overwrite:header.host` y `server_name_to_verify` = endpoint, `overwrite:path` esperado; endpoint con esquema y ARN que no es de listener → error de validación — archivos: infra/routes/tests/routes.tftest.hcl — cubre: RF-020 — verifica: `$TF -chdir=infra/routes test` en verde — depende: T031
- [ ] T033 [P] Escribir la prueba de humo por el gateway (GET reports 200 con array; GET coordinates/<uuid aleatorio> 404 del servicio; POST sin firma 403; GET /api/v1/geoespacial/health 404; reintentos solo en la primera) — archivos: scripts/smoke-gateway-geoespacial.sh — cubre: HU-6, RF-020, RNF-001 (D-024) — verifica: shellcheck sin avisos; contra el gateway actual (sin rutas del servicio) falla en la primera comprobación con un mensaje claro
- [ ] T034 Actualizar `provision.yml` al orden v2: credenciales → `check-platform.sh` → (job test) → base → imagen → esquema → service → `buscar-listener-express.sh` → routes → humo; resumen con la URL del gateway; incluir `infra/routes` y `scripts/tests` en el job de pruebas — archivos: .github/workflows/provision.yml — cubre: RF-012, RF-020, RF-021 (D-025) — verifica: actionlint sin errores; el orden de pasos coincide con la tabla de la revisión v2 — depende: T027, T028, T029, T030, T032, T033
- [ ] T035 Actualizar `deprovision.yml`: routes destroy (variables de relleno válidas) → service destroy → base allow_destroy apply → base destroy; cada paso salta si su estado está vacío — archivos: .github/workflows/deprovision.yml — cubre: RF-013b (D-026) — verifica: actionlint sin errores; el primer paso sigue siendo la confirmación — depende: T031
- [ ] T036 [P] Documentar la v2: README (exposición solo por el gateway, tabla de rutas públicas/internas, URL del gateway, qué necesita Reportes: `execute-api:Invoke` + SigV4, orden de desaprovisionamiento respecto a la plataforma), INVENTARIO (rutas e integraciones creadas por Terraform; la plataforma como recurso externo), bootstrap README (política `github-actions-urban-alert-platform`) — archivos: README.md, infra/INVENTARIO.md, infra/bootstrap/README.md — cubre: RF-017 — verifica: los cuatro puntos de RF-017 v2 aparecen y enlazan la guía de la plataforma — depende: T026
- [ ] T037 Subir `aws-provisioning`, abrir el PR a `main` (con confirmación del usuario), fusionarlo (usuario) y seguir la primera ejecución de `provision.yml`; corregir fallos con commits pequeños — archivos: los que requiera cada corrección — cubre: RF-010b, RF-012, RF-016, RF-019, RF-020, RNF-004 — verifica: ejecución en verde con el humo D-024 en verde; ECR y roles importados conservan ARN y fecha de creación; el ALB de Express es `internal` — depende: T034, T035, T036
- [ ] T038 Eliminar `imports.tf` tras la primera importación correcta, fechar la importación en el inventario y comprobar la idempotencia — archivos: infra/base/imports.tf (borrado), infra/INVENTARIO.md — cubre: RF-010b, RNF-003 — verifica: la ejecución de ese commit muestra «No changes» en base y routes, y solo el cambio de imagen (o ninguno) en service — depende: T037

## Correcciones de verificación

<!-- /sdd-verify añade aquí tareas si detecta fallos -->

## Cobertura

| Requisito | Tareas |
|---|---|
| RF-001 | T012, T016, T017 |
| RF-002 | T005, T008, T012 |
| RF-003 | T016, T017 |
| RF-004 | T004, T007 |
| RF-005 | T006, T009 |
| RF-006 | T009, T016 |
| RF-007 | T020 |
| RF-008 | T005, T008 |
| RF-009 | T005, T008, T012 |
| RF-010 | T010, T011, T013, T016, T019 |
| RF-010b | T003, T014, T037, T038 |
| RF-010c | T002, T003 |
| RF-011 | T010 |
| RF-012 | T020, T034, T037 |
| RF-013 | T021 |
| RF-013b | T011, T012, T015, T021, T035 |
| RF-014 | T020, T021 |
| RF-015 | T020, T021 |
| RF-016 | T013, T018, T020, T037 |
| RF-017 | T002, T022, T036 |
| RF-018 | T009 |
| RF-019 | T027, T029, T030, T037 |
| RF-020 | T031, T032, T033, T034, T037 |
| RF-021 | T028, T034 |
| HU-6 | T033, T037 |
| RNF-001 | T001, T010, T011, T012, T015, T033 |
| RNF-002 | T016, T017 |
| RNF-003 | T038 |
| RNF-004 | T016, T037 |
| RNF-005 | T020 |
| RNF-006 | T012, T022 |
| RNF-007 | T012, T015 |

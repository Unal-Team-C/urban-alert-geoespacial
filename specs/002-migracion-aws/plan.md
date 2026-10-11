# Plan técnico: Migración del Servicio Geoespacial a AWS

- **Spec**: ./spec.md
- **Estado**: aprobado <!-- borrador | aprobado -->
- **Fecha**: 2026-10-10
- **Investigación**: ./research.md
- **Revisión**: v2 (2026-10-11), por la spec v2: exposición solo por el API Gateway compartido. La sección «Revisión v2» prevalece sobre lo que contradiga en §1–§11.

## Revisión v2: consumo de la plataforma compartida

Contrato de la plataforma (`Unal-Team-C/urban-alert-plataforma`, feature 001-red-api-gateway, aprovisionada): parámetros SSM bajo `/urban-alert/plataforma/` (`region`, `vpc-id`, `vpc-cidr`, `subredes-privadas`, `api-id`, `api-endpoint`, `api-execution-arn`, `vpc-link-id`, `vpc-link-sg-id`) y guía `docs/integracion.md`. El rol de GitHub ya tiene `github-actions-urban-alert-platform` (apigateway sobre `/apis/*`, `ssm:GetParameter*` sobre `/urban-alert/*`, `elasticloadbalancing:Describe*`).

**Cambios respecto a la v1**

| Pieza | v1 | v2 |
|---|---|---|
| Stacks | `platform` + `service` | `base` (renombre de `platform`, para no confundirlo con la plataforma compartida) + `service` + **`routes`** (D-020) |
| Red | VPC predeterminada, subredes públicas (D-006) | VPC y subredes privadas de la plataforma leídas de SSM en cada `plan` (D-021). D-006 queda sustituida |
| Servicio Express | ALB público + URL `.on.aws` | ALB **interno** (subredes privadas), tareas sin IP pública, salida por el NAT de la plataforma |
| Tarea del esquema | `assignPublicIp=ENABLED` | Subredes privadas, `assignPublicIp=DISABLED` (D-022) |
| Exposición | URL de Express | Rutas en el API Gateway compartido (D-023) |
| Comprobación final | `curl` a `<url>/health` | Humo por el gateway (D-024) |
| Orden de `provision.yml` | pruebas → platform → imagen → esquema → service → salud | **comprobar plataforma** → pruebas → base → imagen → esquema → service → **listener** → routes → humo (D-025) |
| `deprovision.yml` | service → platform | **routes** → service → base (D-026) |

**Estructura de archivos (v2)**

```text
infra/base/                  (renombre de infra/platform)
  network.tf                 (mod.)  data "aws_ssm_parameter" vpc-id / subredes-privadas; SG en la VPC compartida
  outputs.tf                 (mod.)  subnet_ids = subredes privadas; sin cambios de nombre en el resto
  tests/base.tftest.hcl      (mod.)  override_data de SSM
infra/service/
  main.tf                    (mod.)  remote_state de geoespacial/base.tfstate
  outputs.tf                 (mod.)  service_endpoint (host sin esquema), cluster_name, service_name
infra/routes/                (nuevo) backend geoespacial/routes.tfstate; data SSM api-id / vpc-link-id / api-endpoint
  main.tf                    integraciones HTTP_PROXY por VPC Link + 3 rutas
  variables.tf               express_endpoint, express_listener_arn (validaciones como el ejemplo de la plataforma)
  outputs.tf                 gateway_url, route_keys
  tests/routes.tftest.hcl
scripts/
  buscar-listener-express.sh (nuevo, copiado de la plataforma)
  check-platform.sh          (nuevo) RF-021
  smoke-gateway-geoespacial.sh (nuevo) D-024
  run-schema-task.sh         (mod.)  assignPublicIp=DISABLED
.github/workflows/provision.yml, deprovision.yml (mod.)
infra/INVENTARIO.md, infra/bootstrap/README.md, README.md (mod.)
```

**Rutas del gateway (RF-020)** — integraciones según la guía de la plataforma (§4):

| Ruta pública | Ruta del servicio | `authorization_type` |
|---|---|---|
| `GET /api/v1/geoespacial/reports` | `/api/v1/geospatial/reports` | `NONE` |
| `GET /api/v1/geoespacial/coordinates/{id}` | `/api/v1/geospatial/coordinates/$request.path.id` | `NONE` |
| `POST /api/v1/geoespacial/coordinates` | `/api/v1/geospatial/coordinates` | `AWS_IAM` |

Cada integración: `HTTP_PROXY`, `VPC_LINK` con `vpc-link-id`, `integration_uri` = ARN del listener 443, `payload_format_version = "1.0"`, `tls_config.server_name_to_verify` y `overwrite:header.host` = endpoint del servicio, `overwrite:path` = ruta del servicio. La query string (`lat`, `lon`, `radius`) pasa sin cambios.

**Lo que necesita Reportes** (fuera de alcance, se documenta en el README): en su rol de tarea, `execute-api:Invoke` sobre `<api-execution-arn>/$default/POST/api/v1/geoespacial/coordinates`, y firmar con SigV4 (servicio `execute-api`, `us-east-2`).

## 1. Resumen técnico

La infraestructura se divide en dos stacks de Terraform con estado remoto en S3: **platform** (ECR, roles de ECS, clúster, grupos de seguridad, RDS PostgreSQL 17 + PostGIS, secreto de la aplicación, grupos de logs y la definición de la tarea del esquema) y **service** (el servicio ECS Express Mode, que lee las salidas de platform). El esquema se aplica con una **tarea ECS puntual** que ejecuta `python -m app.db.migrate` con la misma imagen del servicio, dentro de la VPC. El workflow `provision.yml` (push a `main`) encadena pruebas → platform → imagen → esquema → service → comprobación de salud; `deprovision.yml` (manual, con confirmación) quita las protecciones, deja una copia final de la base y destruye service y platform. En el código solo cambian los logs (JSON estructurado), el apagado ordenado y el nuevo módulo de migración; el contrato de la API no se toca.

## 2. Contexto técnico

| Aspecto | Valor |
|---|---|
| Lenguaje / versión | Python 3.13 (sin cambios); HCL de Terraform ≥ 1.10 (bloqueo nativo en S3); YAML de GitHub Actions |
| Dependencias principales | Sin dependencias Python nuevas. Terraform: proveedores `hashicorp/aws ~> 6.0` (debe incluir `aws_ecs_express_gateway_service`) y `hashicorp/random ~> 3.6`. Acciones: `actions/checkout@v4`, `aws-actions/configure-aws-credentials@v4`, `aws-actions/amazon-ecr-login@v2`, `hashicorp/setup-terraform@v3` |
| Almacenamiento | RDS for PostgreSQL 17 + PostGIS, `db.t4g.micro`, gp3 20 GiB (autoscaling hasta 50), Single-AZ, cifrado, backups 7 días, `deletion_protection = true` |
| Estado de Terraform | `s3://urban-alert-tfstate-348364742283`, claves `geoespacial/platform.tfstate` y `geoespacial/service.tfstate`, `use_lockfile = true`, `encrypt = true` |
| Pruebas | `pytest` (unitarias + integración contra PostGIS en compose), `terraform fmt/validate/test` (proveedores simulados), `actionlint`, comprobación de salud contra la URL pública |
| Plataforma objetivo | AWS us-east-2, cuenta 348364742283, VPC predeterminada, ECS Express Mode sobre Fargate (X86_64), 512 CPU / 1024 MiB por tarea, 1–10 tareas |
| Restricciones | Rol OIDC de GitHub solo válido desde `refs/heads/main`; permisos del rol = `github-actions-urban-alertPolicy` + `github-actions-urban-alert-terraform`; ≤ 50 conexiones totales a la base; sin `terraform` ni `aws` instalados en el Mac del usuario |

**Comandos**

```bash
docker compose --profile test run --rm --build tests                 # pruebas Python (local y CI)
terraform -chdir=infra/platform init -backend=false && terraform -chdir=infra/platform validate
terraform -chdir=infra/platform test                                 # pruebas con mock_provider
terraform fmt -check -recursive infra
```

## 3. Verificación contra la constitución

| Principio | ¿Cumple? | Nota / justificación de excepción |
|---|---|---|
| — | n/a | `.sdd/constitution.md` sigue siendo la plantilla sin principios (v0.0.0). Se respetan igualmente las convenciones del plan 001: sin dependencias nuevas sin motivo, SQL explícito, configuración por entorno, sin secretos en el repositorio. |

## 4. Arquitectura y componentes

```text
GitHub (push a main)                                   GitHub (workflow_dispatch + confirmación)
   │ provision.yml                                        │ deprovision.yml
   ▼ OIDC → rol github-actions (credenciales temporales)  ▼
┌──────────── AWS us-east-2 · VPC predeterminada ─────────────────────────────────────┐
│ stack platform (Terraform)                                                          │
│   ECR urban-alert-geoespacial ◄── docker push :<sha>                                │
│   IAM urban-alert-ecs-execution-role (+ lectura de secretos) · ...-infrastructure-role│
│   ECS cluster urban-alert-geoespacial                                               │
│   SG urban-alert-geoespacial-tasks ──5432──► SG urban-alert-geoespacial-rds         │
│   RDS urban-alert-geoespacial-db (PG17+PostGIS, privada, TLS)                       │
│     └ secreto rds!… (usuario maestro, gestionado por RDS)                           │
│   Secreto urban-alert-geoespacial-db {username,password,host,port,dbname,DATABASE_URL}│
│   Logs /ecs/urban-alert-geoespacial · /ecs/urban-alert-geoespacial-schema (30 días) │
│   Task definition urban-alert-geoespacial-schema (imagen :<sha>, python -m app.db.migrate)│
│                                                                                     │
│ paso del workflow: aws ecs run-task (schema) → espera → exit code + logs            │
│                                                                                     │
│ stack service (Terraform, lee platform por terraform_remote_state)                  │
│   ECS Express urban-alert-geoespacial (imagen :<sha>, :8000, /health, 1–10 tareas)  │
│     └ ALB + HTTPS + URL pública (gestionados por Express con el rol de infraestructura)│
└─────────────────────────────────────────────────────────────────────────────────────┘
```

**Componentes**

1. **Código del servicio** (`app/`):
   - `app/observability.py` (nuevo): `configure_logging()` instala un formateador JSON (stdlib) en el logger raíz y en los de uvicorn; `AccessLogMiddleware` registra una línea por petición con `method`, `path`, `status`, `duration_ms`.
   - `app/main.py`: llama a `configure_logging()` y añade el middleware. El `lifespan` ya cierra el pool al apagar.
   - `app/db/migrate.py` (nuevo): punto de entrada `python -m app.db.migrate`. Conecta como usuario maestro (TLS), aplica `db/schema.sql` en una transacción, crea el rol de aplicación si no existe, sincroniza su contraseña y concede `CONNECT`, `USAGE` y `SELECT, INSERT` sobre `coordinates`. Idempotente.
   - `Dockerfile`: copia `db/schema.sql`; `CMD` con `--no-access-log --timeout-graceful-shutdown 20 --proxy-headers --forwarded-allow-ips=*`.
2. **Terraform `infra/platform`**: todos los recursos persistentes y la definición de la tarea del esquema. Variables `image_tag` y `allow_destroy`.
3. **Terraform `infra/service`**: solo el servicio Express. Variables `image_tag`, `db_pool_min`, `db_pool_max`, `min_tasks`, `max_tasks` con una precondición `db_pool_max × max_tasks ≤ 50`.
4. **`scripts/run-schema-task.sh`**: lanza la tarea del esquema con las salidas de platform, espera a que pare, imprime sus logs y devuelve su código de salida.
5. **Workflows**: `provision.yml`, `deprovision.yml` (detalle en §7).
6. **Arranque e inventario**: `infra/bootstrap/` (políticas IAM, confianza OIDC y configuración del bucket en JSON, más un README) e `infra/INVENTARIO.md` (recursos importados y externos).

## 5. Estructura de archivos

```text
app/
  observability.py              (nuevo)  logs JSON + middleware de acceso
  main.py                       (mod.)   configure_logging() + middleware
  db/migrate.py                 (nuevo)  esquema + rol de aplicación, idempotente
Dockerfile                      (mod.)   COPY db/schema.sql; flags de uvicorn
db/schema.sql                   (sin cambios; fuente única del esquema)
scripts/run-schema-task.sh      (nuevo)
tests/unit/test_observability.py        (nuevo)
tests/integration/test_migrate.py       (nuevo)
tests/integration/test_shutdown.py      (nuevo)
infra/
  INVENTARIO.md                 (nuevo)  pseudoinventario: importados + arranque
  bootstrap/
    README.md                   (nuevo)  pasos manuales una sola vez
    github-oidc-trust.json      (nuevo)
    github-deploy-policy.json   (nuevo)  = github-actions-urban-alertPolicy
    github-terraform-policy.json(nuevo)  = github-actions-urban-alert-terraform
    tfstate-bucket-policy.json  (nuevo)
  platform/
    versions.tf  backend.tf  providers.tf  variables.tf  terraform.tfvars
    network.tf   (VPC/subredes predeterminadas por data source, SGs)
    ecr.tf  iam.tf  ecs.tf  rds.tf  secrets.tf  logs.tf  schema_task.tf
    imports.tf   (temporal: se elimina tras la primera importación, D-005)
    outputs.tf
    tests/platform.tftest.hcl
  service/
    versions.tf  backend.tf  providers.tf  variables.tf  terraform.tfvars
    main.tf  outputs.tf
    tests/service.tftest.hcl
.github/workflows/
  provision.yml                 (nuevo)
  deprovision.yml               (nuevo)
README.md                       (mod.)   sección «Despliegue en AWS»
.dockerignore                   (mod.)   excluir infra/ y .github/
```

## 6. Modelo de datos

Sin cambios en la tabla `coordinates`. Cambios de datos solo en la base de la nube:

- **Rol `geospatial_app`** (`DB_APP_USER`): `LOGIN`; `CONNECT` sobre la base, `USAGE` sobre `public`, `SELECT, INSERT` sobre `coordinates`. Sin `UPDATE`, `DELETE` ni DDL.
- **Secreto `urban-alert-geoespacial-db`** (JSON): `username`, `password` (`random_password`, 32 caracteres sin símbolos problemáticos en URL), `host`, `port`, `dbname`, `DATABASE_URL = postgresql://geospatial_app:<pwd>@<host>:5432/geospatial?sslmode=require`.
- **Secreto `rds!…`**: lo crea y rota RDS para el usuario maestro (`postgres`); solo lo lee la tarea del esquema.

## 7. Contratos / interfaces

**API HTTP**: sin cambios (contrato de la spec 001).

**Logs (stdout, una línea JSON por evento)**

```json
{"timestamp":"2026-10-10T18:00:00.123Z","level":"INFO","logger":"app.access","message":"request","method":"GET","path":"/api/v1/geospatial/reports","status":200,"duration_ms":12.4}
```

**`python -m app.db.migrate`** — variables de entorno:

| Variable | Origen en ECS | Uso |
|---|---|---|
| `DB_HOST`, `DB_PORT`, `DB_NAME` | environment | Conexión |
| `DB_ADMIN_USER`, `DB_ADMIN_PASSWORD` | secret `rds!…:username::` / `:password::` | Usuario maestro |
| `DB_APP_USER` | environment (`geospatial_app`) | Rol de la aplicación |
| `DB_APP_PASSWORD` | secret `urban-alert-geoespacial-db:password::` | Contraseña del rol |
| `SCHEMA_PATH` | por defecto `/srv/db/schema.sql` | Fichero de esquema |

Sale con 0 si todo se aplicó (o ya estaba), con ≠ 0 y un log `ERROR` si falla. Conecta siempre con `ssl="require"`.

**Servicio Express** — entorno: `DB_POOL_MIN=1`, `DB_POOL_MAX=5`, `MAX_RADIUS_M=6000`; secreto `DATABASE_URL` = `urban-alert-geoespacial-db:DATABASE_URL::`; `container_port=8000`; `health_check_path=/health`; `scaling_target` por CPU al 60 %, 1–10 tareas.

**Salidas de Terraform** usadas por los workflows: platform → `ecr_repository_url`, `cluster_name`, `schema_task_definition_arn`, `subnet_ids`, `tasks_security_group_id`, `schema_log_group`; service → `service_url`.

**`provision.yml`** (on: `push` a `main`; `concurrency: urban-alert-geoespacial-aws`, sin cancelar)

| Job | Pasos | Necesita |
|---|---|---|
| `test` | checkout → `docker compose --profile test run --rm --build tests` → `terraform fmt -check`, `init -backend=false`, `validate`, `test` (ambos stacks) → `actionlint` | — |
| `provision` | OIDC → `terraform apply` platform (`-var image_tag=$SHA`) → login ECR → build `--target runtime` + push `:$SHA` (si el tag ya existe, se omite) → `scripts/run-schema-task.sh` → `terraform apply` service (`-var image_tag=$SHA`, `wait_for_steady_state`) → `curl` con reintentos a `$service_url/health` (máx. 5 min) → resumen con la URL en `$GITHUB_STEP_SUMMARY` | `test` |

**`deprovision.yml`** (on: `workflow_dispatch` con input `confirm`; misma `concurrency`)

1. Si `inputs.confirm != 'urban-alert-geoespacial'` → falla sin tocar nada.
2. OIDC → `terraform destroy` service.
3. `terraform apply` platform con `-var allow_destroy=true -var final_snapshot_suffix=${{ github.run_id }}` → desactiva `deletion_protection`, fija `skip_final_snapshot=false` y `final_snapshot_identifier`, `force_delete=true` en ECR.
4. `terraform destroy` platform con las mismas variables.
5. Si el estado ya está vacío, `destroy` termina sin cambios (caso borde de la spec).

**Variables y secretos de GitHub (lista definitiva)**: secreto `AWS_ROLE_ARN`; variable `AWS_REGION=us-east-2`. Todo lo demás vive en `terraform.tfvars` o en las salidas de Terraform. Las variables creadas antes (`ECR_REPOSITORY`, `ECS_*`, `DB_POOL_*`, `MAX_RADIUS_M`, `DATABASE_URL_SECRET_ARN`) dejan de usarse y se pueden borrar.

## 8. Decisiones

### D-001: Dos stacks de Terraform (platform y service)
- **Decisión**: `infra/platform` y `infra/service` con estados separados; service lee platform con `terraform_remote_state`.
- **Alternativas consideradas**: un solo stack con `-target` para ordenar; un solo stack con un `null_resource` que lance la tarea del esquema.
- **Motivo**: el esquema debe aplicarse después de crear la base y antes de desplegar la versión nueva (RF-016). Con dos stacks el workflow ejecuta los pasos en ese orden sin `-target` (desaconsejado para uso rutinario) y sin un `null_resource` que, para ejecutarse en cada commit, rompería la idempotencia del plan (RNF-003).

### D-002: El servicio Express lo gestiona Terraform, no la acción de despliegue
- **Decisión**: `aws_ecs_express_gateway_service` en el stack service, con `image_tag` como variable y `wait_for_steady_state = true`.
- **Alternativas consideradas**: `aws-actions/amazon-ecs-deploy-express-service` para el despliegue y Terraform para el resto.
- **Motivo**: RF-010 pide el servicio como código y una sola fuente de verdad; con la acción habría dos herramientas modificando el mismo recurso. Riesgo: el recurso es reciente (ver §10).

### D-003: Esquema con una tarea ECS puntual que usa la imagen del servicio
- **Decisión**: `python -m app.db.migrate` (asyncpg, sin dependencias nuevas) en una task definition propia, lanzada con `aws ecs run-task` en las subredes de la VPC.
- **Alternativas consideradas**: `psql` desde el runner (la base es privada: no llega); runner autoalojado en la VPC; Lambda; imagen aparte con `psql`.
- **Motivo**: es la única opción sin infraestructura extra que llega a la base privada. Reutiliza la imagen ya construida y el SQL de `db/schema.sql`, que sigue siendo la fuente única (RF-008).

### D-004: Platform se aplica antes de publicar la imagen (orden distinto al listado en RF-012)
- **Decisión**: pruebas → platform → imagen → esquema → service → salud.
- **Alternativas consideradas**: imagen → infraestructura, como enumera RF-012.
- **Motivo**: tras un desaprovisionamiento el repositorio ECR no existe y el push fallaría. El cambio de orden no altera lo que pide RF-012 (nada se despliega si fallan las pruebas o el esquema). La task definition del esquema puede registrarse con un tag que aún no existe.

### D-005: Importación con bloques `import` de un solo uso + inventario en Markdown
- **Decisión**: `infra/platform/imports.tf` importa en la primera ejecución el repositorio ECR (y su regla de ciclo de vida, si existe), los dos roles de ECS, sus adjuntos de políticas gestionadas y la política en línea `read-project-secrets` del rol de ejecución (nombre confirmado por el usuario). Tras el primer `apply` correcto se elimina el fichero. `infra/INVENTARIO.md` lista cada recurso con su identificador en AWS, la dirección de Terraform y el bloque `import` para reimportarlo si se pierde el estado; también lista los recursos externos de arranque.
- **Alternativas consideradas**: dejar los bloques `import` permanentes; `terraform import` manual por CLI.
- **Motivo**: un bloque `import` permanente falla después de un desaprovisionamiento (el recurso ya no existe), lo que rompería HU-2 criterio 4. El CLI no deja rastro en el repositorio.

### D-006: Red sobre la VPC predeterminada — **sustituida por D-021 (v2)**
- **Decisión**: subredes predeterminadas (≥ 2 zonas) por `data "aws_subnets"`; tareas con IP pública para llegar a ECR y Secrets Manager; RDS con `publicly_accessible = false` en un subnet group de esas subredes; SG de RDS con entrada 5432 solo desde el SG de las tareas.
- **Alternativas consideradas**: VPC propia con subredes privadas + NAT Gateway (≈ 32 USD/mes) o endpoints de VPC.
- **Motivo**: supuesto de la spec y coste. La base no es accesible desde internet porque no es pública y su SG solo admite al SG de las tareas (HU-3 criterio 2).

### D-007: Credenciales: maestro gestionado por RDS, aplicación con secreto propio
- **Decisión**: `manage_master_user_password = true`; el usuario de la aplicación usa `random_password` guardado en `urban-alert-geoespacial-db` (`recovery_window_in_days = 0` para poder recrearlo tras desaprovisionar). El rol de ejecución lee solo ese secreto y el `rds!…` de esta base.
- **Alternativas consideradas**: usar el usuario maestro en la aplicación; contraseña en variables de GitHub.
- **Motivo**: RF-009 y RNF-001. La contraseña queda en el estado de Terraform, que está cifrado y no es público (riesgo aceptado, §10).

### D-008: TLS con `sslmode=require`
- **Decisión**: `DATABASE_URL` incluye `?sslmode=require`; `migrate.py` usa `ssl="require"`. RDS PG 17 trae `rds.force_ssl = 1` por defecto.
- **Alternativas consideradas**: `verify-full` con el bundle de CA de RDS dentro de la imagen.
- **Motivo**: cifra la conexión y falla si no puede cifrar (RF-002) sin añadir certificados a la imagen. `verify-full` queda como mejora.

### D-009: Logs JSON con la biblioteca estándar
- **Decisión**: formateador JSON propio (~30 líneas) en `app/observability.py`; uvicorn con `--no-access-log` y un middleware propio para la línea por petición.
- **Alternativas consideradas**: `python-json-logger`, `structlog`.
- **Motivo**: RF-004 sin dependencias nuevas. Se aplica también en local (RF-018 no se ve afectado: cambia el formato, no la forma de uso).

### D-010: Apagado ordenado con uvicorn
- **Decisión**: `--timeout-graceful-shutdown 20` (menor que los 30 s de `stopTimeout` de ECS); el `lifespan` cierra el pool.
- **Alternativas consideradas**: manejar `SIGTERM` a mano.
- **Motivo**: uvicorn ya deja de aceptar conexiones, espera las peticiones en curso y ejecuta el `lifespan` al recibir `SIGTERM` (RF-005). El `CMD` en forma exec deja a uvicorn como PID 1.

### D-011: Arquitectura X86_64
- **Decisión**: imagen `linux/amd64` construida en `ubuntu-latest`.
- **Alternativas consideradas**: ARM64 (Graviton, más barato).
- **Motivo**: `aws_ecs_express_gateway_service` no expone la arquitectura (Express usa X86_64 por defecto) y el runner es amd64, así que no hace falta emulación.

### D-012: Desaprovisionamiento en tres pasos con confirmación por input
- **Decisión**: ver §7. La copia final se llama `urban-alert-geoespacial-final-<run_id>`.
- **Alternativas consideradas**: GitHub *environments* con aprobación manual; `destroy` directo.
- **Motivo**: `deletion_protection` y `skip_final_snapshot` deben cambiar en el estado antes del `destroy` (RF-013b). Un *environment* cambiaría el `sub` del token OIDC a `environment:<nombre>` y obligaría a tocar la confianza del rol (D-013).

### D-013: Sin GitHub environments; un grupo de concurrencia común
- **Decisión**: ambos workflows usan `concurrency: { group: urban-alert-geoespacial-aws, cancel-in-progress: false }` y no declaran `environment`.
- **Motivo**: RF-015 y mantener válida la relación de confianza actual (`ref:refs/heads/main`). El desaprovisionamiento debe lanzarse sobre `main`.

### D-014: Pruebas en CI con el mismo compose que en local
- **Decisión**: el job `test` ejecuta `docker compose --profile test run --rm --build tests`.
- **Alternativas consideradas**: `services:` de GitHub Actions con `postgis/postgis`.
- **Motivo**: una sola forma de ejecutar las pruebas; la imagen de BD del repo ya incluye la base `geospatial_test`.

### D-015: Presupuesto de conexiones validado por Terraform
- **Decisión**: service usa `DB_POOL_MIN=1`, `DB_POOL_MAX=5`, `max_tasks=10` y una `precondition` que falla si `db_pool_max × max_tasks > 50`. La tarea del esquema abre 1 conexión puntual.
- **Motivo**: RF-003 / RNF-002 comprobables antes de desplegar. `db.t4g.micro` admite ~80 conexiones, así que hay margen para la tarea del esquema y el usuario maestro.

### D-016: Tamaños mínimos
- **Decisión**: RDS `db.t4g.micro`, gp3 20 GiB (máx. 50), Single-AZ; tareas 512 CPU / 1024 MiB; logs con retención de 30 días; ECR conserva 20 imágenes.
- **Motivo**: RNF-006. Coste aproximado con el entorno encendido: ALB ~16–20 USD/mes + RDS micro + Fargate de 1 tarea. Desaprovisionar cuando no se use.

### D-017: Versiones fijadas
- **Decisión**: `required_version = ">= 1.10, < 2.0"`; el workflow fija la versión exacta de Terraform (la última 1.x estable en el momento de implementar); `.terraform.lock.hcl` versionado.
- **Motivo**: builds reproducibles y `use_lockfile`.

### D-018: Configuración no secreta en el código
- **Decisión**: el nombre del bucket de estado, región, nombres de recursos y tamaños van en `backend.tf` / `terraform.tfvars`; GitHub solo guarda `AWS_ROLE_ARN` y `AWS_REGION`.
- **Motivo**: nada de eso es secreto y así queda versionado y revisable (HU-5).

### D-019: Clúster ECS propio del servicio
- **Decisión**: `aws_ecs_cluster "urban-alert-geoespacial"` en platform.
- **Alternativas consideradas**: clúster `default`.
- **Motivo**: la tarea del esquema se lanza antes de que exista el servicio; en una cuenta limpia el clúster `default` puede no existir todavía. Además, el desaprovisionamiento no afecta a otros servicios.

### D-020: Tercer stack `routes` y renombre de `platform` a `base` (v2)
- **Decisión**: `infra/routes` con estado propio (`geoespacial/routes.tfstate`) para las integraciones y rutas del gateway. `infra/platform` pasa a `infra/base` (estado `geoespacial/base.tfstate`; nada se había aplicado, no hay migración de estado).
- **Alternativas consideradas**: rutas dentro de `service` aplicadas en dos fases (`-target`); un solo `apply` con `data` del listener.
- **Motivo**: el ARN del listener del ALB de Express solo existe después de desplegar el servicio y no lo exponen ni Terraform ni la API de Express (guía §3); un stack aparte respeta ese orden sin `-target`. El renombre evita confundir el stack del servicio con la plataforma compartida.

### D-021: Red de la plataforma leída de SSM (sustituye a D-006)
- **Decisión**: `data "aws_ssm_parameter"` de `vpc-id` y `subredes-privadas` en `base`; RDS (subnet group), SG de tareas y de RDS en esa VPC; `service` y la tarea del esquema usan **todas** las subredes privadas (las salidas de `base`).
- **Alternativas consideradas**: copiar los IDs a `terraform.tfvars` (prohibido por la guía §1); `terraform_remote_state` del estado de la plataforma.
- **Motivo**: RF-019 y el contrato de la plataforma (su D-006). Si la plataforma se recrea, el siguiente `plan` toma los IDs nuevos.

### D-022: Tarea del esquema sin IP pública
- **Decisión**: `run-schema-task.sh` con `assignPublicIp=DISABLED`; sale a ECR/Secrets Manager/CloudWatch por el NAT de la plataforma.
- **Motivo**: RF-019 y guía §2.

### D-023: Rutas como en el ejemplo de consumidor de la plataforma
- **Decisión**: copiar el patrón de `infra/ejemplo-consumidor/main.tf` (validado por el CI de la plataforma), sin `iam.tf`: la política de invocación pertenece al stack de Reportes. `express_endpoint` se calcula quitando el esquema de la salida de `service`; `express_listener_arn` con `buscar-listener-express.sh` (copiado sin cambios).
- **Alternativas consideradas**: referenciar el ejemplo como módulo por git (repo privado; descartado por la plataforma en su D-010).
- **Motivo**: RF-020 con la configuración ya verificada (Host, TLS, payload 1.0).

### D-024: Prueba de humo por el gateway
- **Decisión**: `smoke-gateway-geoespacial.sh <api-endpoint>`: `GET /api/v1/geoespacial/reports?lat=4.6486&lon=-74.0628&radius=1000` → 200 con un array JSON; `GET /api/v1/geoespacial/coordinates/<uuid aleatorio>` → 404 del servicio (cuerpo `{code:404,…}`); `POST /api/v1/geoespacial/coordinates` sin firma → 403; `GET /api/v1/geoespacial/health` → 404. Reintentos durante 5 min solo en la primera comprobación.
- **Alternativas consideradas**: probar `POST` firmado desde el runner (el rol de GitHub no debe tener `execute-api:Invoke`: queda para la verificación manual).
- **Motivo**: HU-6 criterios 1, 2, 3 y 6 automáticos en cada despliegue; el criterio 4 (firmado) y MS-002 completo se verifican en `/sdd-verify`.

### D-025: Comprobación de la plataforma antes de tocar nada
- **Decisión**: primer paso del job `provision` (tras obtener credenciales): `check-platform.sh` lee los 9 parámetros de `/urban-alert/plataforma/`; si falta alguno, falla con «la plataforma compartida no está aprovisionada (urban-alert-plataforma)».
- **Motivo**: RF-021; sin esto el error saldría a mitad del `plan` de `base`.

### D-026: Desaprovisionamiento en orden inverso, sin tocar la plataforma
- **Decisión**: `routes` destroy → `service` destroy → `base` (allow_destroy) apply → `base` destroy. `routes` recibe valores de relleno válidos en sus dos variables al destruir (no se usan para borrar).
- **Motivo**: RF-013b v2 y guía §9: las rutas se eliminan antes que el servicio, y la plataforma detecta consumidores si quedan recursos en su VPC.

### D-027: Política del rol de GitHub sin cambios
- **Decisión**: no se añade ninguna política: `github-actions-urban-alert-platform` ya cubre `apigateway` sobre `/apis/*`, la lectura de SSM y `elasticloadbalancing:Describe*`; `ecs:DescribeServices` está en la de despliegue.
- **Motivo**: guía §8. Si el primer `apply` encuentra un `AccessDenied`, se corrige en el JSON versionado de bootstrap correspondiente.

## 9. Estrategia de pruebas

| Nivel | Qué | Cómo |
|---|---|---|
| Unitario | Formateador JSON (campos `timestamp`, `level`, `logger`, `message`, extras; JSON válido; excepciones serializadas); middleware de acceso (una línea con `method`, `path`, `status`, `duration_ms`) | `tests/unit/test_observability.py` con una app FastAPI mínima y `caplog`/handler en memoria |
| Integración | `migrate`: aplica el esquema sobre `geospatial_test`, segunda ejecución sin errores ni cambios; el rol de aplicación puede `SELECT`/`INSERT` y no puede `UPDATE`/`DELETE`/`DROP`; cambio de contraseña se sincroniza | `tests/integration/test_migrate.py` (en compose; el usuario de pruebas es superusuario) |
| Integración | Apagado: uvicorn en subproceso contra `geospatial_test`; petición en curso + `SIGTERM` → la petición termina con 200, el proceso sale con 0 en < 25 s y el log contiene el cierre del pool | `tests/integration/test_shutdown.py` |
| Regresión | Todas las pruebas de la spec 001 siguen pasando | `docker compose --profile test run --rm --build tests` |
| Terraform estático | Formato, validez, proveedores resueltos | `terraform fmt -check -recursive infra`; `init -backend=false && validate` en cada stack |
| Terraform lógico | Precondición de conexiones (5×10 pasa, 6×10 falla); `deletion_protection` true por defecto y false con `allow_destroy`; RDS `publicly_accessible=false`, `storage_encrypted=true`, `backup_retention_period>=7`; SG de RDS solo con origen el SG de tareas | `terraform test` con `mock_provider "aws"` en `infra/*/tests/*.tftest.hcl` |
| Workflows | Sintaxis y expresiones | `actionlint` (contenedor `rhysd/actionlint`) en el job `test` |
| Rutas (v2) | Exactamente 3 rutas con las claves de RF-020; `POST` con `AWS_IAM` y los `GET` con `NONE`; ninguna `$default`; cada integración con `VPC_LINK`, payload 1.0, `overwrite:header.host` y `server_name_to_verify` = endpoint, `overwrite:path` correcto; validación de `express_endpoint`/`express_listener_arn` | `terraform test` en `infra/routes` (mock + override_data de SSM) |
| Red (v2) | RDS y SG en la VPC de SSM; subnet group = subredes privadas de SSM | `terraform test` en `infra/base` |
| Despliegue (e2e) | Humo por el gateway (D-024) | Último paso de `provision.yml` |
| Verificación manual | MS-002 (contrato completo contra la URL, con un `reportId` aleatorio), MS-003 (segundo `provision` sin cambios), MS-004 (búsqueda de secretos), HU-2 (desaprovisionar y volver a aprovisionar), conexión a RDS desde fuera rechazada | `/sdd-verify` |

## 10. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| El primer `plan`/`apply` real solo puede ocurrir en `main` (la confianza OIDC exige `main` y no hay `terraform`/`aws` en local) | Errores de IAM o de configuración se descubren tras el merge | Decisión del usuario: Terraform se ejecuta solo desde GitHub Actions (sin `plan` local). Todo lo verificable sin credenciales corre en el job `test`; los fallos del primer apply se corrigen con commits pequeños a `main`. |
| `aws_ecs_express_gateway_service` es reciente (nov. 2025): posibles bugs o diferencias en el proveedor | El stack service no aplica | `wait_for_steady_state`; fijar la versión del proveedor; plan B documentado: desplegar con `amazon-ecs-deploy-express-service` y dejar el resto en Terraform (revierte D-002). |
| Permisos IAM insuficientes (p. ej. KMS al crear el secreto maestro, capacity providers del clúster) | `AccessDenied` en el primer apply | Mensajes de error claros en el log; añadir la acción concreta a `github-terraform-policy.json` (versionada en `infra/bootstrap/`) y aplicarla a mano. |
| Las políticas en línea reales de los roles importados no coinciden con el código (nombres desconocidos) | El primer plan muestra cambios o falla la importación | T de inventario: el usuario lista `aws iam list-role-policies` / consola y se ajustan `imports.tf` e `INVENTARIO.md` antes del primer apply. |
| Tareas sin salida a internet en la VPC predeterminada | `ResourceInitializationError` al descargar la imagen | `assignPublicIp=ENABLED` en la tarea del esquema; Express en subredes públicas. Si falla: endpoints de VPC para ECR/Secrets Manager/Logs. |
| Creación de RDS tarda 5–15 min en el primer aprovisionamiento | El primer `provision` supera los 20 min | RNF-005 excluye los cambios de base; timeouts de Terraform por defecto (40 min). |
| La contraseña de la aplicación queda en el estado de Terraform | Quien lea el bucket la ve | Bucket privado, cifrado, sin acceso público y con TLS obligatorio; solo el rol de GitHub y administradores leen el estado. |
| Las copias finales se acumulan tras cada desaprovisionamiento | Coste de almacenamiento | Documentar cómo borrarlas; nombre con `run_id` para identificarlas. |
| Coste del entorno encendido (ALB, RDS, Fargate) | Gasto mensual | Tamaños mínimos (D-016) y flujo de desaprovisionamiento. |
| El ALB interno de Express es alcanzable desde otras tareas de la VPC (plataforma D-013) | Otra tarea de la VPC podría llamar a `POST` sin pasar por la firma del gateway | Aceptado por el usuario en la plataforma; documentado. Mitigación futura: validar en el servicio una cabecera fija inyectada por el gateway |
| Primer servicio Express de la VPC fija las zonas del ALB compartido | Si se usan menos zonas, otros servicios fallan | Usar siempre todas las subredes privadas (D-021) |
| La plataforma se desaprovisiona con el servicio desplegado | Su Deprovision se niega (detecta dependientes) | Orden documentado: primero el Deprovision de cada microservicio |
| Secretos con ventana de recuperación impiden recrear el nombre | El reaprovisionamiento falla | `recovery_window_in_days = 0` en el secreto de la aplicación; el `rds!…` lo borra RDS con la instancia. |

## 11. Trazabilidad

| Requisito | Componentes | Pruebas |
|---|---|---|
| RF-001 Config por entorno, secreto | `config.py` (sin cambios), `service/main.tf` (`secret DATABASE_URL`), `secrets.tf` | `service.tftest.hcl`; MS-004 en verify |
| RF-002 TLS obligatorio | `secrets.tf` (`sslmode=require`), `migrate.py` (`ssl="require"`), RDS `force_ssl` por defecto | `test_migrate.py` (parámetro ssl), verify: conexión sin TLS rechazada |
| RF-003 Pool ≤ 50 | `service/variables.tf` + precondición (D-015) | `service.tftest.hcl` (5×10 ok, 6×10 falla) |
| RF-004 Logs estructurados | `observability.py`, `main.py`, `Dockerfile --no-access-log` | `test_observability.py`; verify en CloudWatch |
| RF-005 Apagado ordenado | `Dockerfile` (D-010), `main.py` lifespan | `test_shutdown.py` |
| RF-006 Imagen: 8000, /health, no root, arquitectura | `Dockerfile`, `service/main.tf` | Paso de salud de `provision.yml`; revisión del Dockerfile |
| RF-007 Tag = commit | `provision.yml` (`:${{ github.sha }}`), ECR inmutable | Verify: tag del servicio = SHA desplegado |
| RF-008 Esquema solo de `schema.sql`, idempotente, sin seed | `migrate.py`, `Dockerfile` (COPY), `schema_task.tf` | `test_migrate.py` (dos ejecuciones) |
| RF-009 Usuario con SELECT/INSERT | `migrate.py`, `secrets.tf` | `test_migrate.py` (privilegios) |
| RF-010 Infra como código | `infra/platform/*`, `infra/service/*` | `terraform validate/test`; MS-003 |
| RF-010b Importación + inventario | `imports.tf` (temporal), `INVENTARIO.md` | Primer apply sin recrear ECR ni roles (verify: ARN/fecha de creación sin cambios) |
| RF-010c Arranque fuera de Terraform | `INVENTARIO.md`, `infra/bootstrap/` | Revisión: ningún recurso de arranque en el código; HU-2 criterio 5 |
| RF-011 Estado remoto cifrado con bloqueo | `backend.tf` (S3, `encrypt`, `use_lockfile`) | Verify: objetos `.tfstate` y `.tflock` en el bucket |
| RF-012 Flujo de aprovisionamiento | `provision.yml` (orden D-004) | Ejecución en `main`; prueba de pruebas fallidas → sin apply |
| RF-013 / RF-013b Desaprovisionamiento | `deprovision.yml`, `allow_destroy`, `final_snapshot_identifier`, `force_delete` | `platform.tftest.hcl` (allow_destroy); verify HU-2 |
| RF-014 OIDC sin claves | `configure-aws-credentials` con `role-to-assume` | Revisión de workflows: sin `aws-access-key-id` |
| RF-015 Sin ejecuciones simultáneas | `concurrency` (D-013) | Revisión de workflows |
| RF-016 Esquema en cada aprovisionamiento | `scripts/run-schema-task.sh`, paso de `provision.yml` | Ejecución: el paso corre en cada push; fallo → no se aplica service |
| RF-017 Documentación | `README.md`, `infra/bootstrap/README.md`, `INVENTARIO.md` | Revisión en verify (HU-5) |
| RF-018 Local sin cambios | `compose.yaml` intacto | `docker compose up -d --build --wait` + suite completa |
| RF-019 Red privada compartida | `base/network.tf` (SSM), `service/main.tf`, `run-schema-task.sh` (D-021, D-022) | `base.tftest.hcl`; verify: ALB interno, tareas sin IP pública |
| RF-020 Rutas del gateway | `infra/routes/*` (D-023), `buscar-listener-express.sh` | `routes.tftest.hcl`; humo D-024; verify: POST firmado |
| RF-021 Falla sin plataforma | `scripts/check-platform.sh` (D-025) | Prueba del script con parámetro inexistente (prefijo de prueba) |
| RNF-001 Seguridad | D-006, D-007, `.dockerignore`, `::add-mask::` no necesario (no se imprimen secretos) | Verify MS-004; `platform.tftest.hcl` (SG, público=false) |
| RNF-002 Conexiones ≤ 50 | D-015 | `service.tftest.hcl` |
| RNF-003 Idempotencia | Dos stacks sin recursos que cambien en cada ejecución (D-001) | MS-003 en verify |
| RNF-004 Sin caída en despliegue | Express (rolling + ALB), `/health` con BD | Verify: `curl` en bucle durante un despliegue |
| RNF-005 < 20 min | Jobs en paralelo donde se pueda; caché de capas Docker | Duración de la ejecución en verify |
| RNF-006 Coste mínimo | D-016 | Revisión de `terraform.tfvars` |
| RNF-007 Backups y protección | `rds.tf` (`backup_retention_period=7`, `deletion_protection`) | `platform.tftest.hcl` |

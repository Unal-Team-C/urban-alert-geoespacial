# UrbanAlert — Servicio Geoespacial

Microservicio de UrbanAlert que registra la ubicación de cada reporte de daño urbano y responde qué reportes hay cerca de un punto del mapa. Está hecho con **Python 3.13 + FastAPI** y usa una base **PostgreSQL + PostGIS** propia. Se ejecuta en local con contenedores y se despliega en AWS (ECS Express Mode + RDS) con GitHub Actions y Terraform; no usa cola de mensajes.

- Especificación, plan, tareas y verificación (desarrollado con SDD): [docs/](docs/) — [spec](docs/spec.md) · [plan](docs/plan.md) · [verify](docs/verify.md)
- Documentación interactiva (OpenAPI), con el servicio arriba: <http://localhost:8000/docs>
- Migración a AWS (spec 002): [specs/002-migracion-aws/](specs/002-migracion-aws/) — ver [Despliegue en AWS](#despliegue-en-aws)

## Requisitos

Un runtime de contenedores con Compose. En este equipo se usa **Podman** + `docker-compose`:

```bash
podman machine init        # solo la primera vez
podman machine start       # tras cada reinicio del equipo
brew install docker-compose
```

> **Si `docker-compose` falla con `docker-credential-desktop: executable file not found`**: `~/.docker/config.json` todavía apunta a un Docker Desktop desinstalado (`"credsStore": "desktop"`). Quita esa línea o usa una configuración vacía solo para este proyecto:
>
> ```bash
> mkdir -p ~/.docker-podman && echo '{}' > ~/.docker-podman/config.json
> export DOCKER_CONFIG=~/.docker-podman
> ```

En los ejemplos, `docker compose` y `docker-compose` son equivalentes; también funciona `podman compose`.

## Arranque

Todos los comandos se ejecutan desde esta carpeta (`backend/UrbanAlert.Geoespacial`).

```bash
cp .env.example .env              # valores locales; .env no se versiona
docker-compose up -d --build --wait
```

Levanta dos servicios:

| Servicio | Puerto en el host | Descripción |
|---|---|---|
| `db` | 5433 | PostgreSQL 17 + PostGIS 3. Bases `geospatial` (con datos semilla: 31 puntos de demo y 20 000 sintéticos) y `geospatial_test` (vacía, para las pruebas) |
| `api` | 8000 | El servicio. Su healthcheck consulta `/health` |

El esquema y los datos semilla se cargan **solo cuando el volumen está vacío**. Para reaplicarlos después de cambiar `db/schema.sql` o `db/seed.sql`:

```bash
docker-compose down -v && docker-compose up -d --build --wait
```

## Endpoints

Los nombres y valores del contrato están en inglés y el JSON en camelCase. Todos los errores tienen la forma `{"code": <int>, "message": <str>, "details"?: [...]}`.

### Asignar localización (la llama Reportes de forma síncrona)

```bash
curl -i -X POST localhost:8000/api/v1/geospatial/coordinates \
  -H 'Content-Type: application/json' \
  -d '{"reportId": "7d4a3c1e-2b5f-4e8a-9c0d-1f2e3a4b5c6d", "coordinate": {"lat": 4.6512, "lon": -74.0561}}'
```

| Código | Cuándo |
|---|---|
| `201` | Asignación nueva. Cuerpo `LocationAssigned` `{coordinateId, reportId, coordinate}` y cabecera `Location` |
| `200` | Repetición idéntica (p. ej. un reintento): mismo `coordinateId` |
| `400` | `reportId` no es UUID, o la coordenada falta, está mal formada o cae fuera de Bogotá |
| `409` | El reporte ya tiene **otra** coordenada; se conserva la original |
| `503` | Base de datos no disponible |

**Para el servicio de Reportes:**
- Configura un timeout corto en esta llamada.
- Trata `200` igual que `201`, porque la asignación ya existía.
- Trata `409` y `503` como fallos de la creación del reporte.

### Reportes cercanos a un punto (mapa)

```bash
curl "localhost:8000/api/v1/geospatial/reports?lat=4.6486&lon=-74.0628&radius=1000"
```

- `radius` está en metros, con `0 < radius ≤ 6000` (configurable con `MAX_RADIUS_M`). El límite es inclusivo.
- Devuelve `[{reportId, coordinateId, coordinate}]`, ordenado del más cercano al más lejano. Una zona sin reportes devuelve `[]`.
- Responde `400` si los parámetros son inválidos o el punto está fuera de Bogotá, y `503` si la base no está disponible.

### Resolver una coordenada por su id

```bash
curl localhost:8000/api/v1/geospatial/coordinates/<coordinateId>
```

Responde `200` con `LocationAssigned`, `404` si no existe, `400` si el id no es un UUID y `503` si la base no está disponible.

### Salud

```bash
curl localhost:8000/health    # 200 {"status":"ok"} | 503 {"status":"unavailable"}
```

## Configuración

Las variables se toman de `.env` (ver [.env.example](.env.example)). Si una variable no existe, se usa el valor por defecto de [compose.yaml](compose.yaml).

| Variable | Defecto | Uso |
|---|---|---|
| `DATABASE_URL` | `postgresql://geospatial:geospatial@db:5432/geospatial` | Conexión a la base |
| `DB_POOL_MIN` / `DB_POOL_MAX` | `5` / `50` | Pool de conexiones (máximo 50, RNF-002) |
| `MAX_RADIUS_M` | `6000` | Radio máximo de consulta en metros |
| `BOGOTA_MIN_LAT` / `BOGOTA_MAX_LAT` | `3.72` / `4.84` | Recuadro de Bogotá: Distrito Capital incluido Sumapaz |
| `BOGOTA_MIN_LON` / `BOGOTA_MAX_LON` | `-74.46` / `-73.98` | |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | `geospatial` | Credenciales del contenedor de BD (solo para uso local) |

## Pruebas

Las pruebas corren dentro de un contenedor contra la base `geospatial_test`, que se vacía antes de cada prueba de integración. No tocan los datos semilla.

```bash
docker-compose --profile test run --rm --build tests                     # unitarias + integración
docker-compose --profile test run --rm --build tests pytest tests/unit   # solo unitarias (sin BD)
```

Prueba de carga de la consulta de cercanía (RNF-001). Se ejecuta con el servicio arriba.

Un solo proceso generador satura su propia CPU por encima de unas 25 peticiones concurrentes, así que las 50 concurrentes se miden con 5 generadores de 10 en paralelo. Solo el primero recibe `--db-url`, para muestrear las conexiones a la base:

```bash
for seed in 1 2 3 4 5; do
  docker-compose --profile test run --rm tests python -m tests.perf.load_nearby \
    --concurrency 10 --requests 1000 --seed $seed \
    $([ $seed = 1 ] && echo --db-url postgresql://geospatial:geospatial@db:5432/geospatial) &
done; wait
```

Referencia local (Podman, 5 CPU compartidas, 20 031 puntos, media de ~1 000 reportes por respuesta):

| Concurrencia | p95 | Throughput | Errores | Conexiones máximas |
|---|---|---|---|---|
| 50 | ~140 ms | ~985 req/s | 0 | 50 |

## Escalado (ECS)

El despliegue objetivo es AWS ECS con autoscaling de tareas: cada tarea ejecuta un proceso uvicorn, y para tener varios procesos por tarea uvicorn lee `WEB_CONCURRENCY`. El límite de **50 conexiones a la base es un presupuesto total**:

```
DB_POOL_MAX × procesos por tarea × número máximo de tareas ≤ 50
```

En AWS se usa `DB_POOL_MAX=5` con un máximo de 10 tareas, y Terraform rechaza cualquier combinación que supere 50. Si no cabe, hay que poner RDS Proxy delante (ver [plan D-013](docs/plan.md)).

## Despliegue en AWS

Cuenta `348364742283`, región `us-east-2`. Todo lo que no es de arranque está en Terraform ([infra/](infra/)) y se aplica solo desde GitHub Actions.

```text
push a main ─► Provision: pruebas ─► Terraform platform ─► imagen :<sha> en ECR ─► tarea ECS del esquema ─► Terraform service ─► /health
                                     (ECR, roles, red, RDS,                         (db/schema.sql +       (ECS Express Mode:
                                      secreto, logs, clúster)                        rol geospatial_app)     ALB + HTTPS + autoscaling)
```

| Pieza | Dónde |
|---|---|
| Base de datos | RDS PostgreSQL 17 + PostGIS, `db.t4g.micro`, privada, cifrada, TLS obligatorio, backups 7 días, protección contra borrado. Solo el esquema, sin datos semilla. |
| Servicio | ECS Express Mode (Fargate, X86_64), 0,5 vCPU / 1 GiB, 1–10 tareas por CPU al 60 %. URL pública HTTPS: en el resumen de cada ejecución de *Provision* |
| Credenciales | La aplicación usa el rol `geospatial_app` (solo `SELECT`, `INSERT`); su `DATABASE_URL` está en Secrets Manager (`urban-alert-geoespacial-db`). El usuario maestro lo gestiona RDS. |
| Logs | CloudWatch: `/ecs/urban-alert-geoespacial` (servicio, JSON por línea) y `/ecs/urban-alert-geoespacial-schema` (migraciones), 30 días |
| Estado de Terraform | `s3://urban-alert-tfstate-348364742283/geoespacial/{platform,service}.tfstate` |

### Antes del primer despliegue (una sola vez)

1. Crear los recursos de arranque: proveedor OIDC de GitHub, rol de los workflows con sus dos políticas y bucket del estado. Pasos y JSON en [infra/bootstrap/README.md](infra/bootstrap/README.md).
2. En GitHub → Settings → Secrets and variables → Actions:

   | Tipo | Nombre | Ejemplo |
   |---|---|---|
   | Secreto | `AWS_ROLE_ARN` | `arn:aws:iam::348364742283:role/github-actions-…` |
   | Variable | `AWS_REGION` | `us-east-2` |

   No hace falta nada más: nombres, tamaños y el bucket del estado están en `infra/*/terraform.tfvars` y `backend.tf`.

Los recursos que se crearon a mano antes del código (ECR y roles de ECS) se importan a Terraform; la lista, con sus identificadores, está en [infra/INVENTARIO.md](infra/INVENTARIO.md).

### Workflows

| Workflow | Cuándo | Qué hace |
|---|---|---|
| [Provision](.github/workflows/provision.yml) | Cada push a `main` | Pruebas (Python, `terraform fmt/validate/test`, actionlint) → aplica `infra/platform` → construye y sube la imagen con el SHA del commit → aplica `db/schema.sql` con una tarea ECS dentro de la VPC → aplica `infra/service` → comprueba `/health`. Si un paso falla, los siguientes no se ejecutan. |
| [Deprovision](.github/workflows/deprovision.yml) | A mano: Actions → Deprovision → Run workflow (rama `main`), escribiendo `urban-alert-geoespacial` | Destruye el servicio, quita la protección de la base, deja una copia final `urban-alert-geoespacial-final-<run_id>` y destruye la plataforma. No toca los recursos de arranque. |

Los dos comparten un grupo de concurrencia: nunca se ejecutan a la vez. El rol de AWS solo confía en `main`, así que desde otras ramas no obtienen credenciales.

### Costes y desaprovisionamiento

Con el entorno encendido, el coste aproximado es el balanceador (~16–20 USD/mes), la instancia `db.t4g.micro` y una tarea Fargate. Cuando no se use, lanzar **Deprovision**; un nuevo push a `main` recrea todo con la base vacía.

- **Restaurar la copia final**: RDS → Snapshots → `urban-alert-geoespacial-final-<run_id>` → Restore. La instancia restaurada queda fuera de Terraform; para volver a gestionarla hay que importarla en lugar de la nueva.
- **Borrar copias antiguas** (cuestan almacenamiento):

  ```bash
  aws rds describe-db-snapshots --snapshot-type manual --query "DBSnapshots[?starts_with(DBSnapshotIdentifier,'urban-alert-geoespacial-final-')].DBSnapshotIdentifier"
  aws rds delete-db-snapshot --db-snapshot-identifier urban-alert-geoespacial-final-<run_id>
  ```

### Validar Terraform en local (sin credenciales)

No hace falta instalar Terraform: con Podman,

```bash
podman run --rm -v "$PWD":/w -w /w docker.io/hashicorp/terraform:1.16.5 -chdir=infra/platform init -backend=false
podman run --rm -v "$PWD":/w -w /w docker.io/hashicorp/terraform:1.16.5 -chdir=infra/platform test
```

## Desarrollo con SDD

Este repositorio se desarrolla con **desarrollo guiado por especificaciones (SDD)** usando Claude Code y un arnés con persistencia en disco. La especificación original del servicio está en [docs/](docs/); las features nuevas van en `specs/NNN-nombre/`.

- Guía de uso (primeros pasos y comandos `/sdd-*`): [.sdd/GUIA.md](.sdd/GUIA.md)
- Referencia técnica del arnés: [.sdd/README.md](.sdd/README.md) · Protocolo: [.sdd/PROTOCOL.md](.sdd/PROTOCOL.md)

## Estructura

```text
app/            servicio FastAPI (api/, domain/, db/, config.py, main.py)
db/             Dockerfile de la BD, schema.sql, seed.sql, init/01_init.sh
tests/          unit/, integration/, perf/ (+ test_migrate, test_shutdown)
compose.yaml    servicios db, api y tests (perfil "test")
infra/          Terraform: platform/, service/, bootstrap/ (arranque manual), INVENTARIO.md
scripts/        run-schema-task.sh (tarea ECS del esquema)
.github/        workflows provision.yml y deprovision.yml
docs/           spec, plan, tareas y verificación originales del servicio
specs/          features SDD nuevas (spec.md · plan.md · tasks.md · verify.md)
.sdd/ .claude/  arnés SDD: estado, journal, protocolo, hooks y comandos
```

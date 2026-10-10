# UrbanAlert — Servicio Geoespacial

Microservicio de UrbanAlert que registra la ubicación de cada reporte de daño urbano y responde qué reportes hay cerca de un punto del mapa. Está hecho con **Python 3.13 + FastAPI** y usa una base **PostgreSQL + PostGIS** propia. Esta versión se ejecuta en local con contenedores y no usa cola de mensajes.

- Especificación, plan, tareas y verificación (desarrollado con SDD): [docs/](docs/) — [spec](docs/spec.md) · [plan](docs/plan.md) · [verify](docs/verify.md)
- Documentación interactiva (OpenAPI), con el servicio arriba: <http://localhost:8000/docs>

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

Por ejemplo, `DB_POOL_MAX=5` con un máximo de 10 tareas. Si no cabe, hay que poner RDS Proxy delante (ver [plan D-013](docs/plan.md)).

## Desarrollo con SDD

Este repositorio se desarrolla con **desarrollo guiado por especificaciones (SDD)** usando Claude Code y un arnés con persistencia en disco. La especificación original del servicio está en [docs/](docs/); las features nuevas van en `specs/NNN-nombre/`.

- Guía de uso (primeros pasos y comandos `/sdd-*`): [.sdd/GUIA.md](.sdd/GUIA.md)
- Referencia técnica del arnés: [.sdd/README.md](.sdd/README.md) · Protocolo: [.sdd/PROTOCOL.md](.sdd/PROTOCOL.md)

## Estructura

```text
app/            servicio FastAPI (api/, domain/, db/, config.py, main.py)
db/             Dockerfile de la BD, schema.sql, seed.sql, init/01_init.sh
tests/          unit/, integration/, perf/
compose.yaml    servicios db, api y tests (perfil "test")
docs/           spec, plan, tareas y verificación originales del servicio
specs/          features SDD nuevas (spec.md · plan.md · tasks.md · verify.md)
.sdd/ .claude/  arnés SDD: estado, journal, protocolo, hooks y comandos
```

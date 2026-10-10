# Plan técnico: Servicio Geoespacial

- **Spec**: ./spec.md
- **Estado**: aprobado
- **Fecha**: 2026-10-01

## 1. Resumen técnico

Microservicio HTTP en **Python + FastAPI** con una base **PostgreSQL + PostGIS** propia, levantados juntos con **Docker Compose** en local. El servicio expone tres operaciones:

- **Asignar localización** (síncrona, la invoca Reportes).
- **Consultar reportes cercanos** a un punto, con radio ≤ 6000 m configurable.
- **Resolver una coordenada** por su id.

Además expone un indicador de salud. La validación de entrada la hace Pydantic, y los errores se normalizan a `{code, message}` con 400. El acceso a datos usa SQL parametrizado con `asyncpg` y un pool acotado a 50 conexiones. Las consultas de cercanía usan `ST_DWithin` sobre `geography` con índice GiST. Esta versión no tiene cola de mensajes ni autenticación.

## 2. Contexto técnico

| Aspecto | Valor |
|---|---|
| Lenguaje / versión | Python 3.13 en el contenedor (`python:3.13-slim`). En local hay 3.14; el entorno de referencia es el contenedor. |
| Dependencias principales | `fastapi`, `uvicorn[standard]`, `asyncpg`. Pydantic v2 viene con FastAPI. Se fija la última versión estable de cada una al implementar, en `requirements.txt`. |
| Dependencias de desarrollo | `pytest`, `pytest-asyncio`, `httpx` (cliente de pruebas y script de carga), en `requirements-dev.txt`. |
| Almacenamiento | PostgreSQL 17 + PostGIS 3 (imagen propia `db/Dockerfile` sobre `postgres:17`, ver D-010), base `geospatial`; base `geospatial_test` para pruebas de integración. |
| Pruebas | pytest: unitarias (sin BD), de integración (API + PostGIS real) y un script de carga para el p95. |
| Plataforma objetivo | Docker Compose local (Docker Desktop o Podman + compose). La nube queda fuera de alcance. |
| Restricciones | p95 < 200 ms en la consulta de cercanía. Pool ≤ 50 conexiones. Sin secretos en el repositorio (`.env` ignorado; se versiona `.env.example`). Nombres del contrato en inglés. |
| Comandos | `docker compose up -d --build` (arranque) · `docker compose --profile test run --rm tests` (pruebas) · `docker compose down -v` (reset de la BD) |

## 3. Verificación contra la constitución

`.sdd/constitution.md` está sin rellenar (versión 0.0.0), así que no hay principios contra los que validar. Por eso el plan aplica criterios por defecto, que se pueden formalizar con `/sdd-constitution`:

| Criterio por defecto | ¿Cumple? | Nota |
|---|---|---|
| Simplicidad: sin dependencias ni capas que la spec no justifique | Sí | 3 dependencias de ejecución; sin ORM, sin migraciones con herramienta, sin broker (D-002, D-003). |
| Seguridad por defecto: entrada validada en el borde, sin secretos en el repo | Sí | Validación Pydantic antes de la BD (RF-010); SQL parametrizado (RNF-003); `.env` en `.gitignore`. |
| Pruebas de la lógica de dominio | Sí | Reglas de rango de Bogotá y radio con pruebas unitarias; endpoints con pruebas de integración. |

## 4. Arquitectura y componentes

```text
   Reportes (POST, síncrono)          Cliente de mapa (GET)
              │                                │
              ▼                                ▼
 ┌────────────────────── app (FastAPI) ───────────────────────┐
 │ api/routes.py    endpoints + mapeo a códigos HTTP           │
 │ api/schemas.py   modelos Pydantic (camelCase, validación)   │
 │ api/errors.py    handlers → {code, message} (400/404/409/503)│
 │ domain/geo.py    reglas puras: rango Bogotá, radio máximo   │
 │ db/repository.py SQL parametrizado (asyncpg)                │
 │ db/pool.py       pool asyncpg (min/max por config, ≤ 50)    │
 │ config.py        settings desde variables de entorno        │
 └───────────────────────────┬────────────────────────────────┘
                             ▼
                PostgreSQL + PostGIS (contenedor propio)
                tabla coordinates + índice GiST
```

**Responsabilidades:**
- **`domain/geo.py`**: funciones puras sin dependencias de FastAPI ni de la BD:
  - `is_within_bogota(lat, lon)`.
  - Constantes del recuadro, que se leen de la configuración.
  - Validación de radio `0 < r ≤ max_radius_m`.
- **`api/schemas.py`**: usa `domain/geo.py` en validadores Pydantic, así que toda entrada inválida se rechaza antes de tocar la BD (RF-010).
- **`db/repository.py`**: tres consultas y un *ping*:
  - `assign(report_id, lat, lon)` → `(coordinate, created: bool)` o error de conflicto.
  - `find_nearby(lat, lon, radius_m)`.
  - `get_by_id(coordinate_id)`.
  - `ping()`.
- **`api/routes.py`**: orquesta la llamada, traduce el resultado a 201/200/404/409 y no tiene lógica de negocio adicional.
- **Estado (RNF-004)**: el servicio no guarda estado en memoria. Lo único compartido es el pool de conexiones, creado en el `lifespan` de FastAPI.

## 5. Estructura de archivos

Raíz: carpeta del arnés (`Arnés base para SDD/`).

```text
app/
  __init__.py
  main.py              # create_app(): lifespan (pool), routers, exception handlers
  config.py            # Settings (env): DATABASE_URL, DB_POOL_MIN/MAX, MAX_RADIUS_M, BOGOTA_* bbox
  api/
    __init__.py
    routes.py          # /api/v1/geospatial/... y /health
    schemas.py         # AssignLocation, LocationAssigned, NearbyReport, Coordinate, ErrorResponse
    errors.py          # handlers: RequestValidationError→400, NotFound→404, Conflict→409, DB→503
  domain/
    __init__.py
    geo.py             # rango de Bogotá, radio máximo (puro)
  db/
    __init__.py
    pool.py            # create_pool / close_pool
    repository.py      # SQL parametrizado
db/
  schema.sql           # extensión postgis, tabla coordinates, índices
  seed.sql             # puntos de demo + carga sintética para pruebas de rendimiento
  init/
    01_init.sh         # crea geospatial_test, aplica schema.sql a ambas BD, seed.sql solo a geospatial
tests/
  conftest.py          # cliente httpx ASGI, pool contra geospatial_test, TRUNCATE por prueba
  unit/
    test_geo.py        # rango Bogotá, radio
    test_schemas.py    # validación de parámetros y payloads
  integration/
    test_assign.py     # HU-1
    test_nearby.py     # HU-2
    test_coordinates.py# HU-5
    test_health.py     # HU-6 / RNF-006
  perf/
    load_nearby.py     # script de carga: p95 a 5x concurrencia nominal (no se ejecuta en pytest)
Dockerfile             # multi-stage: runtime (app) y test (app + deps de desarrollo)
compose.yaml           # servicios db, api y tests (perfil "test")
requirements.txt
requirements-dev.txt
pyproject.toml         # configuración de pytest (asyncio_mode, rutas)
.env.example
.gitignore             # .env, __pycache__, .venv, .pytest_cache
.dockerignore
README.md              # (modificar) sección del servicio: arranque, pruebas, endpoints
```

## 6. Modelo de datos

**Tabla `coordinates`** (`db/schema.sql`):

| Columna | Tipo | Restricciones |
|---|---|---|
| `coordinate_id` | `uuid` | PK, `DEFAULT gen_random_uuid()` |
| `report_id` | `uuid` | `NOT NULL`, `UNIQUE` (una coordenada por reporte; base de la idempotencia) |
| `location` | `geography(Point, 4326)` | `NOT NULL` |
| `created_at` | `timestamptz` | `NOT NULL DEFAULT now()` |

**Índices y rango:**
- `CREATE INDEX coordinates_location_gix ON coordinates USING GIST (location);`
- La latitud y longitud se leen con `ST_Y(location::geometry)` y `ST_X(location::geometry)`.
- El rango de Bogotá se valida en la aplicación (D-005), no con un `CHECK` en la BD. Así el recuadro es configurable sin migrar.

**Reglas:**
- **Asignación nueva:**
  ```sql
  INSERT ... ON CONFLICT (report_id) DO NOTHING RETURNING ...
  ```
  - Si devuelve fila → 201.
  - Si no, se lee la fila existente:
    - **misma coordenada** (lat y lon iguales redondeadas a 7 decimales, ~1 cm) → 200 con el mismo `coordinateId` (RF-003);
    - **distinta** → 409 (supuesto de la spec §11).
- **Cercanía:**
  ```sql
  WHERE ST_DWithin(location, ST_SetSRID(ST_MakePoint($lon, $lat), 4326)::geography, $radius)
  ```
  `ST_DWithin` es inclusivo (≤, S-2) y usa el índice GiST.
- **Orden de resultados:** por distancia ascendente (`ORDER BY location <-> punto`). Es una conveniencia sin costo; la spec no exige orden.

**Datos semilla** (`db/seed.sql`, solo en la base `geospatial`):
- ~30 puntos de demo en distintos lugares de Bogotá (HU-6).
- 20 000 puntos sintéticos dentro del área urbana, generados con `generate_series` y `setseed` (reproducibles), para medir RNF-001.

## 7. Contratos / interfaces

Prefijo `/api/v1/geospatial`. JSON en camelCase. Errores con la forma `{"code": <int>, "message": <str>, "details": [...]?}`.

### POST `/api/v1/geospatial/coordinates` — asignar localización (HU-1, RF-001/002/003/012)

Request (`AssignLocation`):
```json
{ "reportId": "uuid", "coordinate": { "lat": 4.6512, "lon": -74.0561 } }
```

| Respuesta | Cuándo |
|---|---|
| `201` `LocationAssigned` `{ "coordinateId", "reportId", "coordinate": {lat, lon} }` + header `Location: /api/v1/geospatial/coordinates/{coordinateId}` | Asignación nueva |
| `200` `LocationAssigned` (mismo `coordinateId`) | Repetición idéntica |
| `400` `{code:400, message:"Invalid parameter"}` | UUID inválido, lat/lon ausentes, no numéricos o fuera de Bogotá |
| `409` `{code:409, message:"Report already has a different location"}` | Mismo `reportId` con otra coordenada |
| `503` `{code:503, message:"Service unavailable"}` | BD no disponible |

### GET `/api/v1/geospatial/reports?lat=&lon=&radius=` — reportes cercanos (HU-2, RF-004/005/007/011)

- **`lat`, `lon`:** obligatorios, dentro del recuadro de Bogotá.
- **`radius`:** obligatorio, en metros, `0 < radius ≤ MAX_RADIUS_M` (por defecto 6000).

| Respuesta | Cuándo |
|---|---|
| `200` `[ { "reportId", "coordinateId", "coordinate": {lat, lon} } ]` | Siempre que los parámetros sean válidos; `[]` si no hay reportes |
| `400` | Parámetros inválidos (incluye 6001 m) |
| `503` | BD no disponible |

### GET `/api/v1/geospatial/coordinates/{coordinateId}` — resolver coordenada (HU-5, RF-009)

| Respuesta | Cuándo |
|---|---|
| `200` `LocationAssigned` `{ "coordinateId", "reportId", "coordinate": {lat, lon} }` | Existe |
| `400` | `coordinateId` no es UUID |
| `404` `{code:404, message:"Coordinate not found"}` | No existe |
| `503` | BD no disponible |

### GET `/health` — salud (RNF-006)

- `200 {"status":"ok"}` si `SELECT 1` responde.
- `503 {"status":"unavailable"}` si no.

### Configuración (variables de entorno, `.env.example`)

| Variable | Defecto | Uso |
|---|---|---|
| `DATABASE_URL` | `postgresql://geospatial:geospatial@db:5432/geospatial` | Conexión |
| `DB_POOL_MIN` / `DB_POOL_MAX` | `5` / `50` | Pool (RNF-002) |
| `MAX_RADIUS_M` | `6000` | Radio máximo (RF-011) |
| `BOGOTA_MIN_LAT` / `BOGOTA_MAX_LAT` | `3.72` / `4.84` | Recuadro (D-005) |
| `BOGOTA_MIN_LON` / `BOGOTA_MAX_LON` | `-74.46` / `-73.98` | Recuadro (D-005) |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | valores locales de ejemplo | Contenedor de BD |

### OpenAPI

FastAPI publica `/docs` y `/openapi.json`. Esa documentación sirve para que Reportes y el front consuman el contrato.

## 8. Decisiones

### D-001: Python 3.13 + FastAPI
- **Decisión**: FastAPI sobre Uvicorn, con Python 3.13 en el contenedor.
- **Alternativas consideradas**:
  - .NET 10, como el servicio Reportes del monorepo.
  - Flask.
- **Motivo**:
  - Es la decisión del usuario y coincide con la entrega 2 ("HTTPS / REST (FastAPI)").
  - Async nativo para I/O a BD, validación con Pydantic y OpenAPI automático.
  - Se usa 3.13 y no 3.14 porque es la versión con soporte de ruedas más asentado para `asyncpg`.

### D-002: Acceso a datos con `asyncpg` y SQL explícito
- **Decisión**: `asyncpg` directo, con consultas parametrizadas (`$1, $2…`) en `repository.py`.
- **Alternativas consideradas**:
  - SQLAlchemy 2 + GeoAlchemy2.
  - psycopg 3.
- **Motivo**:
  - Son 3 consultas sobre una tabla, y las funciones PostGIS se expresan mejor en SQL.
  - Un ORM añade dos dependencias sin beneficio.
  - El pool de `asyncpg` permite fijar `max_size=50` directamente (RNF-002).
  - La parametrización nativa garantiza RNF-003.

### D-003: Esquema con scripts SQL de inicialización, sin herramienta de migraciones
- **Decisión**: `db/schema.sql` y `db/seed.sql` aplicados por `docker-entrypoint-initdb.d` mediante `01_init.sh`, que también crea `geospatial_test`.
- **Alternativas consideradas**:
  - Alembic.
  - Crear el esquema al arrancar la app.
- **Motivo**:
  - Una tabla y un entorno local de pruebas.
  - Alembic se justifica cuando haya despliegue persistente con evolución del esquema.
  - Costo: los scripts solo corren con el volumen vacío, así que para reaplicarlos hay que usar `docker compose down -v` (documentado).

### D-004: `geography(Point, 4326)` + `ST_DWithin` + índice GiST
- **Decisión**: guardar como `geography` y filtrar con `ST_DWithin` en metros.
- **Alternativas consideradas**:
  - `geometry` en SRID 4326 con conversión manual a metros.
  - Proyectar a MAGNA-SIRGAS / Bogotá (EPSG:3116).
- **Motivo**:
  - Distancias en metros exactas sin proyecciones.
  - `ST_DWithin` es inclusivo (S-2) y usa el índice GiST que piden las entregas.
  - A escala de 6 km el costo extra de `geography` es despreciable.

### D-005: Recuadro de Bogotá = Distrito Capital completo, incluido Sumapaz, configurable
- **Decisión**: lat 3.72 a 4.84 y lon -74.46 a -73.98 por defecto, configurable por variables de entorno.
- **Alternativas consideradas**:
  - Solo el área urbana (≈ lat 4.45 a 4.84).
  - Un polígono exacto del límite distrital.
- **Motivo**:
  - La spec (S-4) pide un recuadro fijo que cubra el Distrito Capital.
  - Los deslizamientos (`LANDSLIDE`) ocurren sobre todo en zona rural, así que dejar fuera Sumapaz rechazaría reportes legítimos.
  - Un polígono exacto sería más preciso, pero requiere cargar el límite oficial; queda como mejora.
  - Es un recuadro, así que acepta algunos puntos de municipios vecinos (Soacha, La Calera, etc.). Se acepta ese margen.

### D-006: Errores de validación → 400 con `{code, message}`
- **Decisión**: un handler de `RequestValidationError` devuelve `400 {code:400, message:"Invalid parameter", details}` en lugar del 422 por defecto de FastAPI.
- **Alternativas consideradas**: mantener el 422.
- **Motivo**:
  - El contrato del equipo usa 400 y `{code, message}`.
  - La spec dice "rechazo por parámetro inválido".
  - `details` lleva el campo que falló, lo que ayuda al cliente sin filtrar información interna.

### D-007: Idempotencia por `UNIQUE(report_id)` + `ON CONFLICT DO NOTHING`
- **Decisión**: una coordenada por reporte, garantizada por la BD.
  - Repetición idéntica → 200 con el mismo id.
  - Coordenada distinta → 409.
- **Alternativas consideradas**:
  - Clave de idempotencia en cabecera.
  - Caché en memoria.
- **Motivo**:
  - El `reportId` ya es la clave natural, así que no hace falta cambiar el contrato.
  - Es seguro ante concurrencia sin bloqueos explícitos.
  - Se mantiene la ausencia de estado (RNF-004).

### D-008: Pruebas de integración contra PostGIS real, con BD de pruebas separada
- **Decisión**: la base `geospatial_test` del mismo contenedor, con `TRUNCATE coordinates` antes de cada prueba. Se ejecutan en el servicio `tests` de compose (perfil `test`).
- **Alternativas consideradas**:
  - Testcontainers.
  - SQLite/SpatiaLite.
  - Mocks del repositorio.
- **Motivo**:
  - Lo que se prueba es justamente el comportamiento de PostGIS (distancias, límite inclusivo).
  - Con una BD separada, las pruebas no borran la semilla de demo.
  - Al correr en contenedor no dependen del Python 3.14 local.
  - Testcontainers exige acceso al socket de Docker desde el contenedor.

### D-009: Medición del p95 con script propio sobre `httpx`
- **Decisión**: `tests/perf/load_nearby.py` lanza N peticiones concurrentes con puntos y radios aleatorios contra la API levantada y reporta p50/p95/p99.
  - La línea base "nominal" es 10 concurrentes; la prueba de 5x usa 50.
- **Alternativas consideradas**: k6 o Locust.
- **Motivo**:
  - Reutiliza `httpx`, que ya está en las dependencias de desarrollo.
  - Es suficiente para verificar RNF-001 y MS-002 en local.

### D-010: Imagen de BD propia sobre `postgres:17` + PostGIS de PGDG (desviación en implementación, T005)
- **Decisión**: `db/Dockerfile` basado en `docker.io/library/postgres:17` instalando `postgresql-17-postgis-3` del repositorio PGDG, en lugar de `postgis/postgis:17-3.5`.
- **Alternativas consideradas**:
  - `postgis/postgis` emulado como amd64.
  - Imagen comunitaria multi-arch (`imresamu/postgis`).
- **Motivo**:
  - `postgis/postgis` no publica arm64 ("no image found … arm64").
  - La emulación distorsionaría el p95 (RNF-001).
  - La imagen base es oficial y multi-arch, y el paquete viene del repositorio oficial de PostgreSQL.
  - Era la mitigación prevista en §10.

### D-011: Tolerancia de 1 mm en el radio de `ST_DWithin` (desviación en implementación, T011)
- **Decisión**: la consulta usa `radius + 0.001 m`.
- **Alternativas consideradas**:
  - `ST_Distance(...) <= radius`, que no usa el índice GiST y rompe RNF-001.
  - `ST_DWithin` con `use_spheroid=false` (esfera), que da hasta ~0.6 m de error a 500 m.
- **Motivo**:
  - `ST_DWithin` y `ST_Distance` calculan la geodésica con algoritmos distintos que difieren en menos de 1 µm.
  - Sin tolerancia, un reporte exactamente a 500 m quedaba excluido con radio 500, en contra de HU-2 criterio 2 y S-2.
  - 1 mm es despreciable frente a la precisión GPS y conserva el índice.

### D-012: Serialización de la consulta de cercanía en PostGIS (tras T016)
- **Decisión**: `find_nearby` devuelve el JSON final con `json_agg(json_build_object(...) ORDER BY distancia)`. La ruta lo envía como respuesta cruda (`application/json`), sin construir un modelo Pydantic por reporte. `response_model` se mantiene solo para el OpenAPI.
- **Alternativas consideradas**:
  - Seguir con Pydantic.
  - orjson, que añade una dependencia y aun así construye objetos.
- **Motivo**:
  - A 50 concurrentes el p95 era de 216 ms. El límite era la CPU de un proceso Python armando ~940 objetos por respuesta; PostGIS resolvía la consulta en ~7 ms.
  - Decisión del usuario (2026-10-01).

### D-013: Modelo de escalado en ECS (decisión del usuario, fuera del alcance local)
- **Decisión**:
  - El despliegue objetivo es AWS ECS con autoscaling de tareas.
  - Cada tarea ejecuta un proceso uvicorn; si se quisieran más procesos por tarea, uvicorn ya lee `WEB_CONCURRENCY`.
  - Se escala horizontalmente agregando tareas.
- **Consecuencia sobre RNF-002**: el límite de 50 conexiones a la BD es un **presupuesto total** entre todas las tareas y procesos. En ECS se debe cumplir `DB_POOL_MAX × procesos por tarea × tareas máximas ≤ 50`, por ejemplo `DB_POOL_MAX=5` con un máximo de 10 tareas. La alternativa es poner RDS Proxy delante.
- **Motivo**: lo indicó el usuario. En local, con una sola tarea, `DB_POOL_MAX=50` sigue siendo válido.

## 9. Estrategia de pruebas

| Nivel | Qué | Cómo |
|---|---|---|
| Unitario | `domain/geo.py`: dentro/fuera del recuadro, bordes exactos, radio 0/negativo/6000/6001. `schemas.py`: payloads y query params inválidos, inyección como texto | `pytest tests/unit` (sin BD) |
| Integración | HU-1: 201 / 200 idempotente / 409 / 400 fuera de Bogotá; HU-2: 300 m vs 800 m con radio 500, punto exacto a 500 m incluido, vacío → `[]`, cambio de punto/radio, 6000 ok / 6001 → 400; HU-5: 200 / 404 / 400; `/health` 200 | `pytest tests/integration` contra `geospatial_test`; los puntos de prueba se calculan con desplazamientos geodésicos conocidos |
| Robustez | BD caída → 503 en endpoints y `/health` | Prueba de integración con un pool apuntando a un puerto cerrado |
| Seguridad (RNF-003) | Payloads tipo `' OR 1=1 --` en `lat`/`radius`/`coordinateId` → 400; revisión de que `repository.py` no tiene SQL con f-strings ni `%` | Pruebas unitarias e integración, más revisión en `/sdd-verify` (`grep`) |
| Rendimiento (RNF-001, MS-002) | p95 < 200 ms a 50 concurrentes sobre 20 000 puntos | `docker compose exec api python -m tests.perf.load_nearby --concurrency 50 --requests 2000` (manual, en verificación) |
| Entorno (HU-6, RNF-005) | Arranque con un comando, `healthy`, consulta sobre la semilla devuelve datos | `docker compose up -d --build` → `docker compose ps` (healthy) → `curl` de ejemplo en el README |

**Comandos:**

```
docker compose --profile test run --rm tests            # unit + integration
docker compose --profile test run --rm tests pytest tests/unit
```

## 10. Riesgos y mitigaciones

| Riesgo | Impacto | Mitigación |
|---|---|---|
| No hay runtime de contenedores operativo: `/usr/local/bin/docker` apunta a un Docker Desktop ausente y Podman no tiene máquina | No se puede ejecutar nada de HU-6 ni las pruebas | Antes de implementar: `podman machine init && podman machine start` (+ `podman compose`, que requiere `docker-compose` o `podman-compose`), o reinstalar Docker Desktop. `compose.yaml` se mantiene compatible con ambos. |
| La imagen `postgis/postgis` puede no tener variante arm64 y correr emulada en Apple Silicon | Arranque lento y p95 local peor que el real | Fijar `platform` solo si hace falta. Si el p95 no se cumple por emulación, medir en amd64 o usar una imagen multi-arch equivalente; queda anotado en `verify.md`. |
| La carpeta del arnés no es un repo git | `autoCommitPerTask` no puede hacer commits | Hacer `git init` en la carpeta del arnés antes de `/sdd-implement` (confirmar con el usuario). |
| La llamada síncrona acopla la creación de reportes a la disponibilidad de Geoespacial | Si Geoespacial cae, no se crean reportes | Fuera de esta feature: Reportes debe tener timeout y manejo de 503. Se documenta en el README del servicio. |
| Los scripts de init solo corren con el volumen vacío | Cambios de esquema "no aplican" | Documentar `docker compose down -v` en el README. |
| El recuadro de Bogotá acepta puntos de municipios vecinos | Algunos reportes fuera del Distrito pasan la validación | Aceptado (D-005); mejora futura con un polígono oficial. |
| Monorepo UrbanAlert vs. carpeta del arnés | Código fuera del repo del equipo | Decisión del usuario: se desarrolla en el arnés; integrar luego como `backend/UrbanAlert.Geoespacial` o similar (fuera de esta feature). |

## 11. Trazabilidad

| Requisito | Componentes | Pruebas |
|---|---|---|
| RF-001 Asignación síncrona | `routes.py` POST coordinates, `repository.assign`, `schemas.AssignLocation/LocationAssigned` | `integration/test_assign.py::test_assign_new_returns_201` |
| RF-002 Rango Bogotá | `domain/geo.py`, validadores de `schemas.py`, `config.py` (bbox) | `unit/test_geo.py`, `integration/test_assign.py::test_outside_bogota_400`, `integration/test_nearby.py::test_point_outside_bogota_400` |
| RF-003 Idempotencia | `UNIQUE(report_id)`, `repository.assign` (ON CONFLICT) | `test_assign.py::test_repeat_same_returns_200_same_id`, `::test_repeat_different_returns_409`, conteo de filas = 1 |
| RF-004 Cercanía ≤ radio | `repository.find_nearby` (`ST_DWithin`), índice GiST | `test_nearby.py::test_300_in_800_out`, `::test_exact_500_included`, `::test_changed_point_or_radius` |
| RF-005 Vacío → 200 `[]` | `routes.py` GET reports | `test_nearby.py::test_empty_area_returns_empty_list` |
| RF-006 Filtro por tipo | — (fuera de alcance) | — |
| RF-007 Campos de respuesta | `schemas.NearbyReport` | `test_nearby.py::test_response_shape` (solo `reportId`, `coordinateId`, `coordinate`) |
| RF-008 Consumo de eventos | — (diferido) | — |
| RF-009 Coordenada por id | `routes.py` GET coordinates/{id}, `repository.get_by_id` | `integration/test_coordinates.py` (200/404/400) |
| RF-010 Validación antes de BD | `schemas.py`, `errors.py` (400) | `unit/test_schemas.py`, pruebas 400 de integración |
| RF-011 Radio ≤ 6000 m | `domain/geo.py`, `config.MAX_RADIUS_M` | `unit/test_geo.py::test_radius_bounds`, `test_nearby.py::test_6000_ok_6001_400` |
| RF-012 Solo consulta para el mapa | Rutas: solo POST coordinates escribe; no hay PUT/DELETE | Revisión de rutas en `/sdd-verify`; `test_assign.py` |
| RNF-001 p95 < 200 ms | Índice GiST, `geography`, pool | `tests/perf/load_nearby.py` (manual) |
| RNF-002 BD propia, ≤ 50 conexiones | `compose.yaml` (servicio `db` propio), `pool.py` (`DB_POOL_MAX=50`) | Revisión de config + `SELECT count(*) FROM pg_stat_activity` durante la prueba de carga |
| RNF-003 SQL parametrizado | `repository.py` | Pruebas de inyección (400) + `grep` en verificación |
| RNF-004 Sin estado | Sin cachés ni estado global salvo el pool | Revisión de código en `/sdd-verify` |
| RNF-005 Un comando, env, sin secretos | `compose.yaml`, `.env.example`, `.gitignore` | `docker compose up -d --build` en verificación |
| RNF-006 Salud | `/health`, `healthcheck` en `compose.yaml` | `test_health.py` (200 y 503) + `docker compose ps` |
| RNF-007 Contrato en inglés | `schemas.py` (camelCase en inglés), rutas | `test_nearby.py::test_response_shape`, revisión de OpenAPI |

# Tareas: Servicio Geoespacial

- **Plan**: ./plan.md
- **Estado**: aprobado

Leyenda: `[ ]` pendiente · `[~]` en progreso · `[x]` hecha · `[!]` bloqueada · `[-]` descartada · `[P]` paralelizable

Formato de cada tarea (una línea):
`- [ ] T001 [P] Descripción imperativa — archivos: ruta/a, ruta/b — cubre: RF-001 — verifica: <comando o criterio observable>`

Dependencias: cada fase depende de la anterior; dentro de una fase se ejecuta en orden salvo `[P]`.
Dependencias explícitas: añadir `— depende: T00X`.

Convención: `dc` = `docker compose` (o `podman compose`, según el runtime que deje T001). Cada tarea del núcleo incluye sus propias pruebas, porque la constitución no exige pruebas antes de la implementación; así cada tarea es un commit verificable.

## Fase 1: Preparación

- [x] T001 [P] Dejar operativo un runtime de contenedores con compose (Podman: `podman machine init && podman machine start` + proveedor compose; o reinstalar Docker Desktop). Requiere acción/confirmación del usuario — archivos: (ninguno; anotar el comando elegido en STATE.md §Contexto) — cubre: RNF-005 — verifica: `dc version` responde y `docker run --rm hello-world` (o `podman run`) termina con código 0
- [x] T002 [P] Inicializar git en la carpeta del arnés y crear `.gitignore` (`.env`, `__pycache__/`, `.venv/`, `.pytest_cache/`). Confirmar con el usuario antes de `git init` — archivos: .gitignore — cubre: RNF-005 — verifica: `git status` funciona y `git check-ignore .env` devuelve `.env`
- [x] T003 [P] Crear el esqueleto Python: `requirements.txt` (fastapi, uvicorn[standard], asyncpg con versiones fijadas), `requirements-dev.txt` (pytest, pytest-asyncio, httpx), `pyproject.toml` (pytest: `asyncio_mode=auto`, `testpaths`), paquetes vacíos `app/`, `app/api/`, `app/domain/`, `app/db/`, `tests/`, `.dockerignore` y `.env.example` con las variables del plan §7 — archivos: requirements.txt, requirements-dev.txt, pyproject.toml, app/**/__init__.py, .dockerignore, .env.example — cubre: RNF-005 — verifica: `python3 -c "import tomllib;tomllib.load(open('pyproject.toml','rb'))"` sin error y `.env.example` contiene `MAX_RADIUS_M=6000` y `DB_POOL_MAX=50`
- [x] T004 Crear `Dockerfile` multi-stage (`runtime` con uvicorn en `app.main:app`; `test` = runtime + deps de desarrollo + `tests/`) y `compose.yaml` con los servicios `db` (postgis/postgis:17-3.5, volumen, healthcheck `pg_isready`), `api` (depends_on db healthy, puerto 8000, env desde `.env`) y `tests` (perfil `test`, target `test`, `DATABASE_URL` hacia `geospatial_test`) — archivos: Dockerfile, compose.yaml — cubre: RNF-002, RNF-005 — verifica: `dc config` válido y `dc --profile test build` termina sin errores — depende: T001, T003
- [x] T005 Crear `db/schema.sql` (extensión postgis, tabla `coordinates` según plan §6, `UNIQUE(report_id)`, índice GiST) y `db/init/01_init.sh` (crea `geospatial_test` con postgis y aplica `schema.sql` a ambas bases; `seed.sql` solo a `geospatial` si existe) montados en `docker-entrypoint-initdb.d` — archivos: db/schema.sql, db/init/01_init.sh, compose.yaml — cubre: RNF-002, RF-003 (restricción única) — verifica: `dc down -v && dc up -d db` y luego `dc exec db psql -U geospatial -d geospatial_test -c "\d coordinates"` muestra la tabla con `coordinates_location_gix` y la restricción única; lo mismo en `-d geospatial` — depende: T004

## Fase 2: Núcleo

- [x] T006 Implementar `app/config.py` (Settings desde env con los defaults del plan §7: pool 5/50, `MAX_RADIUS_M=6000`, recuadro 3.72–4.84 / -74.46– -73.98) y `app/domain/geo.py` (`is_within_bogota`, `validate_radius`) con `tests/unit/test_geo.py`: dentro/fuera, bordes exactos del recuadro y radio 0, negativo, 6000 y 6001 — archivos: app/config.py, app/domain/geo.py, tests/unit/test_geo.py — cubre: RF-002, RF-011 — verifica: `dc --profile test run --rm tests pytest tests/unit/test_geo.py` en verde
- [x] T007 Implementar `app/api/schemas.py` (`Coordinate`, `AssignLocation`, `LocationAssigned`, `NearbyReport`, `NearbyQuery`, `ErrorResponse`; camelCase en inglés; validadores que usan `domain/geo.py`) y `app/api/errors.py` (`RequestValidationError` → 400 `{code:400, message:"Invalid parameter", details}`; excepciones `NotFound` → 404, `Conflict` → 409, `ServiceUnavailable` → 503), con `tests/unit/test_schemas.py`, que incluye payloads de inyección (`' OR 1=1 --`) rechazados — archivos: app/api/schemas.py, app/api/errors.py, tests/unit/test_schemas.py — cubre: RF-007, RF-010, RNF-003, RNF-007 — verifica: `dc --profile test run --rm tests pytest tests/unit` en verde — depende: T006
- [x] T008 Implementar `app/db/pool.py` (crear/cerrar el pool asyncpg con min/max de config), `app/main.py` (`create_app`, lifespan con el pool, registro de handlers y routers), `app/db/repository.py::ping`, la ruta `GET /health` (200 ok / 503 unavailable), `tests/conftest.py` (cliente httpx ASGI contra `geospatial_test`, `TRUNCATE coordinates` por prueba) y `tests/integration/test_health.py` (200 con BD; 503 con un pool que apunta a un puerto cerrado) — archivos: app/db/pool.py, app/db/repository.py, app/main.py, app/api/routes.py, tests/conftest.py, tests/integration/test_health.py — cubre: RNF-002, RNF-004, RNF-006 — verifica: `dc --profile test run --rm tests pytest tests/integration/test_health.py` en verde — depende: T005, T007
- [x] T009 Implementar `repository.assign` (`INSERT … ON CONFLICT (report_id) DO NOTHING RETURNING`; si ya existe, comparar lat/lon redondeadas a 7 decimales → mismo resultado o conflicto) y `POST /api/v1/geospatial/coordinates` (201 + `Location` / 200 / 400 / 409), con `tests/integration/test_assign.py`: nuevo → 201, repetición idéntica → 200 con el mismo `coordinateId` y una sola fila, coordenada distinta → 409, fuera de Bogotá → 400 sin filas, UUID inválido → 400 — archivos: app/db/repository.py, app/api/routes.py, tests/integration/test_assign.py — cubre: RF-001, RF-002, RF-003, RF-012 — verifica: `dc --profile test run --rm tests pytest tests/integration/test_assign.py` en verde — depende: T008
- [x] T010 Implementar `repository.get_by_id` y `GET /api/v1/geospatial/coordinates/{coordinateId}` (200 / 404 / 400), con `tests/integration/test_coordinates.py` — archivos: app/db/repository.py, app/api/routes.py, tests/integration/test_coordinates.py — cubre: RF-009 — verifica: `dc --profile test run --rm tests pytest tests/integration/test_coordinates.py` en verde — depende: T009
- [x] T011 Implementar `repository.find_nearby` (`ST_DWithin` sobre geography, `ORDER BY location <-> punto`) y `GET /api/v1/geospatial/reports?lat&lon&radius`, con `tests/integration/test_nearby.py`: 300 m dentro / 800 m fuera con radio 500, punto exactamente a 500 m incluido, zona vacía → `[]`, cambio de punto/radio, 6000 → 200 / 6001 → 400, forma de respuesta (solo `reportId`, `coordinateId`, `coordinate`), punto fuera de Bogotá → 400. Los puntos de prueba se generan con desplazamientos geodésicos conocidos — archivos: app/db/repository.py, app/api/routes.py, tests/integration/test_nearby.py — cubre: RF-004, RF-005, RF-007, RF-011, RNF-007 — verifica: `dc --profile test run --rm tests pytest tests/integration/test_nearby.py` en verde — depende: T010
- [x] T012 Mapear errores de conexión a la BD (`asyncpg`/`OSError`/timeout del pool) a 503 `{code:503, message:"Service unavailable"}` en los tres endpoints, con pruebas en `tests/integration/test_unavailable.py` — archivos: app/api/errors.py, app/db/repository.py, tests/integration/test_unavailable.py — cubre: RNF-006 (caso borde "BD no disponible") — verifica: `dc --profile test run --rm tests pytest tests/integration/test_unavailable.py` en verde — depende: T011

## Fase 3: Integración

- [x] T013 Crear `db/seed.sql`: ~30 puntos de demo repartidos por Bogotá + 20 000 sintéticos dentro del área urbana con `setseed` (reproducibles), cargado solo en `geospatial` por `01_init.sh` — archivos: db/seed.sql — cubre: RNF-001, RNF-005 (HU-6) — verifica: `dc down -v && dc up -d db` y luego `dc exec db psql -U geospatial -d geospatial -tc "select count(*) from coordinates"` ≈ 20030; en `geospatial_test` da 0 — depende: T005
- [x] T014 Completar el arranque con un comando: healthcheck del servicio `api` (petición a `/health` con `python -c urllib…`), `depends_on: condition: service_healthy`, variables desde `.env` (copiado de `.env.example`) — archivos: compose.yaml, Dockerfile — cubre: RNF-005, RNF-006 (HU-6) — verifica: `cp .env.example .env && dc up -d --build` → `dc ps` muestra `api` y `db` como `healthy`, y `curl "localhost:8000/api/v1/geospatial/reports?lat=4.6486&lon=-74.0628&radius=1000"` devuelve una lista no vacía — depende: T012, T013
- [x] T015 Ejecutar la suite completa en contenedor y corregir lo que falle — archivos: (los que requiera la corrección) — cubre: MS-001, MS-003 — verifica: `dc --profile test run --rm tests` termina con todas las pruebas en verde — depende: T014

## Fase 4: Pulido

- [-] T016 Crear `tests/perf/load_nearby.py` (httpx async: N peticiones a M concurrentes con puntos urbanos y radios aleatorios ≤ 6000; imprime p50/p95/p99 y errores), ejecutarlo a 10 y 50 concurrentes contra la semilla y anotar los resultados (y el máximo de conexiones en `pg_stat_activity`) en el journal — archivos: tests/perf/load_nearby.py — cubre: RNF-001, RNF-002, MS-002 — verifica: a 50 concurrentes p95 < 200 ms, 0 errores y conexiones ≤ 50; si no se cumple por emulación arm64, registrarlo como riesgo materializado — depende: T014 — descartada: dividida en T016a/T016b tras el bloqueo (p95 216 ms a 50 conc.); el script de carga ya está hecho (commit 2dab799)
- [x] T016a Serializar la respuesta de cercanía en PostGIS (`json_agg` + `json_build_object`, orden por cercanía, `'[]'` si vacío) y devolverla como respuesta JSON cruda sin construir modelos por reporte; el contrato y el OpenAPI no cambian — archivos: app/db/repository.py, app/api/routes.py — cubre: RNF-001, RF-004, RF-005, RF-007 — verifica: `dc --profile test run --rm --build tests` en verde (incluye forma exacta de la respuesta y orden)
- [x] T016b Repetir la medición de carga a 10 y 50 concurrentes con la semilla y anotar los resultados en el journal — archivos: (ninguno) — cubre: RNF-001, RNF-002, MS-002 — verifica: a 50 concurrentes p95 < 200 ms, 0 errores, conexiones ≤ 50; si no se cumple, registrarlo y consultar al usuario — depende: T016a
- [x] T017 [P] Documentar el servicio en `README.md`: arranque (`cp .env.example .env`, `dc up -d --build`), reset (`dc down -v`), pruebas, endpoints con ejemplos `curl`, variables de entorno, y la nota para Reportes (timeout, manejo de 200/409/503) — archivos: README.md — cubre: RNF-005 — verifica: siguiendo solo el README desde un clon limpio se levanta el entorno y los `curl` responden como se documenta — depende: T014

## Correcciones de verificación

<!-- /sdd-verify añade aquí tareas si detecta fallos -->

- [x] T018 Añadir prueba de integración del caso borde "punto cerca del borde del rango de Bogotá con una distancia que se sale del rango": centro en el borde norte (lat 4.84) y en el borde oeste (lon -74.46) con radio 6000, con un reporte dentro del rango → 200 y solo ese reporte, sin error (verify.md H-1) — archivos: tests/integration/test_nearby.py — cubre: RF-004, caso borde spec §4 — verifica: `dc --profile test run --rm --build tests` en verde

## Cobertura

| Requisito | Tareas |
|---|---|
| RF-001 Asignación síncrona | T009 |
| RF-002 Rango Bogotá | T006, T009, T011 |
| RF-003 Idempotencia | T005, T009 |
| RF-004 Cercanía ≤ radio | T011, T018 |
| RF-005 Vacío → `[]` | T011 |
| RF-006 Filtro por tipo | — fuera de alcance (spec §8) |
| RF-007 Campos de respuesta | T007, T011 |
| RF-008 Consumo de eventos | — diferido (spec §8) |
| RF-009 Coordenada por id | T010 |
| RF-010 Validación antes de BD | T007 |
| RF-011 Radio ≤ 6000 m | T006, T011 |
| RF-012 Solo consulta para el mapa | T009 (única escritura); revisión en /sdd-verify |
| RNF-001 p95 < 200 ms | T013, T016a, T016b |
| RNF-002 BD propia, ≤ 50 conexiones | T004, T005, T008, T016b |
| RNF-003 SQL parametrizado | T007 (inyección → 400), T009–T011 (consultas `$n`); revisión en /sdd-verify |
| RNF-004 Sin estado | T008 |
| RNF-005 Un comando, env, sin secretos | T001–T004, T013, T014, T017 |
| RNF-006 Salud | T008, T012, T014 |
| RNF-007 Contrato en inglés | T007, T011 |
| MS-001 / MS-003 | T015 (y T009 para MS-003) |
| MS-002 | T016b |

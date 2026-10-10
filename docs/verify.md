# Verificación: Servicio Geoespacial

- **Fecha**: 2026-10-01
- **Resultado global**: ✅. La primera pasada dio ⚠️ por H-1, corregido en T018 y re-verificado el mismo día.

## 1. Comandos ejecutados

| Comando | Resultado |
|---|---|
| `docker-compose down -v && docker-compose up -d --build --wait` | ✅ `db` y `api` *healthy* desde un volumen vacío (esquema + semilla 20 031 filas) |
| `docker-compose --profile test run --rm --build tests` (unit + integración) | ✅ 74 passed en 0.20 s (1.ª pasada); ✅ **76 passed** tras T018 |
| `curl ".../reports?lat=4.6486&lon=-74.0628&radius=1000"` sobre la semilla | ✅ 200, 87 reportes |
| Carga: 5 generadores × 10 concurrentes (`tests/perf/load_nearby.py`, T016b) | ✅ p95 136–144 ms, 0 errores, pico 50 conexiones |
| `grep -nE 'f"\|\.format\(\|%s' app/db/*.py` (RNF-003) | ✅ sin coincidencias; 5 llamadas `fetch*` con parámetros `$n` |
| `grep` de TODO/FIXME/NotImplemented en `app tests db` | ✅ ninguno |
| `git ls-files \| grep '^\.env$'` | ✅ `.env` no versionado |
| Lint / typecheck | — No definidos en el plan ni en la constitución |

## 2. Matriz de requisitos

### Requisitos funcionales

| Req. | Evidencia | Estado |
|---|---|---|
| RF-001 Asignación síncrona | `app/api/routes.py:44` (POST), `app/db/repository.py:78`; `tests/integration/test_assign.py:16` | ✅ |
| RF-002 Rango Bogotá | `app/domain/geo.py:14`, `app/api/schemas.py:16`; `tests/unit/test_geo.py:27,44`; `test_assign.py:64`; `test_nearby.py:118` | ✅ |
| RF-003 Idempotencia | `db/schema.sql:9` UNIQUE, `repository.py:24` ON CONFLICT; `test_assign.py:30` (200 mismo id), `:54` (10 concurrentes → 1 fila), `:40` (409) | ✅ |
| RF-004 Cercanía ≤ radio | `repository.py:54` ST_DWithin + tolerancia 1 mm (D-011); `test_nearby.py:52,59,77` | ✅ |
| RF-005 Vacío → `[]` | `repository.py:42` COALESCE `'[]'`; `test_nearby.py:68` | ✅ |
| RF-006 Filtro por tipo | Fuera de alcance (spec §8) | — |
| RF-007 Solo campos del contrato | `repository.py:43` json_build_object; `test_nearby.py:103`; `test_schemas.py:47` | ✅ |
| RF-008 Consumo de eventos | Diferido (spec §8) | — |
| RF-009 Coordenada por id | `routes.py:73`, `repository.py:88`; `test_coordinates.py:9,19,26` | ✅ |
| RF-010 Validación antes de BD | `schemas.py` + `errors.py` (400); `test_schemas.py:42,80,118`; `test_unavailable.py:46` (400 incluso con la BD caída, lo que prueba que la validación ocurre antes de acceder a la BD) | ✅ |
| RF-011 Radio ≤ 6000 m | `geo.py:25`, `config.py:36`; `test_geo.py:49,54`; `test_nearby.py:95` (6000 → 200 / 6001 → 400) | ✅ |
| RF-012 Solo consulta para el mapa | Rutas en `routes.py:37,44,73,87`: un único POST de escritura y ningún PUT/PATCH/DELETE. El control de quién invoca el POST queda para el gateway/autenticación (fuera de alcance) | ✅ |

### Requisitos no funcionales

| Req. | Evidencia | Estado |
|---|---|---|
| RNF-001 p95 < 200 ms | T016b: p95 136–144 ms a 50 concurrentes (5 × 10), 20 031 puntos; journal 2026-10-01 | ✅ |
| RNF-002 BD propia, ≤ 50 conexiones | Servicio `db` propio (`compose.yaml`); `pool.py:14` `max_size`; pico medido 50 (todas del pool de la API). En ECS es un presupuesto total (D-013) | ✅ |
| RNF-003 SQL parametrizado | grep sin interpolación; `test_schemas.py:42,80,118` y `test_nearby.py:124` con inyección → 400 | ✅ |
| RNF-004 Sin estado | Sin variables globales mutables; solo `app.state.pool` (`main.py`) | ✅ |
| RNF-005 Un comando, env, sin secretos | `docker-compose up -d --build --wait` desde cero; `.env.example`; `.env` ignorado; verificado desde un clon limpio (T017) | ✅ |
| RNF-006 Salud | `routes.py:37`; `test_health.py:9,15`; healthchecks en `compose.yaml:20,41` (ambos *healthy*) | ✅ |
| RNF-007 Contrato en inglés | `schemas.py` (camelCase); `test_schemas.py:47`; `test_nearby.py:103`; path `{coordinateId}` | ✅ |

### Criterios de aceptación

| HU / criterio | Evidencia | Estado |
|---|---|---|
| HU-1.1 asignación nueva | `test_assign.py:16` | ✅ |
| HU-1.2 fuera de Bogotá / mal formada → rechazo sin registro | `test_assign.py:64,72`; `test_schemas.py:42` | ✅ |
| HU-1.3 repetición → mismo id, sin registro nuevo | `test_assign.py:30,54` | ✅ |
| HU-2.1 300 m dentro / 800 m fuera | `test_nearby.py:52` | ✅ |
| HU-2.2 exactamente 500 m incluido | `test_nearby.py:59` | ✅ |
| HU-2.3 vacío → éxito + `[]` | `test_nearby.py:68` | ✅ |
| HU-2.4 otro punto / radio | `test_nearby.py:77` | ✅ |
| HU-2.5 solo id de reporte, id de coordenada y coordenada | `test_nearby.py:103` | ✅ |
| HU-2.6 6000 aceptado / 6001 rechazado | `test_nearby.py:95` | ✅ |
| HU-3, HU-4 | Fuera de alcance / diferida | — |
| HU-5.1 / HU-5.2 | `test_coordinates.py:9,19` | ✅ |
| HU-6.1 un comando → servicio sano | `up --build --wait` → *healthy* | ✅ |
| HU-6.2 consulta sobre semilla devuelve reportes | curl → 87 reportes | ✅ |

### Casos borde (spec §4)

| Caso | Evidencia | Estado |
|---|---|---|
| lat/lon no numéricas, ausentes o fuera de rango | `test_schemas.py:42,80`; `test_nearby.py:118,124` | ✅ |
| Radio ausente, 0, negativo o > 6000 | `test_geo.py:54`; `test_schemas.py:80`; `test_nearby.py:95,124` | ✅ |
| Punto cerca del borde con un radio que se sale del rango → solo existentes, sin error | `test_nearby.py:131` (bordes norte y oeste, radio 6000) — T018 | ✅ |
| Mismo reporte con otra coordenada → 409, se conserva la original | `test_assign.py:40` | ✅ |
| BD no disponible → 503 y la salud lo refleja | `test_unavailable.py:25,34,40`; `test_health.py:15` | ✅ |
| Contenido malicioso → rechazo sin llegar a la BD | `test_schemas.py:118` (sin eco del input); `test_nearby.py:124` | ✅ |

### Métricas de éxito

| Métrica | Estado |
|---|---|
| MS-001 criterios de HU-1, 2, 5 y 6 | ✅ |
| MS-002 p95 < 200 ms a 5x | ✅ (T016b) |
| MS-003 0 duplicados al repetir | ✅ `test_assign.py:30,54` |

## 3. Constitución

`.sdd/constitution.md` está sin rellenar (v0.0.0), así que no hay principios formales. Se aplicaron los criterios por defecto del plan §3:

| Criterio | Estado |
|---|---|
| Simplicidad (sin dependencias ni capas injustificadas) | ✅ 3 dependencias de ejecución; sin ORM ni migraciones |
| Seguridad por defecto | ✅ validación en el borde, SQL parametrizado, sin secretos versionados (las credenciales de `.env.example` son solo para uso local) |
| Pruebas de la lógica de dominio | ✅ `tests/unit/test_geo.py` |

## 4. Hallazgos

- **H-1 (resuelto en T018)**: el caso borde "punto cerca del borde del rango de Bogotá con una distancia que se sale del rango" no tenía prueba. Por diseño solo se valida el centro, así que debería responder 200, pero faltaba la evidencia. Se añadió la prueba y pasa.
- **Tareas `[x]` sin evidencia**: ninguna. Cada tarea tiene su verificación registrada en el journal.
- **Desviaciones del plan**: todas documentadas.
  - D-010: imagen de BD propia.
  - D-011: tolerancia de 1 mm.
  - D-012: JSON armado en PostGIS.
  - D-013: escalado en ECS.
  - `tests/integration/conftest.py` añadido (registrado en el journal de T008).
- **Código muerto / TODOs / secretos**: ninguno.
- **Fuera del código** (informativos, no bloquean):
  - El arnés usa hooks `.ps1` (PowerShell). No se comprobó que se ejecuten en macOS.
  - `~/.docker/config.json` del usuario sigue apuntando a Docker Desktop (documentado en el README).

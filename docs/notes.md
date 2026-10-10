# Notas: 001-servicio-geoespacial

## Indicaciones técnicas de la fuente

### Contrato acordado con el usuario (traducción al inglés de Contratos UrbanAlert.docx › Geoespacial)

**REST**

```
GET api/v1/geospatial/reports?lat={lat}&lon={lon}&radius={meters}
```
- Query params (no path segments): decided with the user. Reasons: they filter a collection, negative/decimal values in path segments are fragile, easier validation/OpenAPI.
- No damageType filter: Geospatial only knows contract data (user decision 2026-10-01).
- `radius` max = 6000 m (user decision 2026-10-01, replaces 'semi-major axis of Bogotá'). Covers the full viewport down to zoom 15 on desktop (1920×1080) and zoom 14 on mobile (~390×844), 256 px tile scale; the front must cap the radius / ask to zoom in beyond that.
- Plan: make the max radius configurable via environment variable (default 6000 m) so it can be tuned after load tests without code changes. A city-wide view for the admin portal should be a separate feature (aggregated counts per zone / clustering), not a larger radius.
- `radius` in meters (the original contract said `rango` without a unit).
- Response 200: `[{ reportId, coordinateId, coordinate: { lat, lon } }]`; empty area → 200 `[]`.
- Error 400: `{ code, message: "Invalid parameter" }` (the original contract shows `code: 404` in the Reportes example; it looks like a typo).

```
GET api/v1/geospatial/coordinates/{coordinateId}
```
- Suggested to the user, accepted: lets Reportes resolve lat/lon from `IdCoordenada`. 200 `{ coordinateId, reportId, lat, lon }`, 404 if it does not exist.

**Location assignment (synchronous REST, no message queue in this version)**
- Called by Reportes inside its report-creation flow; uses the contract payloads:
  - Request `AssignLocation { reportId: UUID, coordinate: { lat, lon } }`
  - Response `LocationAssigned { coordinateId: UUID, reportId: UUID, coordinate: { lat, lon } }`
- Route not fixed in the contract. Proposal for the plan: `POST api/v1/geospatial/coordinates` → 201 + `LocationAssigned`; repeated reportId → 200 with the same coordinateId (idempotent); same reportId with a different coordinate → 409.
- Deferred (needs the queue): consuming `ReportCreated { eventId, report: { reportId, status, coordinates, userId, … } }` and status changes. Geospatial does NOT emit duplicate events.

**Enums (owned by Reportes; NOT used by Geospatial)**
- damageType: `FLOOD`, `LANDSLIDE`, `ROAD_DAMAGE`
- status (my translation, not fixed in the contract): `REPORTED`, `VERIFIED`, `ASSIGNED`, `IN_PROGRESS`, `RESOLVED`, `CLOSED`, `REJECTED`
- emergencyLevel: `UNDEFINED`, `LOW`, `MEDIUM`, `HIGH`
- Coordinate validation (Geospatial): Bogotá range.

### Arquitectura de las entregas (para /sdd-plan)
- Store: PostgreSQL + PostGIS, separate instance, GiST/R-Tree spatial index (delivery2/3).
- Bulkhead: own connection pool, max 50 connections (ADR-03/05).
- Bus: AMQP RabbitMQ (ADR-01) — NOT in this version (user decision 2026-10-01).
- REST only; WebSockets discarded (ADR-04). Redis/CDN cache is out of scope locally.
- Correlation ID propagation, structured logging (delivery3 QAS-04.1).
- Stack in use in the monorepo: .NET 10 (`../Repositorio de código/UrbanAlert/backend/UrbanAlert.Reportes`: API/Application/Domain/Infrastructure, Scalar/OpenAPI, Dockerfile in deploy/docker). The delivery2 doc mentions FastAPI; the repo is the current reference. Confirm in the plan.
- Deployment target for now: local Docker (docker compose with the service + PostGIS + seed data only).
- Note: the synchronous call couples report creation to Geospatial availability/latency (ADR-01 targets <150 ms for Reportes to confirm). Consider a timeout on the Reportes side in its own plan.
- Transactional Outbox / idempotency key in Postgres ("Dual write para el ADR.docx") applies to Reportes; Geospatial only needs idempotent consumption.
- Responsible: Fabian (Geoespacial). Milestones in the contract doc: progress on Sat 2026-10-03, final delivery 2026-10-12.

# CLAUDE.md

Microservicio Geoespacial de UrbanAlert, extraído de `backend/UrbanAlert.Geoespacial` del monorepo UrbanAlert
para migrarlo a AWS con CI/CD en GitHub Actions. Python 3.13 + FastAPI + asyncpg sobre PostgreSQL 17 + PostGIS 3.

- Arranque local: `cp .env.example .env && docker-compose up -d --build --wait` (API en :8000, BD en :5433)
- Pruebas: `docker-compose --profile test run --rm --build tests` (solo unitarias: añadir `pytest tests/unit`)
- Contrato: JSON camelCase, errores `{code, message, details?}`; spec original en `docs/`.

## Desarrollo guiado por especificaciones (SDD)

Este proyecto usa un arnés SDD con persistencia en disco para sobrevivir a interrupciones de sesión.
El protocolo es obligatorio en todas las sesiones:

@.sdd/PROTOCOL.md

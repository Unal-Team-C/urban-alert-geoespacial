# CLAUDE.md

Microservicio Geoespacial de UrbanAlert, extraído de `backend/UrbanAlert.Geoespacial` del monorepo UrbanAlert
para migrarlo a AWS con CI/CD en GitHub Actions. Python 3.13 + FastAPI + asyncpg sobre PostgreSQL 17 + PostGIS 3.

- Arranque local: `cp .env.example .env && docker-compose up -d --build --wait` (API en :8000, BD en :5433)
- Pruebas: `docker-compose --profile test run --rm --build tests` (solo unitarias: añadir `pytest tests/unit`)
- Contrato: JSON camelCase, errores `{code, message, details?}`; spec original en `docs/`.
- En este Mac `docker-compose` necesita `export DOCKER_CONFIG=~/.docker-podman` y `podman machine start`.

AWS (spec `specs/002-migracion-aws/`): cuenta 348364742283, us-east-2. Terraform se aplica solo desde GitHub Actions.

- `infra/base` (ECR, roles ECS, red, RDS, secreto, logs, clúster, task definition del esquema) e `infra/service` (ECS Express) con estado en `s3://urban-alert-tfstate-348364742283/geoespacial/`. Arranque manual e inventario: `infra/bootstrap/`, `infra/INVENTARIO.md`.
- Workflows: `.github/workflows/provision.yml` (push a `main`) y `deprovision.yml` (manual, confirmación `urban-alert-geoespacial`).
- Esquema en la nube: `python -m app.db.migrate` (tarea ECS lanzada por `scripts/run-schema-task.sh`).
- Validación local sin instalar nada (Podman):
  - `podman run --rm -v "$PWD":/w -w /w docker.io/hashicorp/terraform:1.16.5 -chdir=infra/<stack> init -backend=false` y luego `validate` / `test`; `fmt -check -recursive infra`
  - `podman run --rm -v "$PWD":/repo -w /repo docker.io/rhysd/actionlint:1.7.7`
  - `podman run --rm -v "$PWD":/mnt -w /mnt docker.io/koalaman/shellcheck:stable scripts/*.sh`

## Desarrollo guiado por especificaciones (SDD)

Este proyecto usa un arnés SDD con persistencia en disco para sobrevivir a interrupciones de sesión.
El protocolo es obligatorio en todas las sesiones:

@.sdd/PROTOCOL.md

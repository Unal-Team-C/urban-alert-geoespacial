# Journal SDD

<!-- Bitácora append-only: añade entradas AL FINAL, no reescribas las anteriores.
     Formato:
     ## AAAA-MM-DD · <feature o "general"> · <evento>
     - detalle (qué, por qué, archivos, verificación)
     Las horas exactas de cada edición/checkpoint quedan en .sdd/activity.log. -->

## 2026-09-24 · general · Arnés SDD instalado
- Hooks (SessionStart, PostToolUse, PreCompact, Stop), 11 comandos /sdd-*, protocolo, plantillas e instalador.
- Probado: rastreo de ediciones, bloqueo en Stop, checkpoint vía STATE.md, reinyección de contexto, instalación/fusión en otro proyecto.

## 2026-10-10 · general · Servicio geoespacial migrado a este repositorio
- Copiado desde el monorepo UrbanAlert (`backend/UrbanAlert.Geoespacial`, commit 46daa1f) a la raíz del repo; arnés SDD conservado.
- README del servicio como README raíz (+ sección SDD); la guía del arnés pasa a `.sdd/GUIA.md`; `.gitignore` fusionado.
- Remoto `origin` → github.com/Unal-Team-C/urban-alert-geoespacial.

## 2026-10-10 · general · Decisión: en AWS solo se aplica el esquema
- RDS PostgreSQL 17 + PostGIS (`urban-alert-geoespacial-db`, us-east-2) se inicializa solo con `db/schema.sql` + usuario `geospatial_app` (SELECT, INSERT).
- Sin datos semilla (`db/seed.sql`) ni base `geospatial_test` en AWS; las pruebas de integración corren en GitHub Actions. Local (compose + 01_init.sh) sin cambios.

## 2026-10-10 · 002-migracion-aws · Creada spec desde descripción
- Migración a AWS: servicio apto para la nube (secreto + TLS, pool ≤ 50 conexiones totales, logs estructurados, apagado ordenado), esquema solo en RDS PostGIS, Terraform con estado remoto, workflow de aprovisionamiento en push a `main` + workflow manual, documentación.
- 18 RF, 7 RNF. 3 dudas abiertas: qué hace el workflow manual (HU-2/RF-013), importar o referenciar recursos creados a mano (RF-010), quién aplica el esquema (RF-016).
- Numerada 002 porque `docs/` contiene la spec 001 original del servicio.
- Nota de entorno: los hooks del arnés invocan `powershell`, no instalado en este Mac; no se ejecutan.

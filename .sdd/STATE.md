# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: - | en_progreso | hecha | bloqueada -->

feature_activa: 002-migracion-aws
fase: implement
tarea_actual: T003
estado_tarea: -

## Siguiente paso

T003: crear infra/INVENTARIO.md con recursos importados (ECR, roles, adjuntos, read-project-secrets) y externos de arranque.

## Contexto de trabajo

<!-- Lo que se perdería si la sesión se corta y no está en otros archivos:
     hipótesis en curso, comandos útiles, gotchas, archivos a mirar, lo que ibas a probar. -->

- AWS ya configurado por el usuario (us-east-2, cuenta 348364742283): OIDC + rol GitHub con políticas `github-actions-urban-alertPolicy` y `github-actions-urban-alert-terraform`, roles `urban-alert-ecs-*`, ECR `urban-alert-geoespacial`, bucket de estado `urban-alert-tfstate-348364742283` (confirmado). RDS, SG y secreto de BD NO existen: los crea Terraform (no van al inventario de importación). Secretos/variables de GitHub ya creados (AWS_ROLE_ARN, AWS_REGION, etc.).
- Verificación local: Podman (`podman machine start`) + `docker-compose`; Terraform/actionlint/shellcheck vía contenedores (comandos en la cabecera de tasks.md).
- `infra/bootstrap/github-oidc-trust.json` refleja la confianza recomendada (`repo:Unal-Team-C/*:ref:refs/heads/main`); la real no se ha visto: contrastar en verify.
- Rama `aws-provisioning`. Numeración 002 porque `docs/` ya contiene la spec 001-servicio-geoespacial original.

## Bloqueos / preguntas abiertas

- ninguno

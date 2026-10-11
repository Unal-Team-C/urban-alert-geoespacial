# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: - | en_progreso | hecha | bloqueada -->

feature_activa: 002-migracion-aws
fase: plan
tarea_actual: -
estado_tarea: -

## Siguiente paso

El usuario revisa y aprueba specs/002-migracion-aws/plan.md (decisiones a validar: D-001 dos stacks, D-002 Express en Terraform, D-003 tarea ECS para el esquema, D-004 orden, D-005 imports de un solo uso, D-016 tamaños). Con la aprobación: `Estado: aprobado` en el plan → `/sdd-tasks`.

## Contexto de trabajo

<!-- Lo que se perdería si la sesión se corta y no está en otros archivos:
     hipótesis en curso, comandos útiles, gotchas, archivos a mirar, lo que ibas a probar. -->

- AWS ya configurado por el usuario (us-east-2, cuenta 348364742283): OIDC + rol GitHub con políticas `github-actions-urban-alertPolicy` y `github-actions-urban-alert-terraform`, roles `urban-alert-ecs-*`, ECR `urban-alert-geoespacial`, bucket de estado `urban-alert-tfstate-348364742283` (confirmado). RDS, SG y secreto de BD NO existen: los crea Terraform (no van al inventario de importación). Secretos/variables de GitHub ya creados (AWS_ROLE_ARN, AWS_REGION, etc.).
- Rama `aws-provisioning`. Numeración 002 porque `docs/` ya contiene la spec 001-servicio-geoespacial original.

## Bloqueos / preguntas abiertas

- ninguno

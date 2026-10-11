# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: - | en_progreso | hecha | bloqueada -->

feature_activa: 002-migracion-aws
fase: clarify
tarea_actual: -
estado_tarea: -

## Siguiente paso

Esperar a que el usuario revise y apruebe specs/002-migracion-aws/spec.md (estado: aclarada); con la aprobación, marcar `Estado: aprobada` y ejecutar `/sdd-plan`. El plan debe incluir la política IAM ampliada del rol de GitHub (Terraform: IAM/ECR/logs/S3 estado/ecs:RunTask para el esquema, destroy).

## Contexto de trabajo

<!-- Lo que se perdería si la sesión se corta y no está en otros archivos:
     hipótesis en curso, comandos útiles, gotchas, archivos a mirar, lo que ibas a probar. -->

- Rama `aws-provisioning`. Numeración 002 porque `docs/` ya contiene la spec 001-servicio-geoespacial original.

## Bloqueos / preguntas abiertas

- ninguno (spec aclarada, pendiente de aprobación).

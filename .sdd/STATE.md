# Estado SDD

<!-- Puntero de reanudación. Claude lo actualiza en CADA transición (inicio/fin de tarea, cambio de fase, decisión, bloqueo).
     Editar este archivo = checkpoint (lo registra el hook). Mantenlo corto: el detalle va en specs/ y journal.md.
     fase: constitution | specify | clarify | plan | tasks | implement | verify | done
     estado_tarea: - | en_progreso | hecha | bloqueada -->

feature_activa: 002-migracion-aws
fase: specify
tarea_actual: T024
estado_tarea: bloqueada

## Siguiente paso

El usuario revisa y aprueba la spec 002 v2 (estado aclarada). Con la aprobación: `Estado: aprobada` → replanificar (`/sdd-plan`: red de la plataforma por SSM, schema task sin IP pública, stack de rutas tras el servicio con buscar-listener-express.sh, deprovision de rutas, política de plataforma) → actualizar tasks.md.

## Contexto de trabajo

<!-- Lo que se perdería si la sesión se corta y no está en otros archivos:
     hipótesis en curso, comandos útiles, gotchas, archivos a mirar, lo que ibas a probar. -->

- AWS ya configurado por el usuario (us-east-2, cuenta 348364742283): OIDC + rol GitHub con políticas `github-actions-urban-alertPolicy` y `github-actions-urban-alert-terraform`, roles `urban-alert-ecs-*`, ECR `urban-alert-geoespacial`, bucket de estado `urban-alert-tfstate-348364742283` (confirmado). RDS, SG y secreto de BD NO existen: los crea Terraform (no van al inventario de importación). Secretos/variables de GitHub ya creados (AWS_ROLE_ARN, AWS_REGION, etc.).
- Verificación local: Podman (`podman machine start`) + `docker-compose`; Terraform/actionlint/shellcheck vía contenedores (comandos en la cabecera de tasks.md).
- `infra/bootstrap/github-oidc-trust.json` refleja la confianza recomendada (`repo:Unal-Team-C/*:ref:refs/heads/main`); la real no se ha visto: contrastar en verify.
- Gotcha: `docker-compose` necesita `export DOCKER_CONFIG=~/.docker-podman` (si no, falla docker-credential-desktop).
- Terraform local: wrapper `<scratchpad>/tf` (podman, hashicorp/terraform:1.16.5, caché de plugins en ~/.cache/tf-plugins). En zsh no usar `$TF` con espacios.
- Riesgo abierto: el SG de tareas no tiene reglas de entrada; se asume que Express añade su propio SG ALB→tareas (comprobar en T024).
- Supuesto a comprobar en T024: RDS etiqueta su secreto maestro con `aws:rds:primaryDBInstanceArn` (la política read-project-secrets lo usa como condición). Los roles urban-alert-ecs-* son compartibles por nombre pero este stack los destruye al desaprovisionar: avisar al usuario.
- No lanzar Deprovision mientras exista infra/platform/imports.tf (T025 lo elimina tras el primer apply).
- Rama `aws-provisioning`. Numeración 002 porque `docs/` ya contiene la spec 001-servicio-geoespacial original.

## Bloqueos / preguntas abiertas

- T024: confianza OIDC pendiente de actualizar en AWS por el usuario.
- Cambio de requisitos (API Gateway compartido + servicio privado) pendiente de reflejar en spec/plan/tareas; depende de la plataforma compartida.

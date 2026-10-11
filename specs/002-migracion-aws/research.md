# Investigación: 002-migracion-aws

Fecha: 2026-10-10. Fuentes consultadas en esta sesión.

## ECS Express Mode

- Fuente: <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/express-service-overview.html> y `express-service-first-run.html`.
- Necesita imagen, rol de ejecución y rol de infraestructura. Crea servicio Fargate, ALB compartido con HTTPS y URL propia, autoscaling, logs.
- Por defecto: puerto 80, health check `/` (consola) o `/ping` (acción de GitHub), 1 vCPU / 2 GB, 1–20 tareas, escalado por CPU al 60 %.
- Rol de infraestructura: confianza `ecs.amazonaws.com`, política `arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices` (fuente: `infrastructure_IAM_role.html` y la referencia de la política).

## Terraform: `aws_ecs_express_gateway_service`

- Fuente: `terraform-provider-aws/website/docs/r/ecs_express_gateway_service.html.markdown` (rama `main`).
- Argumentos usados: `execution_role_arn`, `infrastructure_role_arn` (cambiarlo recrea el recurso), `cluster`, `cpu`, `memory`, `health_check_path`, `service_name` (cambiarlo recrea), `task_role_arn`, `wait_for_steady_state`, `network_configuration { subnets (≥ 2), security_groups }`, `scaling_target { auto_scaling_metric, auto_scaling_target_value, min_task_count, max_task_count }`, `primary_container { image, container_port, command, aws_logs_configuration { log_group, log_stream_prefix }, environment {name,value}, secret {name,value_from} }`.
- Atributos: `service_arn`, `ingress_paths[].endpoint` (URL pública).
- No expone la arquitectura de CPU → X86_64 (valor por defecto de Express).
- Importación por ARN del servicio. Timeouts por defecto: create/update 30 min, delete 20 min.
- La documentación no indica la versión del proveedor en que se añadió: se fija la restricción `~> 6.0` y la tarea de Terraform comprueba con `terraform init` que el recurso existe en la versión resuelta.

## Acción `aws-actions/amazon-ecs-deploy-express-service`

- Fuente: <https://github.com/aws-actions/amazon-ecs-deploy-express-service>.
- Alternativa para desplegar sin Terraform. Descartada en D-002: el servicio se gestiona como código (RF-010).

## Estado remoto

- Backend S3 con `use_lockfile = true` (Terraform ≥ 1.10): bloqueo con un objeto `.tflock`, sin DynamoDB.

## Herramientas locales

- En el Mac del usuario no están instalados `terraform` ni `aws`; hay `podman`. La validación de Terraform se hace en CI (`fmt`, `validate`, `test` con proveedores simulados) y el primer `plan` real con credenciales ocurre en el workflow de `main` (ver riesgos del plan).

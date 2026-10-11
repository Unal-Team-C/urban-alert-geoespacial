# Inventario de recursos de AWS

Cuenta `348364742283`, región `us-east-2`. Spec 002, RF-010b y RF-010c.

## 1. Recursos creados a mano e importados a Terraform

Se crearon en la consola antes de existir el código. El stack `infra/base` los importó en su primera ejecución con los bloques de `infra/base/imports.tf`, que después se borró (plan D-005): un bloque `import` permanente fallaría tras un desaprovisionamiento, porque el recurso ya no existiría.

Si se pierde el estado de Terraform con estos recursos todavía en AWS, se vuelven a importar copiando los bloques de la última columna a un `imports.tf` temporal.

| Recurso | ID en AWS | Dirección en Terraform | Bloque `import` |
|---|---|---|---|
| Repositorio ECR | `urban-alert-geoespacial` | `aws_ecr_repository.this` | `import { to = aws_ecr_repository.this  id = "urban-alert-geoespacial" }` |
| Rol de ejecución de ECS | `urban-alert-ecs-execution-role` | `aws_iam_role.execution` | `import { to = aws_iam_role.execution  id = "urban-alert-ecs-execution-role" }` |
| Adjunto `AmazonECSTaskExecutionRolePolicy` | `urban-alert-ecs-execution-role/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy` | `aws_iam_role_policy_attachment.execution_managed` | `import { to = aws_iam_role_policy_attachment.execution_managed  id = "urban-alert-ecs-execution-role/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy" }` |
| Política en línea `read-project-secrets` | `urban-alert-ecs-execution-role:read-project-secrets` | `aws_iam_role_policy.execution_secrets` | `import { to = aws_iam_role_policy.execution_secrets  id = "urban-alert-ecs-execution-role:read-project-secrets" }` |
| Rol de infraestructura de ECS | `urban-alert-ecs-infrastructure-role` | `aws_iam_role.infrastructure` | `import { to = aws_iam_role.infrastructure  id = "urban-alert-ecs-infrastructure-role" }` |
| Adjunto `AmazonECSInfrastructureRoleforExpressGatewayServices` | `urban-alert-ecs-infrastructure-role/arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices` | `aws_iam_role_policy_attachment.infrastructure_managed` | `import { to = aws_iam_role_policy_attachment.infrastructure_managed  id = "urban-alert-ecs-infrastructure-role/arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices" }` |

La regla de ciclo de vida del repositorio ECR (`aws_ecr_lifecycle_policy.this`) no se importa: la API de AWS la sobrescribe al crearla (`PutLifecyclePolicy`), exista o no.

Fecha de importación: **2026-10-11**, en el *Provision* run 38109542072 (los 6 importados sin recrearse; `imports.tf` se borró en T038).

## 2. Recursos creados por Terraform

No existían antes del código; los crea y destruye Terraform.

| Stack | Recursos |
|---|---|
| `base` | En la VPC compartida: SG `urban-alert-geoespacial-tasks` y `urban-alert-geoespacial-rds`, subnet group y RDS `urban-alert-geoespacial-db` (con su secreto `rds!…` gestionado por RDS), secreto `urban-alert-geoespacial-db`, clúster ECS `urban-alert-geoespacial`, grupos de logs `/ecs/urban-alert-geoespacial` y `/ecs/urban-alert-geoespacial-schema`, task definition `urban-alert-geoespacial-schema`, regla de ciclo de vida de ECR |
| `service` | Servicio ECS Express `urban-alert-geoespacial` (con el balanceador **interno**, el certificado, sus grupos de seguridad y el escalado que crea ECS con el rol de infraestructura) |
| `routes` | En el API Gateway compartido: 3 integraciones HTTP_PROXY por el VPC Link de la plataforma y 3 rutas (`GET /api/v1/geoespacial/reports`, `GET /api/v1/geoespacial/coordinates/{id}`, `POST /api/v1/geoespacial/coordinates` con `AWS_IAM`) |

## 3. Recursos externos de arranque (no gestionados por Terraform)

Terraform los necesita para ejecutarse; el desaprovisionamiento no los toca. Cómo crearlos: [bootstrap/README.md](bootstrap/README.md).

| Recurso | ID en AWS | Notas |
|---|---|---|
| Proveedor OIDC de GitHub | `arn:aws:iam::348364742283:oidc-provider/token.actions.githubusercontent.com` | Audiencia `sts.amazonaws.com` |
| Rol de los workflows | ARN en el secreto `AWS_ROLE_ARN` de GitHub (`github-actions-…`) | Confianza: [bootstrap/github-oidc-trust.json](bootstrap/github-oidc-trust.json) |
| Política `github-actions-urban-alertPolicy` | `arn:aws:iam::348364742283:policy/github-actions-urban-alertPolicy` | [bootstrap/github-deploy-policy.json](bootstrap/github-deploy-policy.json) |
| Política `github-actions-urban-alert-terraform` | `arn:aws:iam::348364742283:policy/github-actions-urban-alert-terraform` | [bootstrap/github-terraform-policy.json](bootstrap/github-terraform-policy.json) |
| Bucket del estado | `urban-alert-tfstate-348364742283` | Versionado, cifrado, privado, solo TLS |
| Política `github-actions-urban-alert-platform` | `arn:aws:iam::348364742283:policy/github-actions-urban-alert-platform` | Definida en `urban-alert-plataforma/infra/bootstrap/`; da a este repo `apigateway` sobre `/apis/*`, lectura de SSM y `elasticloadbalancing:Describe*` |

## 4. Plataforma compartida (otro repo, no gestionada aquí)

`Unal-Team-C/urban-alert-plataforma`: VPC, subredes privadas, NAT, API Gateway y VPC Link. Este repo solo lee su contrato en SSM (`/urban-alert/plataforma/`) y registra rutas en su gateway; el *Deprovision* de este repo nunca la toca.

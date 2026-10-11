# Both roles were created by hand and are imported (infra/INVENTARIO.md). Their names keep the
# urban-alert- prefix the pipeline's iam:PassRole and IAM permissions are scoped to.
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  db_arn     = "arn:aws:rds:${var.region}:${local.account_id}:db:${var.name}-db"
}

resource "aws_iam_role" "execution" {
  name        = "urban-alert-ecs-execution-role"
  description = "ECS task execution: pull images, write logs, read the service secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# App secret by name prefix; the RDS-managed master secret (rds!db-…) by the tag RDS puts on it.
resource "aws_iam_role_policy" "execution_secrets" {
  name = "read-project-secrets"
  role = aws_iam_role.execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ProjectSecrets"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:urban-alert-*"
      },
      {
        Sid      = "RdsMasterSecret"
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = "arn:aws:secretsmanager:${var.region}:${local.account_id}:secret:rds!*"
        Condition = {
          StringEquals = { "secretsmanager:ResourceTag/aws:rds:primaryDBInstanceArn" = local.db_arn }
        }
      }
    ]
  })
}

resource "aws_iam_role" "infrastructure" {
  name        = "urban-alert-ecs-infrastructure-role"
  description = "Lets ECS Express Mode manage the load balancer, certificate, security groups and autoscaling"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "infrastructure_managed" {
  role       = aws_iam_role.infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

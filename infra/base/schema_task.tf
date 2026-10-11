# One-off task that applies db/schema.sql and the application role (python -m app.db.migrate) from inside the
# VPC, with the same image the service will run. Launched by scripts/run-schema-task.sh (plan D-003).
locals {
  schema_container = "schema"
}

resource "aws_ecs_task_definition" "schema" {
  family                   = "${var.name}-schema"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.schema_task_cpu
  memory                   = var.schema_task_memory
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = local.schema_container
    image     = "${aws_ecr_repository.this.repository_url}:${var.image_tag}"
    command   = ["python", "-m", "app.db.migrate"]
    essential = true

    environment = [
      { name = "DB_HOST", value = aws_db_instance.this.address },
      { name = "DB_PORT", value = tostring(aws_db_instance.this.port) },
      { name = "DB_NAME", value = var.db_name },
      { name = "DB_APP_USER", value = var.db_app_user },
      { name = "DB_SSLMODE", value = "require" },
    ]

    secrets = [
      { name = "DB_ADMIN_USER", valueFrom = "${aws_db_instance.this.master_user_secret[0].secret_arn}:username::" },
      { name = "DB_ADMIN_PASSWORD", valueFrom = "${aws_db_instance.this.master_user_secret[0].secret_arn}:password::" },
      { name = "DB_APP_PASSWORD", valueFrom = "${aws_secretsmanager_secret.app.arn}:password::" },
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.schema.name
        awslogs-region        = var.region
        awslogs-stream-prefix = local.schema_container
      }
    }
  }])

  # The secret value must exist before a task can read it.
  depends_on = [aws_secretsmanager_secret_version.app]
}

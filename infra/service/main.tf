data "terraform_remote_state" "base" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "geoespacial/base.tfstate"
    region = var.region
  }
}

locals {
  base = data.terraform_remote_state.base.outputs
}

# ECS Express Mode creates the load balancer, HTTPS URL and autoscaling with the infrastructure role.
resource "aws_ecs_express_gateway_service" "this" {
  service_name            = local.base.name
  cluster                 = local.base.cluster_name
  execution_role_arn      = local.base.execution_role_arn
  infrastructure_role_arn = local.base.infrastructure_role_arn
  cpu                     = var.cpu
  memory                  = var.memory
  health_check_path       = var.health_check_path
  wait_for_steady_state   = true

  network_configuration {
    subnets         = local.base.subnet_ids
    security_groups = [local.base.tasks_security_group_id]
  }

  primary_container {
    image          = "${local.base.ecr_repository_url}:${var.image_tag}"
    container_port = var.container_port

    aws_logs_configuration {
      log_group         = local.base.service_log_group
      log_stream_prefix = "service"
    }

    environment {
      name  = "DB_POOL_MIN"
      value = tostring(var.db_pool_min)
    }

    environment {
      name  = "DB_POOL_MAX"
      value = tostring(var.db_pool_max)
    }

    environment {
      name  = "MAX_RADIUS_M"
      value = tostring(var.max_radius_m)
    }

    secret {
      name       = "DATABASE_URL"
      value_from = "${local.base.app_secret_arn}:DATABASE_URL::"
    }
  }

  scaling_target {
    auto_scaling_metric       = "AVERAGE_CPU"
    auto_scaling_target_value = var.cpu_target_percent
    min_task_count            = var.min_tasks
    max_task_count            = var.max_tasks
  }

  lifecycle {
    precondition {
      condition     = var.db_pool_max * var.max_tasks <= 50
      error_message = "db_pool_max × max_tasks exceeds the 50-connection database budget (spec RNF-002, plan D-015)."
    }
  }
}

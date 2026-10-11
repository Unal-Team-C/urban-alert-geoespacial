# terraform test with mocked providers and a fake base state: no AWS credentials, no real resources.
mock_provider "aws" {}

override_data {
  target = data.terraform_remote_state.base
  values = {
    outputs = {
      name                    = "urban-alert-geoespacial"
      cluster_name            = "urban-alert-geoespacial"
      execution_role_arn      = "arn:aws:iam::348364742283:role/urban-alert-ecs-execution-role"
      infrastructure_role_arn = "arn:aws:iam::348364742283:role/urban-alert-ecs-infrastructure-role"
      subnet_ids              = ["subnet-aaaa", "subnet-bbbb"]
      tasks_security_group_id = "sg-tasks"
      ecr_repository_url      = "348364742283.dkr.ecr.us-east-2.amazonaws.com/urban-alert-geoespacial"
      service_log_group       = "/ecs/urban-alert-geoespacial"
      app_secret_arn          = "arn:aws:secretsmanager:us-east-2:348364742283:secret:urban-alert-geoespacial-db-AbCdEf"
    }
  }
}

variables {
  image_tag = "0123456789abcdef"
}

run "container_matches_the_base_contract" {
  command = plan

  assert {
    condition     = aws_ecs_express_gateway_service.this.primary_container[0].container_port == 8000
    error_message = "The service listens on port 8000."
  }

  assert {
    condition     = aws_ecs_express_gateway_service.this.health_check_path == "/health"
    error_message = "The load balancer must check /health."
  }

  assert {
    condition     = aws_ecs_express_gateway_service.this.primary_container[0].image == "348364742283.dkr.ecr.us-east-2.amazonaws.com/urban-alert-geoespacial:0123456789abcdef"
    error_message = "The image must be the ECR repository tagged with the commit SHA."
  }
}

run "database_url_comes_from_the_secret" {
  command = plan

  assert {
    condition = anytrue([
      for s in aws_ecs_express_gateway_service.this.primary_container[0].secret :
      s.name == "DATABASE_URL" && s.value_from == "arn:aws:secretsmanager:us-east-2:348364742283:secret:urban-alert-geoespacial-db-AbCdEf:DATABASE_URL::"
    ])
    error_message = "DATABASE_URL must be injected from the app secret (RF-001)."
  }

  assert {
    condition     = alltrue([for e in aws_ecs_express_gateway_service.this.primary_container[0].environment : e.name != "DATABASE_URL"])
    error_message = "DATABASE_URL must never be a plain environment variable."
  }
}

run "connection_budget_within_50" {
  command = plan

  assert {
    condition     = var.db_pool_max * var.max_tasks <= 50
    error_message = "Default sizing must respect the 50-connection budget."
  }

  assert {
    condition     = contains([for e in aws_ecs_express_gateway_service.this.primary_container[0].environment : "${e.name}=${e.value}"], "DB_POOL_MAX=5")
    error_message = "Tasks must run with DB_POOL_MAX=5."
  }
}

run "connection_budget_exceeded_is_rejected" {
  command = plan

  variables {
    db_pool_max = 6
    max_tasks   = 10
  }

  expect_failures = [aws_ecs_express_gateway_service.this]
}

run "endpoint_is_a_bare_host" {
  command = apply

  override_resource {
    target = aws_ecs_express_gateway_service.this
    values = {
      service_name  = "urban-alert-geoespacial"
      ingress_paths = [{ access_type = "PRIVATE", endpoint = "https://urban-alert-geoespacial-abc.ecs.us-east-2.on.aws/" }]
    }
  }

  assert {
    condition     = output.service_endpoint == "urban-alert-geoespacial-abc.ecs.us-east-2.on.aws"
    error_message = "service_endpoint must be the host only (no scheme, no trailing slash)."
  }
}

run "endpoint_without_scheme_is_kept" {
  command = apply

  override_resource {
    target = aws_ecs_express_gateway_service.this
    values = {
      service_name  = "urban-alert-geoespacial"
      ingress_paths = [{ access_type = "PRIVATE", endpoint = "urban-alert-geoespacial-abc.ecs.us-east-2.on.aws" }]
    }
  }

  assert {
    condition     = output.service_endpoint == "urban-alert-geoespacial-abc.ecs.us-east-2.on.aws"
    error_message = "A host without scheme must be returned unchanged."
  }
}

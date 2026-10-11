# terraform test with mocked providers: no AWS credentials, no real resources.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "348364742283" }
  }

  mock_resource "aws_db_instance" {
    defaults = {
      address            = "urban-alert-geoespacial-db.example.us-east-2.rds.amazonaws.com"
      port               = 5432
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:us-east-2:348364742283:secret:rds!db-mock", kms_key_id = "", secret_status = "active" }]
    }
  }

}

mock_provider "random" {}

# Platform contract (SSM). StringList values are comma-separated.
override_data {
  target = data.aws_ssm_parameter.vpc_id
  values = { value = "vpc-plataforma" }
}

override_data {
  target = data.aws_ssm_parameter.private_subnets
  values = { value = "subnet-priv-a,subnet-priv-b,subnet-priv-c" }
}

# Resources in imports.tf cannot be imported from a mock provider: give them fixed values instead.
override_resource {
  target = aws_ecr_repository.this
  values = { repository_url = "348364742283.dkr.ecr.us-east-2.amazonaws.com/urban-alert-geoespacial" }
}

override_resource {
  target = aws_iam_role.execution
  values = { arn = "arn:aws:iam::348364742283:role/urban-alert-ecs-execution-role", id = "urban-alert-ecs-execution-role" }
}

override_resource {
  target = aws_iam_role.infrastructure
  values = { arn = "arn:aws:iam::348364742283:role/urban-alert-ecs-infrastructure-role", id = "urban-alert-ecs-infrastructure-role" }
}

override_resource {
  target = aws_iam_role_policy_attachment.execution_managed
}

override_resource {
  target = aws_iam_role_policy_attachment.infrastructure_managed
}

override_resource {
  target = aws_iam_role_policy.execution_secrets
}

variables {
  image_tag = "0123456789abcdef"
}

run "defaults_protect_data" {
  command = apply

  assert {
    condition     = aws_db_instance.this.deletion_protection
    error_message = "RDS must have deletion protection unless allow_destroy is set (RNF-007)."
  }

  assert {
    condition     = !aws_ecr_repository.this.force_delete
    error_message = "ECR must not be force-deletable unless allow_destroy is set."
  }

  assert {
    condition     = !aws_db_instance.this.skip_final_snapshot
    error_message = "A final snapshot must always be taken (RF-013b)."
  }
}

run "database_is_private_encrypted_and_backed_up" {
  command = apply

  assert {
    condition     = !aws_db_instance.this.publicly_accessible
    error_message = "RDS must not be publicly accessible (RNF-001)."
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted
    error_message = "RDS storage must be encrypted."
  }

  assert {
    condition     = aws_db_instance.this.backup_retention_period >= 7
    error_message = "Backups must be kept at least 7 days (RNF-007)."
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password
    error_message = "The master password must be managed by RDS in Secrets Manager."
  }
}

run "only_tasks_reach_the_database" {
  command = apply

  assert {
    condition     = aws_vpc_security_group_ingress_rule.rds_from_tasks.referenced_security_group_id == aws_security_group.tasks.id
    error_message = "The RDS ingress rule must reference the tasks security group."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.rds_from_tasks.cidr_ipv4 == null
    error_message = "The RDS ingress rule must not allow a CIDR range."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.rds_from_tasks.from_port == 5432 && aws_vpc_security_group_ingress_rule.rds_from_tasks.to_port == 5432
    error_message = "The RDS ingress rule must only open PostgreSQL."
  }
}

run "uses_the_shared_private_network" {
  command = apply

  assert {
    condition     = aws_security_group.tasks.vpc_id == "vpc-plataforma" && aws_security_group.rds.vpc_id == "vpc-plataforma"
    error_message = "Security groups must live in the platform VPC read from SSM (RF-019)."
  }

  assert {
    condition     = toset(aws_db_subnet_group.this.subnet_ids) == toset(["subnet-priv-a", "subnet-priv-b", "subnet-priv-c"])
    error_message = "RDS must use every private subnet of the platform."
  }

  assert {
    condition     = output.subnet_ids == tolist(["subnet-priv-a", "subnet-priv-b", "subnet-priv-c"])
    error_message = "The service and the schema task must get every private subnet."
  }
}

run "app_secret_requires_tls_and_is_recreatable" {
  command = apply

  assert {
    condition     = aws_secretsmanager_secret.app.recovery_window_in_days == 0
    error_message = "The app secret must be deleted immediately so it can be recreated after deprovisioning."
  }

  assert {
    condition     = endswith(jsondecode(aws_secretsmanager_secret_version.app.secret_string).DATABASE_URL, "?sslmode=require")
    error_message = "DATABASE_URL must require TLS (RF-002)."
  }
}

run "allow_destroy_lifts_protection_and_names_the_snapshot" {
  command = apply

  variables {
    allow_destroy         = true
    final_snapshot_suffix = "123456"
  }

  assert {
    condition     = !aws_db_instance.this.deletion_protection
    error_message = "allow_destroy must disable deletion protection."
  }

  assert {
    condition     = aws_ecr_repository.this.force_delete
    error_message = "allow_destroy must let ECR be deleted with its images."
  }

  assert {
    condition     = aws_db_instance.this.final_snapshot_identifier == "urban-alert-geoespacial-final-123456"
    error_message = "The final snapshot must be named after the workflow run."
  }
}

run "name_must_keep_the_pipeline_prefix" {
  command = plan

  variables {
    name = "geoespacial"
  }

  expect_failures = [var.name]
}

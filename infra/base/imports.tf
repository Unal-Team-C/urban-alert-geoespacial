# One-shot imports of the resources created by hand (infra/INVENTARIO.md). Delete this file after the first
# successful apply (task T025): a permanent import block would fail once deprovisioning has removed them.
import {
  to = aws_ecr_repository.this
  id = "urban-alert-geoespacial"
}

import {
  to = aws_iam_role.execution
  id = "urban-alert-ecs-execution-role"
}

import {
  to = aws_iam_role_policy_attachment.execution_managed
  id = "urban-alert-ecs-execution-role/arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

import {
  to = aws_iam_role_policy.execution_secrets
  id = "urban-alert-ecs-execution-role:read-project-secrets"
}

import {
  to = aws_iam_role.infrastructure
  id = "urban-alert-ecs-infrastructure-role"
}

import {
  to = aws_iam_role_policy_attachment.infrastructure_managed
  id = "urban-alert-ecs-infrastructure-role/arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

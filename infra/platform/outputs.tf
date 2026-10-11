# Read by the workflows (scripts/run-schema-task.sh, docker push) and by the service stack (terraform_remote_state).
output "region" {
  value = var.region
}

output "name" {
  value = var.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.this.repository_url
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "subnet_ids" {
  value = data.aws_subnets.default.ids
}

output "tasks_security_group_id" {
  value = aws_security_group.tasks.id
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "infrastructure_role_arn" {
  value = aws_iam_role.infrastructure.arn
}

output "app_secret_arn" {
  value = aws_secretsmanager_secret.app.arn
}

output "service_log_group" {
  value = aws_cloudwatch_log_group.service.name
}

output "schema_task_definition_arn" {
  value = aws_ecs_task_definition.schema.arn
}

output "schema_container_name" {
  value = local.schema_container
}

output "schema_log_group" {
  value = aws_cloudwatch_log_group.schema.name
}

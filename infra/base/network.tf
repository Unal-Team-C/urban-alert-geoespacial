# Shared private network of the UrbanAlert platform (repo urban-alert-plataforma, contract in SSM; plan D-021).
# Fails with ParameterNotFound when the platform is not provisioned (the workflow checks it first, D-025).
# Tasks have no public IP and leave through the platform NAT; RDS is only reachable from the tasks SG.
data "aws_ssm_parameter" "vpc_id" {
  name = "/urban-alert/plataforma/vpc-id"
}

data "aws_ssm_parameter" "private_subnets" {
  name = "/urban-alert/plataforma/subredes-privadas"
}

# The provider marks every SSM value as sensitive; network IDs are not secrets and are needed as outputs.
locals {
  vpc_id          = nonsensitive(data.aws_ssm_parameter.vpc_id.value)
  private_subnets = split(",", nonsensitive(data.aws_ssm_parameter.private_subnets.value))
}

resource "aws_security_group" "tasks" {
  name        = "${var.name}-tasks"
  description = "ECS tasks of ${var.name} (service and schema task)"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "tasks_all" {
  security_group_id = aws_security_group.tasks.id
  description       = "Outbound to ECR, Secrets Manager, CloudWatch and RDS"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS of ${var.name}: PostgreSQL only from the tasks security group"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_tasks" {
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from ${var.name} tasks"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.tasks.id
}

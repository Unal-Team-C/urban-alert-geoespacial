# Own cluster (plan D-019): the schema task runs before the service exists, so it cannot rely on "default".
resource "aws_ecs_cluster" "this" {
  name = var.name
}

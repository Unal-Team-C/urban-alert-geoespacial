# Password of the application role (created by the schema task). Lives in the encrypted, private Terraform state.
resource "random_password" "app" {
  length  = 32
  special = false
}

locals {
  app_db = {
    username = var.db_app_user
    password = random_password.app.result
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.db_name
  }
}

# recovery_window_in_days = 0: deleted immediately on deprovision, so the next provision can recreate the name.
resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.name}-db"
  description             = "Connection of ${var.name} to its database (application role, TLS required)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id = aws_secretsmanager_secret.app.id
  secret_string = jsonencode(merge(local.app_db, {
    DATABASE_URL = "postgresql://${local.app_db.username}:${local.app_db.password}@${local.app_db.host}:${local.app_db.port}/${local.app_db.dbname}?sslmode=require"
  }))
}

# Imported (infra/INVENTARIO.md). force_delete only when the deprovision workflow sets allow_destroy.
resource "aws_ecr_repository" "this" {
  name                 = var.name
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.allow_destroy

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last ${var.ecr_keep_images} images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.ecr_keep_images
      }
      action = { type = "expire" }
    }]
  })
}

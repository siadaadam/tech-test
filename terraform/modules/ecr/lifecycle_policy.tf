locals {
  default_lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after ${var.untagged_image_expiry_days} days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_image_expiry_days
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep at most ${var.max_image_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = {
          type = "expire"
        }
      },
    ]
  })

  lifecycle_policies = {
    for name, repo in var.repositories : name => coalesce(repo.lifecycle_policy, local.default_lifecycle_policy)
    if repo.enable_lifecycle_policy
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = local.lifecycle_policies

  repository = aws_ecr_repository.this[each.key].name
  policy     = each.value
}

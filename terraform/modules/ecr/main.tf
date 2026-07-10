locals {
  kms_key_arn = var.kms_key_arn != null ? var.kms_key_arn : (var.create_kms_key ? aws_kms_key.this[0].arn : null)

  repositories_with_read_principals = {
    for name, repo in var.repositories : name => distinct(concat(var.read_principal_arns, repo.read_principal_arns))
    if length(distinct(concat(var.read_principal_arns, repo.read_principal_arns))) > 0
  }
}

resource "aws_kms_key" "this" {
  count = var.kms_key_arn == null && var.create_kms_key ? 1 : 0

  description             = "ECR image encryption key for ${var.name}"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.name}-ecr"
  })
}

resource "aws_kms_alias" "this" {
  count = var.kms_key_arn == null && var.create_kms_key ? 1 : 0

  name          = "alias/${var.name}-ecr"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_ecr_repository" "this" {
  for_each = var.repositories

  name                 = each.key
  image_tag_mutability = each.value.image_tag_mutability
  force_delete         = each.value.force_delete

  image_scanning_configuration {
    scan_on_push = each.value.scan_on_push
  }

  encryption_configuration {
    encryption_type = local.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = local.kms_key_arn != null ? local.kms_key_arn : null
  }

  tags = merge(var.tags, each.value.tags)
}

data "aws_iam_policy_document" "read_access" {
  for_each = local.repositories_with_read_principals

  statement {
    sid    = "AllowCrossAccountPull"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = each.value
    }

    actions = [
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:BatchCheckLayerAvailability",
    ]
  }
}

resource "aws_ecr_repository_policy" "read_access" {
  for_each = local.repositories_with_read_principals

  repository = aws_ecr_repository.this[each.key].name
  policy     = data.aws_iam_policy_document.read_access[each.key].json
}

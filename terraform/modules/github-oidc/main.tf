locals {
  oidc_url = "https://token.actions.githubusercontent.com"

  oidc_provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.existing[0].arn

  has_ecr_permissions = length(var.ecr_repository_arns) > 0
  has_eks_permissions = length(var.eks_cluster_arns) > 0
}

# GitHub rotates the certificate this thumbprint is derived from
# periodically; AWS itself no longer strictly validates it for GitHub's
# provider, but the resource still requires a value, so it's fetched live
# instead of hardcoding a thumbprint that will eventually go stale.
data "tls_certificate" "github" {
  url = local.oidc_url
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url             = local.oidc_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]

  tags = var.tags
}

data "aws_iam_openid_connect_provider" "existing" {
  count = var.create_oidc_provider ? 0 : 1

  url = local.oidc_url
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # StringLike (not StringEquals) so allowed_refs entries may use
    # wildcards, e.g. "refs/tags/v*" for a future release-tag pipeline.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for ref in var.allowed_refs : "repo:${var.github_org}/${var.github_repo}:ref:${ref}"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

data "aws_iam_policy_document" "permissions" {
  count = local.has_ecr_permissions || local.has_eks_permissions ? 1 : 0

  dynamic "statement" {
    for_each = local.has_ecr_permissions ? [1] : []
    content {
      sid    = "ECRAuth"
      effect = "Allow"
      # GetAuthorizationToken is account-wide and does not support
      # resource-level scoping - AWS requires Resource = "*" for it.
      actions   = ["ecr:GetAuthorizationToken"]
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = local.has_ecr_permissions ? [1] : []
    content {
      sid    = "ECRPush"
      effect = "Allow"
      actions = [
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:BatchGetImage",
      ]
      resources = var.ecr_repository_arns
    }
  }

  dynamic "statement" {
    for_each = local.has_eks_permissions ? [1] : []
    content {
      sid       = "EKSDescribe"
      effect    = "Allow"
      actions   = ["eks:DescribeCluster"]
      resources = var.eks_cluster_arns
    }
  }
}

resource "aws_iam_policy" "permissions" {
  count = local.has_ecr_permissions || local.has_eks_permissions ? 1 : 0

  name   = "${var.role_name}-permissions"
  policy = data.aws_iam_policy_document.permissions[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "permissions" {
  count = local.has_ecr_permissions || local.has_eks_permissions ? 1 : 0

  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.permissions[0].arn
}

resource "aws_iam_role_policy_attachment" "additional" {
  # Keyed by index rather than toset(var.policy_arns): the key set must be
  # known at plan time, but a policy ARN created in the same apply (e.g. a
  # sibling module's aws_iam_policy) commonly isn't - see the same fix in
  # terraform/modules/iam for the full explanation.
  for_each = { for idx, arn in var.policy_arns : tostring(idx) => arn }

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

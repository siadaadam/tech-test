data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  # Keyed by index rather than toset(var.policy_arns): the ARNs are commonly
  # not yet known at plan time (e.g. on a first apply that creates the sqs
  # module's policies in the same run), and for_each requires its key set -
  # unlike individual values - to be known up front. An index-keyed map's
  # keys are static, so only the (possibly unknown) value has to wait.
  for_each = { for idx, arn in var.policy_arns : tostring(idx) => arn }

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

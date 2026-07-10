output "role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes via OIDC."
  value       = aws_iam_role.this.arn
}

output "oidc_provider_arn" {
  description = "ARN of the token.actions.githubusercontent.com OIDC provider (created or looked up)."
  value       = local.oidc_provider_arn
}

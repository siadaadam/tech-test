output "repository_arns" {
  description = "ARNs of the created repositories, keyed by repository name."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "repository_urls" {
  description = "Repository URLs (for docker push/pull), keyed by repository name."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_registry_ids" {
  description = "Registry (account) IDs the repositories belong to, keyed by repository name."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.registry_id }
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for image encryption, if one was created or provided."
  value       = local.kms_key_arn
}

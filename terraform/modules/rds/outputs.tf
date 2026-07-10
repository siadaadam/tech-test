output "db_instance_id" {
  description = "ID of the RDS instance."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "ARN of the RDS instance."
  value       = aws_db_instance.this.arn
}

output "endpoint" {
  description = "Connection endpoint for the instance, in host:port form."
  value       = aws_db_instance.this.endpoint
}

output "address" {
  description = "Hostname of the instance, without the port."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port the instance accepts connections on."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the default database created on the instance."
  value       = aws_db_instance.this.db_name
}

output "security_group_id" {
  description = "ID of the security group attached to the instance."
  value       = aws_security_group.this.id
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret holding the connection credentials/URL. Sync this into your cluster with something like the External Secrets Operator; the password/URL are never exposed as module outputs."
  value       = aws_secretsmanager_secret.this.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for storage encryption, Performance Insights, and the Secrets Manager secret."
  value       = local.kms_key_arn
}

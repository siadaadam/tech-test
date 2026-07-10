resource "random_password" "master" {
  length = 32

  special = true
  # Avoid characters that are reserved/unsafe in a postgres:// connection URL
  # or would otherwise need percent-encoding: / @ " ' and space are excluded.
  override_special = "!#$%^&*()-_=+[]{}<>?~"

  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
}

resource "aws_secretsmanager_secret" "this" {
  name       = "${var.identifier}-credentials"
  kms_key_id = local.kms_key_arn

  tags = var.tags
}

# JSON blob intended to be synced into a Kubernetes Secret by something like
# the External Secrets Operator, which then populates the banking-app
# container's DATABASE_URL env var from the "url" field.
resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id

  secret_string = jsonencode({
    engine   = "postgres"
    username = var.master_username
    password = random_password.master.result
    host     = aws_db_instance.this.address
    port     = aws_db_instance.this.port
    dbname   = var.db_name
    url      = "postgres://${var.master_username}:${random_password.master.result}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}?sslmode=require"
  })
}

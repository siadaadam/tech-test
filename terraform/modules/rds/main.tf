locals {
  kms_key_arn = var.kms_key_arn != null ? var.kms_key_arn : (var.create_kms_key ? aws_kms_key.this[0].arn : null)

  # e.g. "16.4" -> "postgres16", used as the DB parameter group family.
  parameter_group_family = "postgres${split(".", var.engine_version)[0]}"
}

resource "aws_kms_key" "this" {
  count = var.kms_key_arn == null && var.create_kms_key ? 1 : 0

  description             = "RDS storage/Performance Insights/secret encryption key for ${var.identifier}"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.identifier}-rds"
  })
}

resource "aws_kms_alias" "this" {
  count = var.kms_key_arn == null && var.create_kms_key ? 1 : 0

  name          = "alias/${var.identifier}-rds"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.identifier}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, {
    Name = "${var.identifier}-subnet-group"
  })
}

resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.identifier}-"
  family      = local.parameter_group_family
  description = "Parameter group for ${var.identifier}"

  parameter {
    name  = "log_min_duration_statement"
    value = var.log_min_duration_statement
  }

  # Reject unencrypted client connections.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  dynamic "parameter" {
    for_each = var.additional_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier = var.identifier

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = var.storage_type
  storage_encrypted     = true
  kms_key_id            = local.kms_key_arn

  db_name  = var.db_name
  username = var.master_username
  password = random_password.master.result
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az                  = var.multi_az
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.identifier}-final"

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window
  apply_immediately       = var.apply_immediately

  auto_minor_version_upgrade = true

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? local.kms_key_arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  tags = merge(var.tags, {
    Name = var.identifier
  })

  lifecycle {
    # The master password is generated once by random_password and then handed
    # off to Secrets Manager; ignore drift here so an out-of-band rotation of
    # the secret doesn't fight with Terraform on subsequent applies.
    ignore_changes = [password]
  }
}

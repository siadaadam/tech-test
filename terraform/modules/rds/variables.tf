## Core

variable "identifier" {
  description = "Identifier for the RDS instance. Also used to derive names for the subnet group, parameter group, security group, IAM monitoring role, and Secrets Manager secret."
  type        = string
}

variable "engine_version" {
  description = <<-EOT
    PostgreSQL engine version, e.g. "16.4". Required, with no default: AWS
    periodically deprecates and retires RDS engine versions, so baking a
    default into this module risks it going stale. Check currently supported
    versions before setting this:

      aws rds describe-db-engine-versions --engine postgres --query "DBEngineVersions[].EngineVersion"
  EOT
  type        = string
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage, in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper limit, in GiB, that storage autoscaling is allowed to grow allocated_storage to. Set equal to allocated_storage to effectively disable autoscaling."
  type        = number
  default     = 100
}

variable "storage_type" {
  description = "Underlying EBS storage type for the instance."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage_type)
    error_message = "storage_type must be one of: gp2, gp3, io1, io2."
  }
}

variable "multi_az" {
  description = "Whether to deploy a synchronously replicated standby in a second Availability Zone for automatic failover."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Whether to enable deletion protection on the instance, preventing accidental deletion via Terraform or the console."
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Whether to skip taking a final DB snapshot when the instance is destroyed. This should only be set to true for throwaway/dev environments; leave it false for anything holding real data."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups."
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Preferred daily UTC time range for automated backups, e.g. \"03:00-04:00\". Should not overlap maintenance_window."
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred weekly UTC time range for system maintenance, e.g. \"mon:04:30-mon:05:30\". Should not overlap backup_window."
  type        = string
  default     = "mon:04:30-mon:05:30"
}

variable "apply_immediately" {
  description = "Whether to apply changes immediately instead of waiting for the next maintenance window. Leave false in production to avoid unexpected downtime."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Whether to enable Performance Insights, encrypted with this module's KMS key."
  type        = bool
  default     = true
}

variable "performance_insights_retention_period" {
  description = "Retention period, in days, for Performance Insights data. Ignored if performance_insights_enabled is false."
  type        = number
  default     = 7
}

variable "monitoring_interval" {
  description = "Interval, in seconds, between Enhanced Monitoring metric collections. Set to 0 to disable Enhanced Monitoring (and skip creating its IAM role)."
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

## Database / credentials

variable "db_name" {
  description = "Name of the default database created on the instance."
  type        = string
  default     = "banking"
}

variable "master_username" {
  description = "Master username for the instance."
  type        = string
  default     = "banking"
}

## Networking

variable "vpc_id" {
  description = "VPC in which the instance and its dedicated security group will run."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group. Should be private subnets across at least two Availability Zones, e.g. the vpc module's private_subnet_ids_list output."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = <<-EOT
    Security group IDs allowed to reach the instance on port 5432, one ingress
    rule created per entry. When composing with the eks module, pass
    module.eks.cluster_security_group_id here: EKS managed node groups
    automatically attach the cluster's primary security group to node ENIs, so
    this is sufficient to let pods reach the database.
  EOT
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the instance on port 5432, for cases without a source security group (e.g. a bastion host)."
  type        = list(string)
  default     = []
}

## Parameter group

variable "log_min_duration_statement" {
  description = "Minimum statement execution time, in milliseconds, above which statements are logged. Set to -1 to disable statement duration logging."
  type        = number
  default     = 1000
}

variable "additional_parameters" {
  description = "Additional DB parameter group parameters, beyond this module's baseline (log_min_duration_statement, rds.force_ssl)."
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

## Encryption

variable "create_kms_key" {
  description = "Whether to create a KMS key used for storage encryption, Performance Insights, and the Secrets Manager secret. Ignored if kms_key_arn is set."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key to use instead of creating one. Takes precedence over create_kms_key."
  type        = string
  default     = null
}

variable "kms_key_deletion_window_in_days" {
  description = "Deletion window for the KMS key created for this instance."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}

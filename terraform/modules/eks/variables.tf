## Cluster

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to use for the EKS cluster control plane."
  type        = string
}

variable "vpc_id" {
  description = "VPC in which the cluster and its nodes will run."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs used for the cluster's ENIs and as the default subnets for node groups."
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "Subnet IDs used for the control plane ENIs only. Defaults to var.subnet_ids when empty."
  type        = list(string)
  default     = []
}

variable "endpoint_private_access" {
  description = "Whether the EKS private API server endpoint is enabled."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Whether the EKS public API server endpoint is enabled."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the public API server endpoint, when enabled."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  description = "Control plane log types to enable and ship to CloudWatch Logs."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cloudwatch_log_retention_in_days" {
  description = "Retention period for the cluster's CloudWatch log group."
  type        = number
  default     = 90
}

## Encryption

variable "create_kms_key" {
  description = "Whether to create a KMS key for EKS secrets envelope encryption. Ignored if kms_key_arn is set."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key to use for secrets envelope encryption. Takes precedence over create_kms_key."
  type        = string
  default     = null
}

variable "kms_key_deletion_window_in_days" {
  description = "Deletion window for the KMS key created for this cluster."
  type        = number
  default     = 30
}

## Access management (EKS access entries, replaces the aws-auth ConfigMap)

variable "authentication_mode" {
  description = "Cluster authentication mode: API, API_AND_CONFIG_MAP, or CONFIG_MAP."
  type        = string
  default     = "API"

  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP", "CONFIG_MAP"], var.authentication_mode)
    error_message = "authentication_mode must be one of: API, API_AND_CONFIG_MAP, CONFIG_MAP."
  }
}

variable "bootstrap_cluster_creator_admin_permissions" {
  description = "Whether the IAM principal creating the cluster is granted cluster-admin access entry automatically."
  type        = bool
  default     = true
}

variable "access_entries" {
  description = <<-EOT
    Map of EKS access entries keyed by an arbitrary name. Each entry grants an IAM principal
    cluster access and associates it with one or more access policies.
  EOT
  type = map(object({
    principal_arn     = string
    kubernetes_groups = optional(list(string), [])
    type              = optional(string, "STANDARD")
    policy_associations = optional(map(object({
      policy_arn = string
      namespaces = optional(list(string), [])
    })), {})
  }))
  default = {}
}

## Security groups

variable "cluster_security_group_additional_rules" {
  description = "Additional security group rules to add to the cluster's primary security group."
  type = map(object({
    description              = string
    type                     = string
    protocol                 = string
    from_port                = number
    to_port                  = number
    cidr_blocks              = optional(list(string))
    source_security_group_id = optional(string)
    self                     = optional(bool)
  }))
  default = {}
}

## Node groups

variable "node_groups" {
  description = "Map of managed node group configurations keyed by an arbitrary name."
  type = map(object({
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    capacity_type  = optional(string, "ON_DEMAND")
    instance_types = optional(list(string), ["t3.medium"])
    disk_size      = optional(number, 50)

    min_size     = optional(number, 1)
    max_size     = optional(number, 3)
    desired_size = optional(number, 2)

    max_unavailable = optional(number, 1)

    subnet_ids                           = optional(list(string), [])
    additional_security_group_ids        = optional(list(string), [])
    metadata_http_put_response_hop_limit = optional(number, 2)

    labels = optional(map(string), {})
    taints = optional(map(object({
      key    = string
      value  = optional(string)
      effect = string
    })), {})

    tags = optional(map(string), {})
  }))
  default = {}
}

## Add-ons

variable "addons" {
  description = <<-EOT
    Configuration for the standard EKS add-ons. Set `enabled = false` to skip an add-on,
    or `version = null` (default) to track the most recent version compatible with the cluster.
  EOT
  type = object({
    vpc_cni = optional(object({
      enabled                     = optional(bool, true)
      version                     = optional(string)
      resolve_conflicts_on_update = optional(string, "OVERWRITE")
    }), {})
    kube_proxy = optional(object({
      enabled                     = optional(bool, true)
      version                     = optional(string)
      resolve_conflicts_on_update = optional(string, "OVERWRITE")
    }), {})
    coredns = optional(object({
      enabled                     = optional(bool, true)
      version                     = optional(string)
      resolve_conflicts_on_update = optional(string, "OVERWRITE")
    }), {})
    aws_ebs_csi_driver = optional(object({
      enabled                     = optional(bool, true)
      version                     = optional(string)
      resolve_conflicts_on_update = optional(string, "OVERWRITE")
    }), {})
  })
  default = {}
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}

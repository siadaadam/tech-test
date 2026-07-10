variable "role_name" {
  description = "Name of the IAM role to create."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's IAM OIDC provider (the eks module's oidc_provider_arn output)."
  type        = string
}

variable "oidc_provider_url" {
  description = "OIDC issuer URL of the cluster (the eks module's cluster_oidc_issuer_url output). The https:// prefix is stripped internally if present."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the service account allowed to assume this role."
  type        = string
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account allowed to assume this role. Exactly one namespace/service-account pair can assume a given role - this is what makes IRSA least-privilege per-workload rather than per-node."
  type        = string
}

variable "policy_arns" {
  description = "IAM policy ARNs to attach to the role (e.g. the producer_policy_arn / consumer_policy_arn outputs of the sqs module)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the role."
  type        = map(string)
  default     = {}
}

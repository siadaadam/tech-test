variable "create_oidc_provider" {
  description = "Whether to create the token.actions.githubusercontent.com OIDC provider. An AWS account can only have one provider per URL, so if another instance of this module (or something else) already created it, set this to false and it will be looked up instead."
  type        = bool
  default     = true
}

variable "github_org" {
  description = "GitHub organization or user that owns the repository."
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name (without the org/ prefix)."
  type        = string
}

variable "allowed_refs" {
  description = "Git refs allowed to assume this role, e.g. [\"refs/heads/main\"]. Restricting this at the AWS trust-policy level means only workflow runs on these refs can ever get credentials - not just \"the workflow happens to check the branch,\" but AWS itself refusing the AssumeRoleWithWebIdentity call for anything else (PRs, other branches, forks)."
  type        = list(string)
  default     = ["refs/heads/main"]
}

variable "role_name" {
  description = "Name of the IAM role GitHub Actions will assume."
  type        = string
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs this role may push images to. Leave empty to grant no ECR permissions."
  type        = list(string)
  default     = []
}

variable "eks_cluster_arns" {
  description = "EKS cluster ARNs this role may call eks:DescribeCluster on (needed for `aws eks update-kubeconfig`). Leave empty to grant no EKS permissions. Note this only grants AWS-API-level access to fetch cluster connection info - actual Kubernetes RBAC access (what kubectl/helm can do once connected) is separate and must be granted via the eks module's access_entries variable."
  type        = list(string)
  default     = []
}

variable "policy_arns" {
  description = "Additional managed IAM policy ARNs to attach, for anything beyond the built-in ECR/EKS statements."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the role (and the OIDC provider, if created)."
  type        = map(string)
  default     = {}
}

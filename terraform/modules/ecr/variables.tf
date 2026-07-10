variable "name" {
  description = "Name prefix for this module instance, used to name the shared KMS key/alias when create_kms_key is true. Only needs to be unique if the module is instantiated more than once in the same account/region."
  type        = string
  default     = "ecr"
}

## Repositories

variable "repositories" {
  description = "Map of ECR repositories to create, keyed by repository name."
  type = map(object({
    image_tag_mutability = optional(string, "IMMUTABLE")
    scan_on_push         = optional(bool, true)
    force_delete         = optional(bool, false)

    enable_lifecycle_policy = optional(bool, true)
    lifecycle_policy        = optional(string) # raw JSON; overrides the generated default policy when set

    read_principal_arns = optional(list(string), [])

    tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in var.repositories : contains(["MUTABLE", "IMMUTABLE"], r.image_tag_mutability)
    ])
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}

## Encryption

variable "create_kms_key" {
  description = "Whether to create a KMS key for ECR image encryption, shared by all repositories in this module. Ignored if kms_key_arn is set."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key to use for image encryption. Takes precedence over create_kms_key. If neither is set, repositories use AWS-managed (AES256) encryption."
  type        = string
  default     = null
}

variable "kms_key_deletion_window_in_days" {
  description = "Deletion window for the KMS key created for these repositories."
  type        = number
  default     = 30
}

## Lifecycle policy defaults (used unless a repository sets its own lifecycle_policy)

variable "untagged_image_expiry_days" {
  description = "Expire untagged images older than this many days."
  type        = number
  default     = 14
}

variable "max_image_count" {
  description = "Maximum number of images (tagged or untagged) to retain per repository; older images beyond this count are expired."
  type        = number
  default     = 100
}

## Cross-account access

variable "read_principal_arns" {
  description = "IAM principal ARNs (accounts or roles) granted pull access to every repository in this module, in addition to any repository-specific read_principal_arns."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}

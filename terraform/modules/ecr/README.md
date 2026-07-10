# ecr

Provisions one or more ECR repositories: KMS-encrypted images, scan-on-push,
a sensible default lifecycle policy (expire old untagged images, cap total
image count), and optional cross-account pull access.

## Default lifecycle policy

Applied to every repository unless it sets its own `lifecycle_policy` or sets
`enable_lifecycle_policy = false`:

1. Expire untagged images older than `var.untagged_image_expiry_days` (default 14).
2. Once a repository exceeds `var.max_image_count` images (default 100),
   expire the oldest ones first.

## Example

```hcl
module "ecr" {
  source = "../../modules/ecr"

  name = "my-app" # only used to name the shared KMS key/alias

  repositories = {
    api = {
      scan_on_push = true
    }
    worker = {
      image_tag_mutability = "MUTABLE"
      read_principal_arns  = ["arn:aws:iam::222222222222:root"] # shared with a CI/deploy account
    }
  }

  read_principal_arns = ["arn:aws:iam::333333333333:root"] # granted pull on every repo above

  tags = {
    Environment = "production"
  }
}
```

## Notes

- `image_tag_mutability` defaults to `IMMUTABLE` — set to `MUTABLE` per
  repository if you rely on floating tags like `latest`.
- All repositories in a module instance share one KMS key by default. Set
  `create_kms_key = false` and leave `kms_key_arn` unset to fall back to
  AWS-managed (AES256) encryption instead.
- `read_principal_arns` (global) and each repository's own
  `read_principal_arns` are merged, so you can grant broad access to every
  repository and extend specific ones further.

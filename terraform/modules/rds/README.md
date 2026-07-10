# rds

Provisions a production-ready Amazon RDS for PostgreSQL instance for the
banking-app: KMS-encrypted storage, Multi-AZ by default, automated backups,
Performance Insights + Enhanced Monitoring, a dedicated (default-deny)
security group, a baseline parameter group, and master credentials generated
and stored in Secrets Manager rather than ever appearing in Terraform state
as an output.

## Notable behavior

| Concern | Behavior |
|---|---|
| Credentials | `random_password` generates a 32-character master password (excluding `/ @ " '` and space, so it never needs URL-encoding). Username/password/host/port/dbname/engine and a ready-to-use `url` are written as a JSON blob to a `aws_secretsmanager_secret_version`. The password is never a module output. |
| Secret consumption | The secret is meant to be synced by something like the Kubernetes External Secrets Operator into a k8s `Secret`, which then populates the banking-app container's `DATABASE_URL` env var from the secret's `url` field. |
| Networking | The instance sits in a `aws_db_subnet_group` built from `var.subnet_ids` (private subnets) and a dedicated security group with **no ingress by default**. Ingress is opt-in via `allowed_security_group_ids` (one rule per SG) and/or `allowed_cidr_blocks`. |
| Composing with `eks` | Pass `module.eks.cluster_security_group_id` as one of `allowed_security_group_ids` — EKS managed node groups automatically attach the cluster's primary security group to node ENIs, so this is enough for pods to reach the database without a separate node security group. |
| Encryption | `storage_encrypted = true` always. Performance Insights and the Secrets Manager secret reuse the same KMS key. |
| Monitoring | Performance Insights is on by default. Enhanced Monitoring (`monitoring_interval`, default 60s) creates its own IAM role assuming `monitoring.rds.amazonaws.com`, attached to `AmazonRDSEnhancedMonitoringRole`; set `monitoring_interval = 0` to disable both the feature and the role. |
| Engine version | `engine_version` has no default — see [Notes](#notes). |
| Parameter group family | Derived from `engine_version`, e.g. `"16.4"` -> `"postgres16"`. |

## Example

```hcl
module "rds" {
  source = "../../modules/rds"

  identifier     = "banking-app-prod"
  engine_version = "16.4" # check currently supported versions before setting this

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids_list

  allowed_security_group_ids = [module.eks.cluster_security_group_id]

  instance_class          = "db.t4g.small"
  multi_az                = true
  backup_retention_period = 14

  tags = {
    Environment = "production"
    Application = "banking-app"
  }
}
```

### Throwaway/dev example

```hcl
module "rds_dev" {
  source = "../../modules/rds"

  identifier     = "banking-app-dev"
  engine_version = "16.4"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids_list

  allowed_cidr_blocks = ["10.0.0.0/16"] # e.g. a bastion/VPN CIDR

  instance_class       = "db.t4g.micro"
  multi_az             = false
  deletion_protection  = false
  skip_final_snapshot  = true # only ever set true for dev/throwaway environments

  tags = {
    Environment = "dev"
  }
}
```

## Notes

- `engine_version` has no default: AWS periodically deprecates and retires
  RDS engine versions, so baking one in risks this module going stale. Check
  currently supported versions before setting it:
  `aws rds describe-db-engine-versions --engine postgres --query "DBEngineVersions[].EngineVersion"`.
- `subnet_ids` should be private subnets across at least two Availability
  Zones, e.g. the `vpc` module's `private_subnet_ids_list` output.
- `skip_final_snapshot` defaults to `false`; only set it to `true` for
  throwaway/dev environments, since it means `terraform destroy` deletes data
  with no recovery snapshot.
- Neither the master password nor the Secrets Manager secret value is ever
  exposed as a module output — only `secret_arn` is, so callers (or an
  External Secrets Operator instance) fetch the value out-of-band.
- `additional_parameters` lets you extend the parameter group's small
  baseline (`log_min_duration_statement`, `rds.force_ssl`) without needing to
  fork the module.

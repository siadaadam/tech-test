# eks

Provisions a production-ready Amazon EKS cluster: control plane, KMS-encrypted
secrets, CloudWatch control plane logging, IRSA (OIDC), EKS access entries for
cluster access (no `aws-auth` ConfigMap), managed node groups hardened with
IMDSv2 and encrypted EBS volumes, and the standard EKS add-ons.

## Add-ons managed by this module

| Add-on               | Purpose                              | IRSA role |
|-----------------------|---------------------------------------|-----------|
| `vpc-cni`             | Pod networking                        | yes |
| `kube-proxy`          | Service networking                    | no |
| `coredns`             | Cluster DNS                           | no |
| `aws-ebs-csi-driver`  | Dynamic EBS-backed `PersistentVolume`s | yes |

Each add-on can be disabled via `var.addons.<name>.enabled = false`, and pins
to a specific version via `var.addons.<name>.version` (defaults to the latest
version compatible with the cluster's Kubernetes version).

## Example

```hcl
module "eks" {
  source = "../../modules/eks"

  cluster_name       = "my-cluster"
  kubernetes_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  node_groups = {
    default = {
      instance_types = ["m6i.large"]
      min_size       = 2
      max_size       = 5
      desired_size   = 2
    }
    spot = {
      capacity_type  = "SPOT"
      instance_types = ["m6i.large", "m6a.large", "m5.large"]
      min_size       = 0
      max_size       = 10
      desired_size   = 0
      labels         = { workload = "batch" }
      taints = {
        spot = {
          key    = "spot"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  access_entries = {
    platform_admins = {
      principal_arn = "arn:aws:iam::123456789012:role/platform-admins"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
        }
      }
    }
  }

  tags = {
    Environment = "production"
  }
}
```

## Notes

- `subnet_ids` should be private subnets across at least two Availability
  Zones; node groups fall back to these subnets unless a node group config
  specifies its own `subnet_ids`.
- Node groups accept extra security groups via
  `additional_security_group_ids`; the cluster's primary security group is
  always attached in addition to these.
- `authentication_mode` defaults to `"API"`. Set it to
  `"API_AND_CONFIG_MAP"` only if you still need to support the legacy
  `aws-auth` ConfigMap during a migration.

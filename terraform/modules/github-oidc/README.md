# github-oidc

Lets a GitHub Actions workflow assume an AWS IAM role via OIDC federation -
no long-lived AWS access keys stored as GitHub secrets. The trust policy is
scoped to specific git refs (`refs/heads/main` by default), so the role can
only ever be assumed by a workflow run on that exact branch: not a pull
request, not a fork, not a feature branch.

This is the AWS-permissions half of a CI/CD pipeline (push an image to ECR,
call `eks:DescribeCluster` to build a kubeconfig). It deliberately does
**not** grant any Kubernetes-level RBAC - what the role can do *inside* the
cluster once connected is a separate concern, granted via the `eks`
module's `access_entries` variable.

## Usage: banking-app's deploy pipeline

```hcl
module "banking_app_cicd" {
  source = "../../modules/github-oidc"

  github_org  = "your-org"
  github_repo = "tech-test"
  role_name   = "banking-app-cicd"

  ecr_repository_arns = [module.ecr.repository_arns["banking-app"]]
  eks_cluster_arns     = [module.eks.cluster_arn]

  tags = local.tags
}
```

Then grant that role Kubernetes RBAC access, scoped to just the app's
namespace (not cluster-admin), by adding it to the `eks` module's
`access_entries`:

```hcl
module "eks" {
  # ...

  access_entries = {
    banking_app_cicd = {
      principal_arn = module.banking_app_cicd.role_arn
      policy_associations = {
        edit = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
          namespaces = ["banking-app"]
        }
      }
    }
  }
}
```

`AmazonEKSEditPolicy` scoped to the `banking-app` namespace lets the CI role
create/update/delete the Deployments, Services, ConfigMaps, Secrets, etc.
that `helm upgrade` needs, without granting access to other namespaces or
cluster-scoped resources.

## Multiple pipelines, one OIDC provider

`token.actions.githubusercontent.com` can only be registered once per AWS
account. If you're instantiating this module more than once (e.g. one role
per app), set `create_oidc_provider = false` on every instance after the
first:

```hcl
module "banking_app_cicd" {
  source                = "../../modules/github-oidc"
  create_oidc_provider  = true
  # ...
}

module "some_other_app_cicd" {
  source                = "../../modules/github-oidc"
  create_oidc_provider  = false
  # ...
}
```

## Outputs

`role_arn`, `oidc_provider_arn`.

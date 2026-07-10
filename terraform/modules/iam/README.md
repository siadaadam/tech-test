# iam

Creates a single IAM role assumable via IRSA (IAM Roles for Service
Accounts) by exactly one Kubernetes namespace/service-account pair, with a
given list of policy ARNs attached. This is the piece that was missing:
`eks` creates the cluster's OIDC provider and `sqs` produces attachable
`producer`/`consumer` IAM policies, but nothing previously composed the two
into an actual role a pod could assume.

## How it works

1. `eks` creates an `aws_iam_openid_connect_provider` for the cluster's OIDC
   issuer.
2. This module's role trusts that provider, scoped by a condition on the
   OIDC token's `sub` claim: `system:serviceaccount:<namespace>:<name>`. Only
   pods running under that exact service account can assume it.
3. The Kubernetes `ServiceAccount` is annotated with
   `eks.amazonaws.com/role-arn: <this module's role_arn output>`. EKS's pod
   identity webhook then projects a token for that pod and the AWS SDK's
   default credential chain exchanges it for real credentials via
   `sts:AssumeRoleWithWebIdentity` - no code in the workload needs to know
   this is happening.

## Usage: banking-app's api and consumer roles

Least-privilege, as it should be - one role and one dedicated
`ServiceAccount` per component, so the api's role can never call
`ReceiveMessage`/`DeleteMessage` and the consumer's role can never call
`SendMessage` on the main queue:

```hcl
module "banking_app_api_irsa" {
  source = "../../modules/iam"

  role_name             = "banking-app-api"
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_provider_url     = module.eks.cluster_oidc_issuer_url
  namespace             = "banking-app"
  service_account_name  = "banking-app-api"
  policy_arns           = [module.sqs.producer_policy_arn]
  tags                  = local.tags
}

module "banking_app_consumer_irsa" {
  source = "../../modules/iam"

  role_name             = "banking-app-consumer"
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_provider_url     = module.eks.cluster_oidc_issuer_url
  namespace             = "banking-app"
  service_account_name  = "banking-app-consumer"
  policy_arns           = [module.sqs.consumer_policy_arn]
  tags                  = local.tags
}
```

Then in the Helm release: two `ServiceAccount`s (`banking-app-api`,
`banking-app-consumer`), each annotated with its respective `role_arn`
output.

### Known trade-off: the chart currently shares one ServiceAccount

`helm/banking-app` was built with **one shared `ServiceAccount`** used by
both the api and consumer Deployments (`serviceAccount.create` in
`values.yaml`), not the two-ServiceAccount split shown above - a
time-boxed simplification, not an oversight. A Kubernetes `ServiceAccount`
can only carry one `eks.amazonaws.com/role-arn` annotation, so a shared
ServiceAccount can only ever assume one role. The pragmatic fit for
today's chart is therefore a single combined role with **both** policies
attached:

```hcl
module "banking_app_irsa" {
  source = "../../modules/iam"

  role_name             = "banking-app"
  oidc_provider_arn     = module.eks.oidc_provider_arn
  oidc_provider_url     = module.eks.cluster_oidc_issuer_url
  namespace             = "banking-app"
  service_account_name  = "banking-app"
  policy_arns           = [module.sqs.producer_policy_arn, module.sqs.consumer_policy_arn]
  tags                  = local.tags
}
```

This works, but it over-privileges both pods: the api pod can technically
call `ReceiveMessage`/`DeleteMessage`/send-to-DLQ even though it never
does, and the consumer pod can technically `SendMessage` to the main queue.
**To tighten this to least privilege later**, split
`helm/banking-app/templates/serviceaccount.yaml` and the two
`deployment-*.yaml` templates to reference per-component ServiceAccounts,
then switch to the two-role setup shown above.

## Outputs

`role_arn`, `role_name`.

# CI/CD

## `deploy-banking-app.yml`

Runs on every push to `main` that touches `app/**` or `helm/banking-app/**`
(or via manual `workflow_dispatch`):

1. **test** — `go build`/`go vet`/`go test` in `app/`. Gates everything else.
2. **build-scan-push** — builds the image locally (both `api` and
   `consumer` binaries, `app/Dockerfile`), **scans it with Trivy before
   requesting any AWS credentials**, and only then assumes the AWS role via
   OIDC, logs into ECR, and pushes (tagged with the commit SHA and
   `latest`). A CRITICAL/HIGH vulnerability with an available fix fails the
   job here — the image never reaches the registry, let alone the cluster.
   Results are also uploaded to the repo's Security tab regardless of
   pass/fail, for visibility into what's currently unfixed-but-ignored too.
3. **deploy** — assumes the AWS role, points `kubectl`/`helm` at the EKS
   cluster, renders a values overlay, `helm lint`s it, then
   `helm upgrade --install --atomic --cleanup-on-fail`, followed by an
   in-cluster smoke test. See "Rollback" below for what happens if either
   step is unhappy.

Validated locally: `actionlint` (workflow syntax + embedded shellcheck)
passes clean on both workflow files, and the exact `ci-values.yaml` overlay
the deploy job generates was fed through `helm lint`/`helm template` against
the real chart and validated against the Kubernetes API schema with
`kubeconform` - all green.

## Rollback: three layers, for three different failure modes

| Layer | Trigger | Mechanism |
|---|---|---|
| 1. Automatic, rollout-health | The new ReplicaSet never becomes healthy within the timeout (e.g. `CrashLoopBackOff`, readiness probe never passes) | `--atomic --cleanup-on-fail` on `helm upgrade` - Helm rolls back itself and cleans up anything the failed release created. Nothing further runs; the job simply fails. |
| 2. Automatic, functional | The rollout reports healthy (probes pass) but the app is actually broken in a way probes can't see | The `deploy` job's own **smoke test** (an in-cluster `curlimages/curl` pod hitting `/healthz` through the Service) fails after a successful `helm upgrade`. The workflow then explicitly runs `helm rollback` to the immediately previous revision and still fails the job - a rollback happening is never silently green. |
| 3. Manual, on-demand | A human decides to revert something that passed both of the above (bad business logic, bad data, a slow leak found later) | `rollback-banking-app.yml`, triggered via `workflow_dispatch`, with an optional `revision` input (empty = previous revision). Runs `helm rollback`, which restores the *entire* previous release exactly as Helm recorded it, then re-runs the same smoke test. |

Layer 2 needs one RBAC permission beyond what plain `helm upgrade` requires:
the CI role must be able to `create`/`delete` Pods in the `banking-app`
namespace (to run the smoke-test pod), not just manage
Deployments/Services/Secrets. `AmazonEKSEditPolicy` (recommended in
`terraform/modules/github-oidc`'s README for the EKS access entry) already
covers this: `edit` includes pod create/delete within its scope, it's not
an additional grant.

## One-time setup this pipeline needs (not done for you)

Nothing below was created or configured as part of writing this pipeline -
doing so would mean either applying Terraform against a real AWS account or
changing this repository's live GitHub settings, neither of which happened
here; everything above was validated with local/fake credentials only.

**1. Apply `terraform/modules/github-oidc`**, composed with `ecr` and `eks`
as shown in that module's README, to create the actual IAM role. Also add
it to the `eks` module's `access_entries` (see the same README) so it has
Kubernetes RBAC access, not just AWS API access.

**2. Configure these repository variables** (Settings → Secrets and
variables → Actions → Variables - none of these are secret, they're just
not knowable until the infrastructure above actually exists):

| Variable | Value |
|---|---|
| `AWS_REGION` | e.g. `us-east-1` |
| `AWS_DEPLOY_ROLE_ARN` | `role_arn` output of `github-oidc` |
| `ECR_REPOSITORY` | `repository_urls["banking-app"]` output of `ecr` |
| `EKS_CLUSTER_NAME` | `cluster_id` output of `eks` |
| `DATABASE_SECRET_NAME` | name of the k8s Secret populated from `rds`'s Secrets Manager secret (e.g. by External Secrets Operator) |
| `SQS_QUEUE_URL` | `queue_url` output of `sqs` |
| `SQS_DLQ_URL` | `dlq_url` output of `sqs` |
| `APP_IRSA_ROLE_ARN` | the app's own IRSA role ARN (see `terraform/modules/iam`'s README - and its noted shared-ServiceAccount trade-off) |

**3. Optional:** create a `production` GitHub Environment (Settings →
Environments) and add required reviewers, so the `deploy` job (and the
`rollback` job, which targets the same environment) pauses for manual
approval before running. Worth weighing for `rollback-banking-app.yml`
specifically: an approval gate adds safety, but also friction to what's
meant to be a fast incident-response path - consider a separate,
non-gated environment for that workflow if response time matters more than
the extra check.

# tech-test

A small event-driven and request-driven banking service (`app/`), the
Terraform modules that would host it on AWS/EKS (`terraform/`), the Helm
chart that deploys it (`helm/`), and the CI/CD pipeline that ships it
(`.github/workflows/`).

See [`TRADEOFFS.md`](./TRADEOFFS.md) for what was deliberately traded off
in this session, what's known-but-unfixed, and how reliability
(SLOs/SLIs/SLAs) would actually get measured going forward.

## Repo layout

```
app/            Go service: cmd/api (HTTP), cmd/consumer (SQS consumer), internal/ (shared packages)
terraform/      Standalone, independently-tested modules - not yet wired into a root composition
helm/           Helm chart deploying both binaries from one image
.github/        CI/CD: build/scan/push, deploy with a post-deploy smoke test, rollback
```

## Running the app locally

Prerequisites: Docker + Docker Compose. (Go 1.25+ only needed if you want to
run binaries directly instead of via Compose - see below.)

```sh
cd app
docker compose up --build
```

This starts four containers: `postgres`, `elasticmq` (a local SQS-compatible
broker), `api` (port 8080), and `consumer` (port 8081, health/metrics only -
it has no inbound API traffic of its own).

```sh
curl localhost:8080/healthz
curl localhost:8080/readyz
curl localhost:8080/api/accounts/1        # seeded rows: ids 1, 2, 3
curl localhost:8080/metrics
curl localhost:8081/healthz               # consumer's own health server
curl localhost:8081/metrics               # events_processed_total, event_processing_duration_seconds, ...
```

Reading an account publishes an `account.accessed` event; the consumer picks
it up and writes an audit row (`processed_events` + `audit_log` tables) -
see `app/README.md` for the full idempotency/poison-message story, and
`docker compose logs consumer -f` to watch it happen.

Tear down with `docker compose down --volumes`.

### Running without Docker

```sh
cd app
go run ./cmd/api      # requires Postgres reachable at $DATABASE_URL
go run ./cmd/consumer # additionally requires $SQS_QUEUE_URL and $SQS_DLQ_QUEUE_URL
```

### Running the tests

```sh
cd app
go build ./...
go vet ./...
go test ./...
```

Full endpoint contract, configuration reference (env vars), and the
SQS producer/consumer design are documented in [`app/README.md`](./app/README.md).

## AWS service mapping

What each part of the architecture actually runs on, and which Terraform
module owns it:

| Component | AWS service(s) | Purpose | Terraform module |
|---|---|---|---|
| Container hosting | EKS (managed node groups) | Runs the `api` and `consumer` Deployments | `terraform/modules/eks` |
| Pod networking / add-ons | VPC CNI, CoreDNS, kube-proxy, EBS CSI driver | Standard EKS add-ons, each with its own IRSA role where needed | `terraform/modules/eks` |
| Networking | VPC, subnets, NAT Gateway(s), Internet Gateway, VPC Flow Logs | Network isolation; NAT mode (none/single/per-AZ) is a cost-vs-HA choice per environment | `terraform/modules/vpc` |
| Container images | ECR | Stores the single image containing both `api` and `consumer` binaries | `terraform/modules/ecr` |
| Primary datastore | RDS for PostgreSQL | `accounts`, `processed_events`, `audit_log` tables | `terraform/modules/rds` |
| DB credentials | Secrets Manager | Holds the generated DB password/connection string, synced into a k8s Secret (e.g. by External Secrets Operator) | `terraform/modules/rds` |
| Messaging | SQS (main queue + DLQ) | `account.accessed` event delivery; see `app/README.md` for why SQS here and Kafka in a higher-throughput production setup | `terraform/modules/sqs` |
| Encryption at rest | KMS | Separate keys for EKS secrets, ECR images, RDS storage, and SQS messages | each module above provisions its own key |
| Pod → AWS permissions | IAM (IRSA via the EKS cluster's OIDC provider) | Scoped per-workload AWS API access (SQS publish/consume, etc.) | `terraform/modules/iam` |
| CI/CD → AWS permissions | IAM (OIDC via `token.actions.githubusercontent.com`) | Lets GitHub Actions push to ECR and deploy to EKS without stored AWS keys, restricted to `refs/heads/main` | `terraform/modules/github-oidc` |
| Control plane / audit logging | CloudWatch Logs | EKS control plane logs, VPC Flow Logs | `terraform/modules/eks`, `terraform/modules/vpc` |

None of these modules are wired together into a deployable root
configuration yet - see `TRADEOFFS.md` for why, and each module's own
README for a composition example.

# banking-app

Helm chart for `/app` — deploys two Deployments from one image:

- **api** (`command: ["/api"]`) — the HTTP service, fronted by a `Service`
  and optionally an `Ingress`/`HorizontalPodAutoscaler`.
- **consumer** (`command: ["/consumer"]`) — the SQS event consumer. No
  `Service`/`Ingress` (it has no inbound traffic besides its own
  health/metrics port); scraped via a `PodMonitor` instead of a
  `ServiceMonitor` if `consumer.serviceMonitor.enabled` is set.

Both containers run as the distroless image's non-root user (65532), with a
read-only root filesystem and all Linux capabilities dropped.

## Required values

At minimum, set:

```yaml
image:
  repository: <ecr repo url from terraform/modules/ecr>
  tag: <image tag>

database:
  existingSecret: <name of a Secret with a DATABASE_URL key>
  # populate this Secret from the Secrets Manager secret created by
  # terraform/modules/rds, e.g. via External Secrets Operator - don't
  # put real credentials directly in a values file.

sqs:
  queueUrl: <queue_url output from terraform/modules/sqs>
  dlqUrl: <dlq_url output from terraform/modules/sqs>

aws:
  region: <aws region>

serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: <IRSA role ARN with the sqs module's producer+consumer policies attached>
```

Without `sqs.queueUrl`/`sqs.dlqUrl`, the api simply skips publishing events
(logs a warning) but the consumer will fail to start — `helm install` will
print a warning via `NOTES.txt` if either is missing.

### Known trade-off: one shared ServiceAccount, not least-privilege

This chart creates **one** `ServiceAccount` (`serviceAccount.create`),
referenced by both the api and consumer Deployments - a time-boxed
simplification, not an oversight. The correct least-privilege setup is two
ServiceAccounts (one per component), each with its own IRSA role carrying
only the permissions that component needs (the api only needs
`sqs:SendMessage` on the main queue; the consumer additionally needs
`sqs:ReceiveMessage`/`DeleteMessage`/`ChangeMessageVisibility` on the main
queue plus `sqs:SendMessage` to the DLQ for poison routing) - see
`terraform/modules/iam`'s README for exactly how that split would compose
with `eks`'s OIDC provider and `sqs`'s `producer_policy_arn`/
`consumer_policy_arn` outputs.

Because a single `ServiceAccount` can only carry one `role-arn` annotation,
today's shared setup means whichever single IRSA role gets attached to
`serviceAccount.annotations` has to carry **both** policies - the api pod
ends up with unused SQS-receive/DLQ permissions, and the consumer pod ends
up with an unused SQS-send permission. To tighten this later: split
`templates/serviceaccount.yaml` into two (`-api`/`-consumer` suffixed),
update the two `deployment-*.yaml` templates to reference their own
ServiceAccount, and switch to two separate IRSA roles.

## Local/dev quick start

For a quick test against a throwaway database (not for real credentials):

```sh
helm install banking-app . \
  --set image.repository=<local-or-test-registry>/banking-app \
  --set image.tag=latest \
  --set database.url="postgres://banking:banking@postgres:5432/banking?sslmode=disable" \
  --set sqs.queueUrl=<...> \
  --set sqs.dlqUrl=<...>
```

## Notable values

| Key | Default | Purpose |
|---|---|---|
| `api.replicaCount` / `consumer.replicaCount` | `2` / `1` | Replica counts. |
| `api.autoscaling.enabled` | `false` | CPU-based HPA for the api. The consumer intentionally has no built-in autoscaling here — scaling it on queue depth (e.g. with KEDA) is the more correct approach and is left to the cluster's own tooling rather than baked into this chart. |
| `api.shutdownDrainSeconds` + `api.lifecycle.preStop` | `5` / `sleep 5` | Paired together: the `preStop` hook gives Kubernetes time to remove the pod from Service endpoints before the process's own drain-then-shutdown sequence begins. Keep these equal. |
| `api.terminationGracePeriodSeconds` / `consumer.terminationGracePeriodSeconds` | `30` | Must exceed `shutdownDrainSeconds + SHUTDOWN_TIMEOUT_SECONDS` (api) or `SHUTDOWN_TIMEOUT_SECONDS` (consumer), or Kubernetes SIGKILLs the process before it finishes draining. |
| `api.podDisruptionBudget.enabled` | `true` | Consumer's PDB defaults to `false` since it typically runs a single replica. |
| `api.ingress.enabled` | `false` | Off by default; this API is assumed to sit behind internal cluster traffic unless told otherwise. |
| `api.serviceMonitor.enabled` / `consumer.serviceMonitor.enabled` | `false` | Requires the Prometheus Operator CRDs installed in-cluster. |

See `values.yaml` for the full set (resources, probes, node scheduling,
extra env vars per component, etc).

## Verifying changes to this chart

```sh
helm lint .
helm template test . --set database.url=x --set image.repository=x --set image.tag=x
```

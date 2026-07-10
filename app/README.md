# banking-app

A minimal Go application backed by Postgres, built to be hosted on
Kubernetes. It's request-driven (an HTTP API) and event-driven (an SQS
consumer). The application logic is intentionally trivial — the point is the
platform around it (health checks, metrics, graceful shutdown, delivery
semantics).

Two binaries share one codebase and one image:

- **`cmd/api`** — the HTTP API described in the contract below. After a
  successful account read, it publishes an `account.accessed` audit event to
  a queue as a best-effort side effect.
- **`cmd/consumer`** — a standalone process that consumes those events and
  idempotently writes an audit log row to Postgres. It's the "idempotent
  consumer" piece of the messaging tier.

## HTTP endpoints (`cmd/api`)

| Endpoint | Purpose |
|---|---|
| `GET /healthz` | Liveness. Always 200 if the process is up; never depends on Postgres. |
| `GET /readyz` | Readiness. Returns 503 while draining (after SIGTERM) or if Postgres is unreachable, 200 otherwise. |
| `GET /metrics` | Prometheus exposition format. |
| `GET /api/accounts/{id}` | Reads one row from the `accounts` table. 404 if missing, 400 for a non-numeric/non-positive id. On success, publishes an `account.accessed` event (best-effort; a publish failure is logged and counted in metrics, never returned to the caller). |

The `consumer` exposes the same `/healthz`, `/readyz` (Postgres-only; it
doesn't need the broker to be reachable to be considered ready — see
"Idempotency and delivery semantics" below) and `/metrics` on its own port,
since it has no external traffic of its own to be "ready" for but still
benefits from the same liveness/readiness/observability contract.

The `accounts` table and three seed rows (ids `1`, `2`, `3`), plus the
`processed_events` and `audit_log` tables, are created automatically on
startup if they don't already exist (see "Idempotency" below for why this is
race-safe across multiple processes).

## Messaging tier: why SQS here, why Kafka in production

**This exercise uses Amazon SQS** (a standard queue + a dead-letter queue,
provisioned by `terraform/modules/sqs`), for reasons specific to what's
being built and evaluated here:

- **Zero operational surface.** There's no broker to run, size, or upgrade —
  just two queues. For a single low-volume event type (one audit event per
  account read) that's the right amount of infrastructure, not an
  under-investment.
- **Native IAM/IRSA integration.** Producer and consumer permissions are
  ordinary IAM policies (see `terraform/modules/sqs`'s `producer`/`consumer`
  policy outputs) — no separate ACL system or client-cert setup.
- **DLQ and redelivery are built in.** A redrive policy (max receive count)
  and a dead-letter queue are queue attributes, not something to build.
  That's most of what "poison message handling" needs at the infra layer.
- **Pay-per-message pricing** suits a spiky, low-throughput audit stream
  far better than a cluster sized for peak capacity.

**If this were a real production system, the messaging tier would be
Kafka** (or a managed equivalent like MSK), once volume and consumer
topology justify it:

- **Throughput and latency.** Kafka sustains much higher throughput at
  lower, more predictable p99 latency than SQS's HTTP-polling model,
  because consumers read sequentially from an in-memory/page-cached log
  instead of issuing a network round-trip per batch.
- **Replay.** Kafka retains a log per partition; any consumer (or a new one
  added later — fraud detection, analytics, a second audit sink) can replay
  from an offset. SQS deletes a message once acknowledged — there's no
  "replay last 24 hours" without having architected that in from the start.
- **Ordering and partitioning.** Kafka gives per-key ordering and
  horizontal consumer-group scaling via partitions. This workload doesn't
  need ordering (the consumer is idempotent and order-agnostic), but a
  higher-volume transactional event stream (every debit/credit, not just
  reads) likely would.
- **Cost model inverts at scale.** SQS's per-message pricing, cheap at low
  volume, gets expensive relative to a running Kafka cluster once message
  rates are high and sustained.

In short: SQS is the right choice for what this tech test asks for (a
single, low-volume audit event, evaluated on delivery semantics, not broker
operations); Kafka is the right choice once the platform has genuinely
high-throughput, multi-consumer, replay-sensitive event traffic.

## Idempotency and delivery semantics

Every event carries an `event_id` (a UUID, generated once by the producer)
- this is the deduplication key. The consumer processes a message like this,
in one Postgres transaction (`internal/dbstore.RecordAuditIfNew`):

```sql
INSERT INTO processed_events (event_id) VALUES ($1) ON CONFLICT (event_id) DO NOTHING;
-- if that inserted a row (first time this event_id has been seen):
INSERT INTO audit_log (event_id, account_id, event_type, occurred_at) VALUES (...);
COMMIT;
```

If `event_id` already exists, the `ON CONFLICT DO NOTHING` affects zero
rows, the transaction is a no-op, and the message is acknowledged (deleted
from the queue) without writing a second audit row. **The same event
delivered twice causes the effect once** — verified in practice: a message
resent with the same `event_id` as one already processed shows up in the
consumer's logs and metrics as `outcome=duplicate`, and `audit_log`/
`processed_events` both still show exactly one row for that `event_id`.

Because `processed_events` and `audit_log` are written in the same
transaction, "have we handled this event" and "did we record its effect" can
never disagree — even if the process crashes mid-transaction, Postgres just
rolls the whole thing back and the next delivery attempt starts fresh.

Schema migration itself is guarded by a Postgres advisory transaction lock
(`pg_advisory_xact_lock`, in `dbstore.MigrateAndSeed`) — both binaries run it
on startup, and without the lock, two processes racing `CREATE TABLE IF NOT
EXISTS` against Postgres's own system catalogs can genuinely fail with a
duplicate-key error (this happened during development of this app and was
the reason the lock was added). The same protection also covers running more
than one replica of either binary.

## Poison messages: retry vs. park

The consumer draws a hard line between two failure classes:

- **Transient failures** (a momentary DB outage, a lock timeout): the
  message is simply left alone — not deleted. It becomes visible again once
  the queue's visibility timeout expires, and SQS redelivers it. After
  `max_receive_count` attempts (configured on the queue via
  `terraform/modules/sqs`, default 5), the queue's own redrive policy moves
  it to the DLQ automatically. **Retry is appropriate here because the same
  message will likely succeed on a later attempt** once the transient
  condition clears.
- **Poison messages** — unparseable JSON, or JSON that parses but fails
  `events.Event.Validate()` (missing/invalid `event_id`, unknown
  `event_type`, non-positive `account_id`, zero `occurred_at`): the consumer
  routes these to the DLQ **immediately**, in application code
  (`routePoison` in `cmd/consumer/main.go`), rather than waiting for
  `max_receive_count` retries to be exhausted. **No number of retries makes
  a structurally invalid message valid**, so retrying it would only delay
  parking it while doing nothing useful. If the DLQ send itself fails, the
  message is left alone so the queue's redrive policy still catches it
  eventually as a backstop.

Verified in practice: sending a non-JSON message to the queue produces a
`poison` outcome in the consumer's logs/metrics, the message appears on the
DLQ immediately (queue depth 1) while the main queue's depth returns to 0,
and a valid message sent immediately afterward is processed normally — a
poison message never blocks the stream behind it.

## Configuration

All configuration is via environment variables. Shared by both binaries
unless noted:

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `8080` (api) / `8081` (consumer, suggested) | HTTP listen port for the health/metrics server. |
| `DATABASE_URL` | `postgres://banking:banking@localhost:5432/banking?sslmode=disable` | Postgres connection string. |
| `SQS_QUEUE_URL` | _(none)_ | Main queue URL. The api treats this as optional (logs a warning and skips publishing if unset); the consumer requires it. |
| `SQS_DLQ_QUEUE_URL` | _(none)_ | Dead-letter queue URL. Required by the consumer (for explicit poison routing); unused by the api. |
| `DB_PING_TIMEOUT_SECONDS` | `2` | Timeout for the Postgres ping performed on every `/readyz` call. |
| `SHUTDOWN_DRAIN_SECONDS` | `5` | **api only.** How long to keep serving after SIGTERM (readiness already failing) before shutting down, to cover Kubernetes' endpoint-removal propagation delay. |
| `SHUTDOWN_TIMEOUT_SECONDS` | `20` | Max time to wait for in-flight work to finish once shutdown actually starts (in-flight HTTP requests for the api; the current receive batch for the consumer). |
| `EVENT_PUBLISH_TIMEOUT_SECONDS` | `2` | **api only.** Bounds how long a request waits on the best-effort event publish before responding anyway. |
| `PROCESS_TIMEOUT_SECONDS` | `5` | **consumer only.** Bounds a single message's DB work. |

The AWS SDK's standard environment variables (`AWS_REGION`,
`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` or a real credential
chain/IRSA, and `AWS_ENDPOINT_URL_SQS` to point at a local SQS-compatible
broker) control how both binaries talk to SQS — see `docker-compose.yml`
for a working local example against ElasticMQ.

## Run locally

```sh
docker compose up --build
curl localhost:8080/healthz
curl localhost:8080/readyz
curl localhost:8080/api/accounts/1     # triggers an account.accessed event
curl localhost:8080/metrics
curl localhost:8081/healthz            # consumer's own health server
curl localhost:8081/metrics            # events_processed_total, event_processing_duration_seconds, ...
```

`docker-compose.yml` runs four services: `postgres`, `elasticmq` (an
SQS-compatible broker for local dev — see `elasticmq.conf` for the main
queue + DLQ + redrive policy), `api`, and `consumer`.

## Run without Docker

```sh
go run ./cmd/api      # requires Postgres reachable at $DATABASE_URL
go run ./cmd/consumer # additionally requires $SQS_QUEUE_URL and $SQS_DLQ_QUEUE_URL
```

## Kubernetes wiring notes

- Point `livenessProbe` at `/healthz` and `readinessProbe` at `/readyz` for
  both the api and consumer deployments.
- Pair `SHUTDOWN_DRAIN_SECONDS` with a `preStop` hook (e.g. `sleep 5`) and a
  `terminationGracePeriodSeconds` comfortably larger than
  `SHUTDOWN_DRAIN_SECONDS + SHUTDOWN_TIMEOUT_SECONDS`, so the container isn't
  SIGKILLed before it finishes draining.
- Scrape `/metrics` with a Prometheus `ServiceMonitor`/`PodMonitor` or
  scrape annotations, depending on what's running in-cluster.
- The consumer deployment needs no `Service`/ingress (it has no inbound
  traffic other than its own health/metrics port) and should run with
  `command: ["/consumer"]` against the same image as the api.

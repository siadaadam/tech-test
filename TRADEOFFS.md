# Trade-offs and reliability measurement plan

This documents what was deliberately traded off while building this session's
work, what's known to be incomplete or unfixed, and the plan for how
reliability (SLIs, SLOs, and eventually SLAs) would actually get measured
rather than guessed at.

## Trade-offs

### Infrastructure (Terraform)

| Decision | What we got | What we gave up |
|---|---|---|
| Every module (`eks`, `vpc`, `ecr`, `rds`, `sqs`, `iam`, `github-oidc`) is standalone and independently validated, but **none are wired into a root composition** | Each module tested in isolation without committing to undiscussed decisions - region, CIDR ranges, instance sizing, environment count, state backend/workspace strategy | This is not yet a deployable platform, just a tested component library. Someone still has to write the root `main.tf` that instantiates all of them together, decide on remote state, and actually `apply` against a real account. |
| `eks` module built from native `aws_eks_*` resources, not `terraform-aws-modules/eks/aws` | Full transparency into exactly what's created, no external module dependency | More Terraform to maintain ourselves vs. leaning on a widely-used, battle-tested community module |
| RDS is a single Postgres instance (optionally Multi-AZ), not Aurora | Simpler, cheaper, easier to reason about | No built-in storage-layer elastic scaling, no native cross-region replica story - see Disaster Recovery below |
| VPC's NAT gateway mode (none / single / per-AZ) is a per-environment choice, not a fixed default | Cost-vs-availability decision left where it belongs (per environment) | Nothing enforces a "safe" choice - a dev environment could accidentally be configured like prod's cost profile or vice versa |

### Messaging

Already covered in depth in `app/README.md` ("Messaging tier" and
"Idempotency and delivery semantics" sections) - summarized here:

- **SQS now, Kafka if this ever needs real throughput.** SQS's operational
  simplicity and native IAM integration fit a single, low-volume audit
  event well; Kafka's log/replay/partitioning model would be the right
  call once volume, replay, or multi-consumer needs justify running it.
- **At-least-once delivery + idempotent consumer**, not exactly-once - SQS
  doesn't offer exactly-once, so correctness comes from the
  `processed_events` dedupe table instead.
- **Best-effort, synchronous-with-timeout event publish**, not a
  transactional outbox. If the process crashes between committing the HTTP
  response and the publish call succeeding, that one audit event is
  silently lost. A transactional outbox (write the event to Postgres in
  the same transaction as the business data, and have a separate relay
  publish it) would close this gap; it wasn't built here because there's
  no business transaction to piggyback on yet (the read endpoint has
  nothing else to commit) - worth revisiting the moment there's an actual
  write endpoint.
- **App-level immediate DLQ routing for poison messages**, on top of the
  queue's own redrive policy - added application complexity in exchange
  for not burning retries on messages that can never succeed.

### App and platform

- **One shared `ServiceAccount`/IRSA role for both `api` and `consumer`**,
  each carrying permissions the other doesn't use. Already flagged in
  `terraform/modules/iam/README.md` and `helm/banking-app/README.md` as a
  time-boxed simplification - the fix (two ServiceAccounts, two roles) is
  documented there, just not applied.
- **One container image with both binaries** (`command: ["/api"]` or
  `["/consumer"]` picks which one runs), instead of two images. Simpler
  CI/build, at the cost of every deployment shipping an unused binary.
- **Distroless, no-shell runtime image.** Stronger security posture
  (nothing to `exec` into, no package manager to exploit), but genuinely
  harder to debug live - no `kubectl exec -it ... sh`.
- **Local dev runs against ElasticMQ**, not real SQS or LocalStack. Good
  enough to prove delivery semantics (idempotency, poison routing) but not
  a perfect behavioral match for real AWS SQS (throttling, exact latency
  characteristics).

### CI/CD

- **Deploy pipeline only validates on merge to `main`** - there's no
  pull-request-time `helm lint`/`terraform plan` check, so a broken chart
  or module change is only caught after it's already merged.
- **Trivy scan uses `ignore-unfixed: true`** - won't block a release over a
  CVE with no available fix. Pragmatic (an unfixable CVE would otherwise
  permanently block every deploy), but it does mean some known
  vulnerabilities can still ship.
- **GitHub OIDC trust is restricted to `refs/heads/main`** - secure by
  default (no other branch, PR, or fork can assume the deploy role), but
  deliberately means deploying from a hotfix branch or tag requires
  widening `allowed_refs` first.
- **Rollback's smoke test is a single `/healthz` check**, not a deeper
  synthetic transaction - fast, but shallow; it wouldn't catch a consumer
  that's silently failing to process events, for example.

### Known issue: zero-downtime rollout timing - identified, not yet fixed

An audit against the "readiness probe + preStop + terminationGracePeriodSeconds
+ readyz-fails-before-stop-accepting" mechanism turned up real timing
problems in `helm/banking-app` that haven't been corrected yet (deprioritized
this session in favor of the CI/CD work above):

1. The `preStop` sleep duration (`api.lifecycle.preStop.exec.command`) is a
   second value hardcoded independently of `api.shutdownDrainSeconds`, not
   derived from it - they can silently drift out of sync.
2. `api.terminationGracePeriodSeconds` (30s) has **zero margin** over the
   worst case of preStop (5s) + the app's own post-SIGTERM drain (5s) +
   its shutdown timeout (20s) = 30s exactly. Any small overhead risks a
   SIGKILL mid-drain.
3. No explicit `strategy`/`minReadySeconds` on the api Deployment - rollout
   safety currently relies on Kubernetes' implicit rolling-update defaults
   rather than a pinned, deliberate configuration.
4. `cmd/consumer`'s shutdown runs the poll-loop drain wait and the HTTP
   server shutdown **sequentially** (up to 20s + 20s = 40s worst case),
   which can exceed its own 30s `terminationGracePeriodSeconds`.

None of these are catastrophic in the common case - they're margin/timing
issues, not outright broken behavior - but they should be fixed (numbers
tightened, `preStop` derived from a single source of truth, an explicit
`RollingUpdate` strategy added, the consumer's shutdown made concurrent)
before relying on this chart for a genuinely zero-dropped-request guarantee.

## Measuring reliability: the plan for SLIs, SLOs, and SLAs

Reliability targets aren't being invented up front - they'd be backed into
from a disaster recovery capability that's actually been tested, in this
order:

**1. Settle on a disaster recovery strategy.**
A backup site - active, or standby (cold, warm, or hot) - that we can fail
over to, sized against how much downtime and data loss the business can
actually tolerate. Alongside it, a backup strategy following full,
differential, or incremental backups, built around the 3-2-1 rule (three
copies of the data, on two different types of storage, with one copy
off-site).

**2. Write it down.**
Once a strategy is settled, it goes into a knowledge base covering exactly
how backups are performed, plus a step-by-step incident-response playbook
covering: restoring from backup, failing over to the standby site, and
post-incident forensic analysis.

**3. Exercise it regularly.**
Regular incident-response exercises (game days) against that playbook are
what produce real, measured numbers for:
- **MTTR** (Mean Time To Recovery)
- **MTBF** (Mean Time Between Failures)
- **RTO** (Recovery Time Objective)
- **RPO** (Recovery Point Objective)

These come from actually running the drill, not from estimating it on
paper.

**4. Turn measured numbers into SLIs.**
Those exercise results are what should set the SLIs (Service Level
Indicators) - accurate, because they're grounded in a real, rehearsed
recovery, not a guess.

**5. SLAs come last, and come from clients.**
SLAs (the externally-facing commitments, with any associated penalties)
only get finalized after liaising with clients about what they actually
need - internal capability (SLOs, driven by what step 3 proved achievable)
comes before external commitment (SLAs, driven by what step 5's
conversation determines is required).

### What already exists to build on

None of the above (DR strategy, backup tooling, playbook, game days) has
been built yet - it's a plan, not a deliverable of this session. What *does*
already exist and would feed the eventual SLIs once that program is in
place:

- `/metrics` on both `api` and `consumer` already expose
  `http_requests_total`/`http_request_duration_seconds` (by route and
  status - candidate availability/latency SLIs for the API),
  `events_processed_total`/`event_processing_duration_seconds` (by
  outcome - candidate consumer-lag/error-rate SLIs), and `db_up`.
- `/readyz` and `/healthz` already give a clean, tested signal for
  automated recovery (Kubernetes restarting/rerouting around unhealthy
  pods) - a component of MTTR, though not a substitute for measuring it
  end-to-end through an actual drill.
- The three-layer rollback mechanism (`.github/workflows/README.md`) is
  itself a small, already-tested piece of the incident-response story:
  what happens when a deploy is the incident.

None of this is a substitute for the plan above - it's the instrumentation
that plan would read from once it exists.

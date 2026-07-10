# sqs

Provisions a KMS-encrypted SQS queue and its dead-letter queue (DLQ) for the
banking-app messaging tier: the API publishes an `account.accessed` audit
event to the main queue on every account read, and a separate consumer
process reads that queue, dedupes by the `event_id` carried in the message
body, and writes an audit log row. The module also produces reusable IAM
policy documents for the producer and consumer sides, rather than full IRSA
roles, since it has no knowledge of any particular EKS cluster's OIDC
provider — callers attach these policies to whatever role/IRSA setup they
already have.

## Retry vs. DLQ semantics

Two independent failure paths are wired up:

1. **Automatic redrive on exhausted retries.** The main queue's
   `redrive_policy` points at the DLQ with `maxReceiveCount = var.max_receive_count`
   (default 5). If the consumer receives a message and fails to delete it
   (crashes, throws, or the visibility timeout simply expires) `max_receive_count`
   times in a row, SQS moves the message to the DLQ automatically — no
   application code required. This is the right behavior for **transient**
   failures such as a momentary database outage or a lock timeout, where the
   same message is likely to succeed on a later attempt.
2. **Explicit poison-message routing.** The consumer policy also grants
   `sqs:SendMessage` on the DLQ directly, so application code that can
   identify a message as permanently unprocessable — unparseable JSON, a
   missing required field, an unknown event type — can send it straight to
   the DLQ and delete it from the main queue immediately, instead of waiting
   for `max_receive_count` redeliveries to burn through. No number of retries
   will make a structurally invalid message valid, so paying the redelivery
   latency for it only delays visibility into the problem.

The DLQ's `redrive_allow_policy` restricts `redrivePermission` to `byQueue`,
scoped to this module's main queue only, so it can't silently become a dumping
ground for unrelated queues.

## Example

```hcl
module "account_events" {
  source = "../../modules/sqs"

  name = "banking-app-account-events"

  visibility_timeout_seconds = 90 # comfortably longer than the consumer's DB write + audit log insert
  max_receive_count          = 5

  tags = {
    Environment = "production"
    Application = "banking-app"
  }
}

## Producer side: the API role that publishes account.accessed events.

data "aws_iam_policy_document" "api_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:banking-app:api"]
    }
  }
}

resource "aws_iam_role" "api" {
  name               = "banking-app-api"
  assume_role_policy = data.aws_iam_policy_document.api_assume_role.json
}

resource "aws_iam_role_policy_attachment" "api_producer" {
  role       = aws_iam_role.api.name
  policy_arn = module.account_events.producer_policy_arn
}

## Consumer side: the audit-log worker that reads and dedupes events.

data "aws_iam_policy_document" "audit_consumer_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:banking-app:audit-consumer"]
    }
  }
}

resource "aws_iam_role" "audit_consumer" {
  name               = "banking-app-audit-consumer"
  assume_role_policy = data.aws_iam_policy_document.audit_consumer_assume_role.json
}

resource "aws_iam_role_policy_attachment" "audit_consumer" {
  role       = aws_iam_role.audit_consumer.name
  policy_arn = module.account_events.consumer_policy_arn
}
```

## Notes

- Retry via normal redelivery (`max_receive_count`) is appropriate for
  transient failures — a momentary DB outage, a lock timeout — because the
  same message will likely succeed on the next attempt within the configured
  number of tries.
- Immediate DLQ routing, performed in application code and not by this
  module, is appropriate for messages that are structurally invalid —
  unparseable JSON, missing required fields, an unknown event type — since no
  number of retries will make a malformed message valid. Use the
  `sqs:SendMessage` permission this module grants on the DLQ in the consumer
  policy to implement that path.
- `fifo_queue` defaults to `false`. This workload doesn't need ordering: the
  consumer dedupes by `event_id` via its own `processed_events` table and
  processes events order-agnostically, so a standard queue (higher
  throughput, simpler redrive semantics) is sufficient.
- `visibility_timeout_seconds` should comfortably exceed the consumer's
  expected processing time (including its own database round-trip for
  dedup + audit log insert) to avoid duplicate concurrent deliveries of the
  same message while it's still being handled.
- Set `create_kms_key = false` and leave `kms_key_arn` unset only if you
  intentionally want SQS-managed (`alias/aws/sqs`) encryption instead of a
  dedicated customer-managed key.
- This module does not create IRSA roles or attach the policies it outputs —
  it only produces the queues, DLQ, and attachable `aws_iam_policy` resources
  (plus their raw JSON, via `producer_policy_json` / `consumer_policy_json`,
  for callers who'd rather inline them). Wire them to your own roles as shown
  above.

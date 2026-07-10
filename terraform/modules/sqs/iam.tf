## Producer policy: publish audit events onto the main queue only.

data "aws_iam_policy_document" "producer" {
  statement {
    sid    = "SendToQueue"
    effect = "Allow"

    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
    ]

    resources = [aws_sqs_queue.this.arn]
  }

  dynamic "statement" {
    for_each = local.kms_key_arn != null ? [1] : []

    content {
      sid    = "UseKmsKey"
      effect = "Allow"

      actions = [
        "kms:GenerateDataKey",
        "kms:Decrypt",
      ]

      resources = [local.kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "producer" {
  name        = "${var.name}-producer"
  description = "Allows publishing audit events to the ${var.name} queue."
  policy      = data.aws_iam_policy_document.producer.json

  tags = var.tags
}

## Consumer policy: receive/delete/extend visibility on the main queue, plus
## explicit permission to route poison messages straight to the DLQ (the
## consumer identifies some unprocessable messages itself, rather than only
## relying on the redrive policy exhausting max_receive_count).

data "aws_iam_policy_document" "consumer" {
  statement {
    sid    = "ConsumeFromQueue"
    effect = "Allow"

    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]

    resources = [aws_sqs_queue.this.arn]
  }

  statement {
    sid    = "RouteToDeadLetterQueue"
    effect = "Allow"

    actions = [
      "sqs:SendMessage",
      "sqs:GetQueueAttributes",
    ]

    resources = [aws_sqs_queue.dlq.arn]
  }

  dynamic "statement" {
    for_each = local.kms_key_arn != null ? [1] : []

    content {
      sid    = "UseKmsKey"
      effect = "Allow"

      actions = [
        "kms:GenerateDataKey",
        "kms:Decrypt",
      ]

      resources = [local.kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "consumer" {
  name        = "${var.name}-consumer"
  description = "Allows consuming audit events from the ${var.name} queue and routing poison messages to its DLQ."
  policy      = data.aws_iam_policy_document.consumer.json

  tags = var.tags
}

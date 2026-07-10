locals {
  kms_key_arn = var.kms_key_arn != null ? var.kms_key_arn : (var.create_kms_key ? aws_kms_key.this[0].arn : null)

  queue_name = var.fifo_queue ? "${var.name}.fifo" : var.name
  dlq_name   = var.fifo_queue ? "${var.name}-dlq.fifo" : "${var.name}-dlq"
}

resource "aws_kms_key" "this" {
  count = var.kms_key_arn == null && var.create_kms_key ? 1 : 0

  description             = "SQS encryption key for ${var.name}"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.name}-sqs"
  })
}

resource "aws_kms_alias" "this" {
  count = var.kms_key_arn == null && var.create_kms_key ? 1 : 0

  name          = "alias/${var.name}-sqs"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_sqs_queue" "dlq" {
  name       = local.dlq_name
  fifo_queue = var.fifo_queue

  message_retention_seconds = var.dlq_message_retention_seconds
  kms_master_key_id         = local.kms_key_arn

  tags = merge(var.tags, {
    Name = local.dlq_name
  })
}

resource "aws_sqs_queue" "this" {
  name       = local.queue_name
  fifo_queue = var.fifo_queue

  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  kms_master_key_id          = local.kms_key_arn

  tags = merge(var.tags, {
    Name = local.queue_name
  })
}

# redrive_policy and redrive_allow_policy are managed as standalone resources
# (rather than as attributes of aws_sqs_queue directly) so the main queue and
# its DLQ can each reference the other's arn without Terraform seeing a
# dependency cycle between the two aws_sqs_queue resources themselves.

resource "aws_sqs_queue_redrive_policy" "this" {
  queue_url = aws_sqs_queue.this.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

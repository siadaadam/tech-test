output "queue_url" {
  description = "URL of the main queue."
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "ARN of the main queue."
  value       = aws_sqs_queue.this.arn
}

output "dlq_url" {
  description = "URL of the dead-letter queue."
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  description = "ARN of the dead-letter queue."
  value       = aws_sqs_queue.dlq.arn
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for SQS server-side encryption."
  value       = local.kms_key_arn
}

output "producer_policy_arn" {
  description = "ARN of the managed IAM policy granting producer (SendMessage) access to the main queue."
  value       = aws_iam_policy.producer.arn
}

output "consumer_policy_arn" {
  description = "ARN of the managed IAM policy granting consumer access to the main queue and DLQ."
  value       = aws_iam_policy.consumer.arn
}

output "producer_policy_json" {
  description = "Raw JSON of the producer policy document, for callers that want to inline it rather than attach the managed policy."
  value       = data.aws_iam_policy_document.producer.json
}

output "consumer_policy_json" {
  description = "Raw JSON of the consumer policy document, for callers that want to inline it rather than attach the managed policy."
  value       = data.aws_iam_policy_document.consumer.json
}

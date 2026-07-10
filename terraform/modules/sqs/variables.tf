variable "name" {
  description = "Name of the main queue (e.g. \"banking-app-account-events\"). The dead-letter queue is named \"<name>-dlq\"."
  type        = string
}

## Main queue

variable "visibility_timeout_seconds" {
  description = "Visibility timeout for the main queue. Should comfortably exceed the consumer's expected processing time so a message isn't redelivered while still being handled."
  type        = number
  default     = 60
}

variable "message_retention_seconds" {
  description = "How long the main queue retains messages that are never successfully processed or redriven."
  type        = number
  default     = 345600 # 4 days
}

variable "receive_wait_time_seconds" {
  description = "Long-poll wait time for ReceiveMessage calls on the main queue. Non-zero enables long polling, reducing empty receives."
  type        = number
  default     = 20
}

variable "max_receive_count" {
  description = "Number of delivery attempts allowed before SQS automatically moves a message from the main queue to the dead-letter queue via the redrive policy."
  type        = number
  default     = 5

  validation {
    condition     = var.max_receive_count >= 1
    error_message = "max_receive_count must be at least 1."
  }
}

variable "fifo_queue" {
  description = "Whether the main queue (and its DLQ) are FIFO queues. Defaults to false: this workload's consumer is idempotent (dedupes by event_id) and order-agnostic, so standard queues are sufficient and give higher throughput."
  type        = bool
  default     = false
}

## Dead-letter queue

variable "dlq_message_retention_seconds" {
  description = "How long the dead-letter queue retains parked messages. Defaults to the SQS maximum so there's ample time to investigate and replay them."
  type        = number
  default     = 1209600 # 14 days
}

## Encryption

variable "create_kms_key" {
  description = "Whether to create a KMS key for SQS server-side encryption. Ignored if kms_key_arn is set."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key to use for server-side encryption. Takes precedence over create_kms_key."
  type        = string
  default     = null
}

variable "kms_key_deletion_window_in_days" {
  description = "Deletion window for the KMS key created for these queues."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}

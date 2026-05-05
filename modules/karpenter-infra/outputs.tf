output "sqs_queue_arn" {
  description = "ARN of the SQS queue for Karpenter interruption handling"
  value       = aws_sqs_queue.karpenter.arn
}

output "sqs_queue_url" {
  description = "URL of the SQS queue for Karpenter interruption handling"
  value       = aws_sqs_queue.karpenter.url
}

output "sqs_queue_name" {
  description = "Name of the SQS queue for Karpenter interruption handling"
  value       = aws_sqs_queue.karpenter.name
}

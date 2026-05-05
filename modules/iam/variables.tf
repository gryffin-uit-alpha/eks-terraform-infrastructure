variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "The URL on the EKS cluster OIDC Issuer (with https://)"
  type        = string
  default     = ""
}

variable "velero_bucket_arn" {
  description = "ARN of the Velero S3 bucket"
  type        = string
}

variable "karpenter_sqs_queue_arn" {
  description = "ARN of the Karpenter SQS queue for interruption handling"
  type        = string
}

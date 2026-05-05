output "bucket_arn" {
  description = "ARN of the Velero S3 bucket"
  value       = aws_s3_bucket.velero.arn
}

output "bucket_name" {
  description = "Name of the Velero S3 bucket"
  value       = aws_s3_bucket.velero.id
}

output "bucket_region" {
  description = "Region of the Velero S3 bucket"
  value       = aws_s3_bucket.velero.region
}

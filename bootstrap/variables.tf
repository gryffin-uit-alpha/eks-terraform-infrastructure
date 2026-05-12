variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "state_bucket_name" {
  type        = string
  description = " S3 bucket for Terraform state ( globally unique)"
}

variable "lock_table_name" {
  type    = string
  default = "tfstate-lock"
}

variable "project_tags" {
  type = map(string)
  default = {
    Project   = "eks-cluster"
    ManagedBy = "terraform-bootstrap"
  }
}

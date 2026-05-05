terraform {
  backend "s3" {
    bucket         = "eks-cluster-hly7hc-us-east-1"
    key            = "eks-cluster/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tfstate-lock"
    encrypt        = true
  }
}

terraform {
  backend "s3" {
    bucket         = "eks-cluster-ap"
    key            = "eks-cluster/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "tfstate-lock"
    encrypt        = true
  }
}

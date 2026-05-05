variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID where bastion instance will be launched"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the bastion"
  type        = string
  default     = "t3.medium"
}

variable "registry_port" {
  description = "Port number for the local Docker registry"
  type        = number
  default     = 5000
}

variable "instance_profile_name" {
  description = "Name of the IAM instance profile to attach to the bastion"
  type        = string
}

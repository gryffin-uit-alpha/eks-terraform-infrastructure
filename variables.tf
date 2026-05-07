# ── Project ───────────────────────────────────────────────────────────────────
variable "project_name" {
  description = "Tên project, dùng làm prefix cho tất cả tài nguyên"
  type        = string
  default     = "eks-cluster"
}

variable "environment" {
  description = "Môi trường triển khai (production | staging)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging"], var.environment)
    error_message = "environment phải là 'production' hoặc 'staging'."
  }
}

# ── Region & AZs ──────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "availability_zones" {
  description = "Danh sách AZ để deploy (3 AZs cho production HA)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

# ── Networking ────────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block cho VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks cho public subnets (1 per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks cho private subnets (1 per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

# ── EKS ───────────────────────────────────────────────────────────────────────
variable "cluster_name" {
  description = "Tên EKS cluster"
  type        = string
  default     = "eks-production"
}

variable "cluster_version" {
  description = "Kubernetes version cho EKS"
  type        = string
  default     = "1.30"
}

variable "cluster_endpoint_public_access" {
  description = "Cho phép public access vào EKS API endpoint (false = private only)"
  type        = bool
  default     = true # Enable for development access
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDR được phép truy cập EKS API (chỉ dùng khi public_access = true)"
  type        = list(string)
  default     = []
}

# ── Node Group ────────────────────────────────────────────────────────────────
variable "node_group_instance_types" {
  description = "EC2 instance types cho managed node group"
  type        = list(string)
  default     = ["t3.small"] # Free tier eligible
}

variable "node_group_desired_size" {
  description = "Số node mong muốn trong managed node group"
  type        = number
  default     = 2
}

variable "node_group_min_size" {
  description = "Số node tối thiểu"
  type        = number
  default     = 1
}

variable "node_group_max_size" {
  description = "Số node tối đa"
  type        = number
  default     = 5
}

variable "node_group_disk_size_gb" {
  description = "Dung lượng EBS root volume mỗi node (GB)"
  type        = number
  default     = 50
}

# ── Bastion / Local Registry ──────────────────────────────────────────────────
variable "bastion_instance_type" {
  description = "EC2 instance type cho bastion host chạy registry:2"
  type        = string
  default     = "t3.small" # Free tier eligible
}

variable "local_registry_port" {
  description = "Port mà registry:2 lắng nghe trên bastion"
  type        = number
  default     = 5000
}

# ── Velero ────────────────────────────────────────────────────────────────────
variable "velero_bucket_name" {
  description = "Tên S3 bucket lưu Velero backups"
  type        = string
  default     = ""
}

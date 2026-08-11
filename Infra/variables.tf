variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS Cluster Name"
  type        = string
  default     = "k8s-lab-cluster"
}

variable "cluster_version" {
  description = "Kubernetes Version"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "EC2 Worker Node Instance Type (Free Tier eligible)"
  type        = string
  default     = "t3.large"
}

variable "ami_type" {
  description = "AMI Type for Node Group"
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

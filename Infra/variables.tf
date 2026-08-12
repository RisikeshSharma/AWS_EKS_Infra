variable "aws_region" {
  description = "AWS Region"

  type = string

  default = "us-east-1"
}


variable "cluster_name" {
  description = "EKS Cluster Name"

  type = string

  default = "k8s-lab-cluster"
}


variable "cluster_version" {
  description = "EKS Kubernetes Version"

  type = string

  default = "1.36"
}


variable "node_instance_type" {
  description = "EC2 Worker Node Instance Type"

  type = string

  default = "m7i-flex.large"
}


variable "ami_type" {
  description = "EKS Worker Node AMI Type"

  type = string

  default = "AL2023_x86_64_STANDARD"
}

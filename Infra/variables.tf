# ============================================================
# AWS
# ============================================================

variable "aws_region" {

  description = "AWS Region"

  type = string

  default = "us-east-1"
}


# ============================================================
# EKS
# ============================================================

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


# ============================================================
# WORKER NODE
# ============================================================

variable "node_instance_type" {

  description = "EKS Worker Node Instance Type"

  type = string

  default = "m7i-flex.large"
}


variable "ami_type" {

  description = "EKS Worker Node AMI"

  type = string

  default = "AL2023_x86_64_STANDARD"
}


# ============================================================
# EBS
# ============================================================

variable "ebs_volume_type" {

  description = "EBS volume type"

  type = string

  default = "gp3"
}


variable "ebs_default_size" {

  description = "Default EBS PVC size for labs"

  type = string

  default = "10Gi"
}


# ============================================================
# EFS
# ============================================================

variable "efs_performance_mode" {

  description = "EFS performance mode"

  type = string

  default = "generalPurpose"
}


variable "efs_throughput_mode" {

  description = "EFS throughput mode"

  type = string

  default = "bursting"
}


# ============================================================
# AWS LOAD BALANCER CONTROLLER
# ============================================================

variable "aws_lb_controller_chart_version" {

  description = "AWS Load Balancer Controller Helm chart version"

  type = string

  default = "1.14.0"
}
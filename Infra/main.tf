terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "rishikesh-eks-tfstate-468354413274"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
  }
}

# ============================================================
# PROVIDER
# ============================================================

provider "aws" {
  region = var.aws_region
}


# ============================================================
# 1. AVAILABILITY ZONES
# ============================================================

data "aws_availability_zones" "available" {
  state = "available"
}


# ============================================================
# 2. VPC
# ============================================================

resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}


# ============================================================
# 3. INTERNET GATEWAY
# ============================================================

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.k8s_vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}


# ============================================================
# 4. PUBLIC SUBNETS
# ============================================================

resource "aws_subnet" "public" {
  count = 2

  vpc_id = aws_vpc.k8s_vpc.id

  cidr_block = "10.0.${count.index + 1}.0/24"

  availability_zone = data.aws_availability_zones.available.names[count.index]

  map_public_ip_on_launch = true

  tags = {
    Name = "${var.cluster_name}-public-${count.index + 1}"

    "kubernetes.io/cluster/${var.cluster_name}" = "shared"

    "kubernetes.io/role/elb" = "1"
  }
}


# ============================================================
# 5. ROUTE TABLE
# ============================================================

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.k8s_vpc.id

  route {
    cidr_block = "0.0.0.0/0"

    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}


# ============================================================
# 6. ROUTE TABLE ASSOCIATION
# ============================================================

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id = aws_subnet.public[count.index].id

  route_table_id = aws_route_table.public.id
}


# ============================================================
# 7. EKS CLUSTER IAM ROLE
# ============================================================

resource "aws_iam_role" "cluster_role" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}


# ============================================================
# 8. EKS CLUSTER IAM POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role = aws_iam_role.cluster_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}


# ============================================================
# 9. WORKER NODE IAM ROLE
# ============================================================

resource "aws_iam_role" "node_role" {
  name = "${var.cluster_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}


# ============================================================
# 10. WORKER NODE POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "node_worker" {
  role = aws_iam_role.node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}


# ============================================================
# 11. AWS VPC CNI POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "node_cni" {
  role = aws_iam_role.node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


# ============================================================
# 12. ECR READ ONLY
# ============================================================

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role = aws_iam_role.node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}


# ============================================================
# 13. EKS CLUSTER
# ============================================================

resource "aws_eks_cluster" "main" {
  name = var.cluster_name

  role_arn = aws_iam_role.cluster_role.arn

  version = var.cluster_version

  vpc_config {
    subnet_ids = aws_subnet.public[*].id

    endpoint_public_access = true

    endpoint_private_access = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}


# ============================================================
# 14. EKS NODE GROUP
# ============================================================

resource "aws_eks_node_group" "main" {
  cluster_name = aws_eks_cluster.main.name

  node_group_name = "${var.cluster_name}-nodes"

  node_role_arn = aws_iam_role.node_role.arn

  subnet_ids = aws_subnet.public[*].id

  version = aws_eks_cluster.main.version

  ami_type = var.ami_type

  instance_types = [
    var.node_instance_type
  ]

  scaling_config {
    desired_size = 2

    min_size = 2

    max_size = 4
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr
  ]
}


# ============================================================
# 15. CALICO INSTALLATION
#
# AWS VPC CNI = POD NETWORKING
# Calico       = NETWORK POLICY
#
# Calico is installed automatically after node group creation.
# ============================================================

resource "null_resource" "calico_install" {

  depends_on = [
    aws_eks_node_group.main
  ]

  provisioner "local-exec" {

    interpreter = [
      "PowerShell",
      "-Command"
    ]

    command = <<-EOT

      Write-Host "============================================"
      Write-Host "Updating kubeconfig..."
      Write-Host "============================================"

      aws eks update-kubeconfig `
        --region ${var.aws_region} `
        --name ${var.cluster_name}

      Write-Host ""
      Write-Host "============================================"
      Write-Host "Installing Calico CRDs..."
      Write-Host "============================================"

      kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/v1_crd_projectcalico_org.yaml

      Write-Host ""
      Write-Host "============================================"
      Write-Host "Installing Tigera Operator..."
      Write-Host "============================================"

      kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/tigera-operator.yaml

      Write-Host ""
      Write-Host "Waiting for Tigera Operator..."
      Write-Host ""

      kubectl wait `
        --for=condition=Available `
        deployment/tigera-operator `
        -n tigera-operator `
        --timeout=180s

      Write-Host ""
      Write-Host "============================================"
      Write-Host "Configuring Calico..."
      Write-Host "============================================"

      @"
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  kubernetesProvider: EKS

  cni:
    type: AmazonVPC

  calicoNetwork:
    bgp: Disabled

---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
"@ | kubectl apply -f -

      Write-Host ""
      Write-Host "============================================"
      Write-Host "Calico installation completed."
      Write-Host "============================================"

    EOT
  }
}

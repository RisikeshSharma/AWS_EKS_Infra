terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
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

provider "helm" {
  kubernetes = {
    host = aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(
      aws_eks_cluster.main.certificate_authority[0].data
    )

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"

      command = "aws"

      args = [
        "eks",
        "get-token",
        "--cluster-name",
        aws_eks_cluster.main.name,
        "--region",
        var.aws_region
      ]
    }
  }
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

  cidr_block = "10.0.0.0/16"

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
# 8. EKS CLUSTER POLICY
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
# 11. VPC CNI POLICY
# ============================================================

resource "aws_iam_role_policy_attachment" "node_cni" {

  role = aws_iam_role.node_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


# ============================================================
# 12. ECR READ ONLY
#
# Required because Kubernetes nodes may pull images from ECR.
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

    endpoint_public_access  = true
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
# 15. EKS OIDC
#
# Required for IRSA
#
# Used by:
# - EBS CSI
# - EFS CSI
# - AWS Load Balancer Controller
# ============================================================

data "tls_certificate" "eks_oidc" {

  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}


resource "aws_iam_openid_connect_provider" "eks" {

  client_id_list = [

    "sts.amazonaws.com"

  ]

  thumbprint_list = [

    data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint

  ]

  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}


# ============================================================
# 16. EBS CSI IAM ROLE
# ============================================================

data "aws_iam_policy_document" "ebs_csi_assume_role" {

  statement {

    effect = "Allow"

    actions = [

      "sts:AssumeRoleWithWebIdentity"

    ]

    principals {

      type = "Federated"

      identifiers = [

        aws_iam_openid_connect_provider.eks.arn

      ]
    }

    condition {

      test = "StringEquals"

      variable = "${replace(
        aws_eks_cluster.main.identity[0].oidc[0].issuer,
        "https://",
        ""
      )}:aud"

      values = [

        "sts.amazonaws.com"

      ]
    }

    condition {

      test = "StringEquals"

      variable = "${replace(
        aws_eks_cluster.main.identity[0].oidc[0].issuer,
        "https://",
        ""
      )}:sub"

      values = [

        "system:serviceaccount:kube-system:ebs-csi-controller-sa"

      ]
    }
  }
}


resource "aws_iam_role" "ebs_csi" {

  name = "${var.cluster_name}-ebs-csi-role"

  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json
}


resource "aws_iam_role_policy_attachment" "ebs_csi" {

  role = aws_iam_role.ebs_csi.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}


# ============================================================
# 17. EBS CSI ADD-ON
# ============================================================

resource "aws_eks_addon" "ebs_csi" {

  cluster_name = aws_eks_cluster.main.name

  addon_name = "aws-ebs-csi-driver"

  service_account_role_arn = aws_iam_role.ebs_csi.arn

  resolve_conflicts_on_create = "OVERWRITE"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [

    aws_eks_node_group.main,

    aws_iam_role_policy_attachment.ebs_csi

  ]
}


# ============================================================
# 18. EFS SECURITY GROUP
# ============================================================

resource "aws_security_group" "efs" {

  name = "${var.cluster_name}-efs-sg"

  description = "Allow NFS traffic from EKS VPC"

  vpc_id = aws_vpc.k8s_vpc.id

  ingress {

    description = "NFS"

    from_port = 2049

    to_port = 2049

    protocol = "tcp"

    cidr_blocks = [

      aws_vpc.k8s_vpc.cidr_block

    ]
  }

  egress {

    from_port = 0

    to_port = 0

    protocol = "-1"

    cidr_blocks = [

      "0.0.0.0/0"

    ]
  }

  tags = {

    Name = "${var.cluster_name}-efs-sg"

  }
}


# ============================================================
# 19. EFS FILE SYSTEM
# ============================================================

resource "aws_efs_file_system" "eks" {

  creation_token = "${var.cluster_name}-efs"

  performance_mode = var.efs_performance_mode

  throughput_mode = var.efs_throughput_mode

  encrypted = true

  tags = {

    Name = "${var.cluster_name}-efs"

  }
}


# ============================================================
# 20. EFS MOUNT TARGETS
# ============================================================

resource "aws_efs_mount_target" "eks" {

  count = 2

  file_system_id = aws_efs_file_system.eks.id

  subnet_id = aws_subnet.public[count.index].id

  security_groups = [

    aws_security_group.efs.id

  ]
}


# ============================================================
# 21. EFS CSI IAM ROLE
# ============================================================

data "aws_iam_policy_document" "efs_csi_assume_role" {

  statement {

    effect = "Allow"

    actions = [

      "sts:AssumeRoleWithWebIdentity"

    ]

    principals {

      type = "Federated"

      identifiers = [

        aws_iam_openid_connect_provider.eks.arn

      ]
    }

    condition {

      test = "StringEquals"

      variable = "${replace(
        aws_eks_cluster.main.identity[0].oidc[0].issuer,
        "https://",
        ""
      )}:aud"

      values = [

        "sts.amazonaws.com"

      ]
    }

    condition {

      test = "StringEquals"

      variable = "${replace(
        aws_eks_cluster.main.identity[0].oidc[0].issuer,
        "https://",
        ""
      )}:sub"

      values = [

        "system:serviceaccount:kube-system:efs-csi-controller-sa"

      ]
    }
  }
}


resource "aws_iam_role" "efs_csi" {

  name = "${var.cluster_name}-efs-csi-role"

  assume_role_policy = data.aws_iam_policy_document.efs_csi_assume_role.json
}


resource "aws_iam_role_policy_attachment" "efs_csi" {

  role = aws_iam_role.efs_csi.name

  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
}


# ============================================================
# 22. EFS CSI ADD-ON
# ============================================================

resource "aws_eks_addon" "efs_csi" {

  cluster_name = aws_eks_cluster.main.name

  addon_name = "aws-efs-csi-driver"

  service_account_role_arn = aws_iam_role.efs_csi.arn

  resolve_conflicts_on_create = "OVERWRITE"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [

    aws_eks_node_group.main,

    aws_iam_role_policy_attachment.efs_csi,

    aws_efs_mount_target.eks

  ]
}


# ============================================================
# 23. CSI SNAPSHOT CONTROLLER
# ============================================================

resource "aws_eks_addon" "snapshot_controller" {

  cluster_name = aws_eks_cluster.main.name

  addon_name = "snapshot-controller"

  resolve_conflicts_on_create = "OVERWRITE"

  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [

    aws_eks_node_group.main

  ]
}


# ============================================================
# 24. CALICO
#
# AWS VPC CNI = POD NETWORKING
# CALICO     = NETWORK POLICY
# ============================================================

resource "null_resource" "calico_install" {

  depends_on = [
    aws_eks_node_group.main
  ]

  provisioner "local-exec" {

    interpreter = [
      "bash",
      "-c"
    ]

    command = <<-EOT
      set -e

      echo "============================================"
      echo "Updating kubeconfig"
      echo "============================================"

      aws eks update-kubeconfig \
        --region ${var.aws_region} \
        --name ${var.cluster_name}

      echo "============================================"
      echo "Installing Calico CRDs"
      echo "============================================"

      kubectl apply \
        --server-side \
        --force-conflicts \
        -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/v1_crd_projectcalico_org.yaml

      echo "============================================"
      echo "Installing Tigera Operator"
      echo "============================================"

      kubectl apply \
        --server-side \
        --force-conflicts \
        -f https://raw.githubusercontent.com/projectcalico/calico/v3.32.1/manifests/tigera-operator.yaml

      echo "============================================"
      echo "Waiting for Tigera Operator"
      echo "============================================"

      kubectl wait \
        --for=condition=Available \
        deployment/tigera-operator \
        -n tigera-operator \
        --timeout=180s

      echo "============================================"
      echo "Configuring Calico"
      echo "============================================"

      cat > /tmp/calico-installation.yaml <<EOF
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
EOF

      kubectl apply \
        --server-side \
        --force-conflicts \
        -f /tmp/calico-installation.yaml

      echo "============================================"
      echo "Waiting for Calico"
      echo "============================================"

      kubectl get tigerastatus

      echo "============================================"
      echo "Calico installation completed"
      echo "============================================"

    EOT
  }
}

# ============================================================
# 25. AWS LOAD BALANCER CONTROLLER IAM POLICY
#
# For:
# - ALB Ingress
# - NLB Service
# - Target Groups
# - Security Groups
# ============================================================

resource "aws_iam_policy" "aws_load_balancer_controller" {

  name = "${var.cluster_name}-AWSLoadBalancerControllerPolicy"

  policy = jsonencode({

    Version = "2012-10-17"

    Statement = [

      {
        Effect = "Allow"

        Action = [

          "iam:CreateServiceLinkedRole"

        ]

        Resource = "*"

        Condition = {

          StringEquals = {

            "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com"

          }

        }

      },

      {
        Effect = "Allow"

        Action = [

          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInstances",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeTags",
          "ec2:DescribeVpcs",
          "ec2:DescribeRouteTables",
          "ec2:DescribeVpcPeeringConnections"

        ]

        Resource = "*"

      },

      {
        Effect = "Allow"

        Action = [

          "elasticloadbalancing:*"

        ]

        Resource = "*"

      },

      {
        Effect = "Allow"

        Action = [

          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:CreateTags",
          "ec2:DeleteTags"

        ]

        Resource = "*"

      },

      {
        Effect = "Allow"

        Action = [

          "acm:ListCertificates",
          "acm:DescribeCertificate"

        ]

        Resource = "*"

      },

      {
        Effect = "Allow"

        Action = [

          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL"

        ]

        Resource = "*"

      },

      {
        Effect = "Allow"

        Action = [

          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection"

        ]

        Resource = "*"

      },

      {
        Effect = "Allow"

        Action = [

          "cognito-idp:DescribeUserPoolClient"

        ]

        Resource = "*"

      },

      {
        Effect = "Allow"

        Action = [

          "tag:GetResources",
          "tag:GetTagKeys",
          "tag:GetTagValues"

        ]

        Resource = "*"

      }

    ]

  })
}


# ============================================================
# 26. AWS LOAD BALANCER CONTROLLER IAM ROLE
# ============================================================

data "aws_iam_policy_document" "aws_lb_assume_role" {

  statement {

    effect = "Allow"

    actions = [

      "sts:AssumeRoleWithWebIdentity"

    ]

    principals {

      type = "Federated"

      identifiers = [

        aws_iam_openid_connect_provider.eks.arn

      ]
    }

    condition {

      test = "StringEquals"

      variable = "${replace(
        aws_eks_cluster.main.identity[0].oidc[0].issuer,
        "https://",
        ""
      )}:aud"

      values = [

        "sts.amazonaws.com"

      ]
    }

    condition {

      test = "StringEquals"

      variable = "${replace(
        aws_eks_cluster.main.identity[0].oidc[0].issuer,
        "https://",
        ""
      )}:sub"

      values = [

        "system:serviceaccount:kube-system:aws-load-balancer-controller"

      ]
    }
  }
}


resource "aws_iam_role" "aws_lb_controller" {

  name = "${var.cluster_name}-aws-lb-controller-role"

  assume_role_policy = data.aws_iam_policy_document.aws_lb_assume_role.json
}


resource "aws_iam_role_policy_attachment" "aws_lb_controller" {

  role = aws_iam_role.aws_lb_controller.name

  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
}


# ============================================================
# 27. AWS LOAD BALANCER CONTROLLER
# ============================================================

resource "helm_release" "aws_load_balancer_controller" {

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  create_namespace = false

  version = var.aws_lb_controller_chart_version

  set = [
    {
      name  = "clusterName"
      value = aws_eks_cluster.main.name
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "vpcId"
      value = aws_vpc.k8s_vpc.id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.aws_lb_controller.arn
    }
  ]

  depends_on = [
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.aws_lb_controller
  ]
}

# ============================================================
# 28. STORAGE CLASSES
#
# Created after EKS/CSI drivers are available.
# ============================================================

resource "null_resource" "storage_classes" {

  depends_on = [
    aws_eks_addon.ebs_csi,
    aws_eks_addon.efs_csi,
    aws_efs_mount_target.eks
  ]

  provisioner "local-exec" {

    interpreter = [
      "bash",
      "-c"
    ]

    command = <<-EOT
      set -e

      echo "============================================"
      echo "Updating kubeconfig"
      echo "============================================"

      aws eks update-kubeconfig \
        --region ${var.aws_region} \
        --name ${var.cluster_name}

      echo "============================================"
      echo "Creating EBS StorageClass"
      echo "============================================"

      cat > /tmp/gp3-storageclass.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: ${var.ebs_volume_type}
  encrypted: "true"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF

      kubectl apply -f /tmp/gp3-storageclass.yaml

      echo "============================================"
      echo "Creating EFS StorageClass"
      echo "============================================"

      cat > /tmp/efs-storageclass.yaml <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: ${aws_efs_file_system.eks.id}
  directoryPerms: "700"
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
  basePath: "/dynamic_provisioning"
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF

      kubectl apply -f /tmp/efs-storageclass.yaml

      echo "============================================"
      echo "StorageClasses created"
      echo "============================================"

      kubectl get storageclass

    EOT
  }
}

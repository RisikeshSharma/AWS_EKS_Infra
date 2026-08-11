# AWS EKS Cluster with 2 Worker Nodes (Terraform)

This Terraform project provisions an Amazon EKS cluster with a Managed Node Group containing **2 worker nodes** in private subnets across 2 Availability Zones.

---

## 📁 Architecture Overview

- **VPC**: Custom VPC (`10.0.0.0/16`) with 2 Public Subnets and 2 Private Subnets.
- **Internet Gateway & NAT Gateway**: NAT Gateway in a public subnet enables private worker nodes to access the Internet securely.
- **EKS Control Plane**: EKS version `1.30` with public & private API endpoint access.
- **Worker Nodes**: Managed Node Group with `desired_size = 2`, `min_size = 1`, `max_size = 3`, running on `t3.medium` instances in private subnets.
- **IAM**: Proper IAM roles for both EKS Cluster (`AmazonEKSClusterPolicy`) and Worker Nodes (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly`).

---

## 🛠️ Prerequisites

1. **Terraform** (`>= 1.3.0`) installed.
2. **AWS CLI** installed and configured (`aws configure` with valid credentials).
3. **kubectl** installed for managing Kubernetes workloads.

---

## 🚀 Quick Start Guide

### Step 1: Initialize Terraform
Initialize the working directory to download the AWS provider:
```bash
terraform init
```

### Step 2: Validate & Preview Resources
Check for syntax errors and preview the resources to be created:
```bash
terraform validate
terraform plan
```

### Step 3: Apply Infrastructure
Provision the EKS cluster and 2 worker nodes (takes approx. 10–15 minutes):
```bash
terraform apply -auto-approve
```

---

## 🔌 Connect to the Cluster

After `terraform apply` finishes, update your local `kubeconfig`:
```bash
aws eks update-kubeconfig --region us-east-1 --name eks-2node-cluster
```

Verify that **2 worker nodes** are in `Ready` status:
```bash
kubectl get nodes -o wide
```

Output should look like:
```text
NAME                                         STATUS   ROLES    AGE   VERSION
ip-10-0-10-xxx.ec2.internal                 Ready    <none>   3m    v1.30.x
ip-10-0-11-xxx.ec2.internal                 Ready    <none>   3m    v1.30.x
```

---

## 🧹 Destroy / Cleanup Resources

To delete all AWS resources created by this Terraform code:
```bash
terraform destroy -auto-approve
```

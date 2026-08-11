output "cluster_name" {
  description = "Name of the EKS Cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Kubernetes API Endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "connect_kubeconfig_cmd" {
  description = "Command to configure local kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${aws_eks_cluster.main.name}"
}

output "verify_nodes_cmd" {
  description = "Command to verify 2 worker nodes"
  value       = "kubectl get nodes -o wide"
}

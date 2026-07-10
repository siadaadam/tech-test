output "cluster_id" {
  description = "Name/ID of the EKS cluster."
  value       = aws_eks_cluster.this.id
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "API server endpoint of the EKS cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster."
  value       = aws_eks_cluster.this.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_security_group_id" {
  description = "ID of the cluster's primary security group, automatically created and managed by EKS."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "cluster_oidc_issuer_url" {
  description = "URL of the cluster's OIDC identity provider."
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider used for IRSA."
  value       = aws_iam_openid_connect_provider.this.arn
}

output "cluster_iam_role_arn" {
  description = "ARN of the IAM role assumed by the EKS control plane."
  value       = aws_iam_role.cluster.arn
}

output "node_iam_role_arn" {
  description = "ARN of the IAM role assumed by node group instances."
  value       = aws_iam_role.node.arn
}

output "node_iam_role_name" {
  description = "Name of the IAM role assumed by node group instances, for attaching further policies."
  value       = aws_iam_role.node.name
}

output "node_groups" {
  description = "Map of node group attributes, keyed by node group name."
  value = {
    for name, ng in aws_eks_node_group.this : name => {
      arn           = ng.arn
      status        = ng.status
      capacity_type = ng.capacity_type
      resources     = ng.resources
    }
  }
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for EKS secrets envelope encryption."
  value       = local.kms_key_arn
}

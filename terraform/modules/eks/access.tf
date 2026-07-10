locals {
  access_policy_associations = merge([
    for entry_name, entry in var.access_entries : {
      for policy_name, policy in entry.policy_associations :
      "${entry_name}.${policy_name}" => {
        principal_arn = entry.principal_arn
        policy_arn    = policy.policy_arn
        namespaces    = policy.namespaces
      }
    }
  ]...)
}

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value.principal_arn
  kubernetes_groups = each.value.kubernetes_groups
  type              = each.value.type

  tags = var.tags
}

resource "aws_eks_access_policy_association" "this" {
  for_each = local.access_policy_associations

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = length(each.value.namespaces) > 0 ? "namespace" : "cluster"
    namespaces = length(each.value.namespaces) > 0 ? each.value.namespaces : null
  }

  depends_on = [aws_eks_access_entry.this]
}

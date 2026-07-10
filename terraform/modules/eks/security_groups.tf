resource "aws_security_group_rule" "cluster_additional" {
  for_each = var.cluster_security_group_additional_rules

  security_group_id = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id

  type        = each.value.type
  description = each.value.description
  protocol    = each.value.protocol
  from_port   = each.value.from_port
  to_port     = each.value.to_port

  cidr_blocks              = each.value.cidr_blocks
  source_security_group_id = each.value.source_security_group_id
  self                     = each.value.self
}

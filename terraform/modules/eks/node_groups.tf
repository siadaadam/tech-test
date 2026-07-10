resource "aws_launch_template" "this" {
  for_each = var.node_groups

  name_prefix = "${var.cluster_name}-${each.key}-"

  vpc_security_group_ids = concat(
    [aws_eks_cluster.this.vpc_config[0].cluster_security_group_id],
    each.value.additional_security_group_ids,
  )

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = each.value.metadata_http_put_response_hop_limit
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = each.value.disk_size
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = local.kms_key_arn
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, each.value.tags, { Name = "${var.cluster_name}-${each.key}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, each.value.tags, { Name = "${var.cluster_name}-${each.key}" })
  }

  tags = merge(var.tags, each.value.tags)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.this.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = length(each.value.subnet_ids) > 0 ? each.value.subnet_ids : var.subnet_ids

  ami_type       = each.value.ami_type
  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types

  launch_template {
    id      = aws_launch_template.this[each.key].id
    version = aws_launch_template.this[each.key].latest_version
  }

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = each.value.desired_size
  }

  update_config {
    max_unavailable = each.value.max_unavailable
  }

  labels = each.value.labels

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(var.tags, each.value.tags)

  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.vpc_cni,
  ]

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }
}

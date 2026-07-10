## IRSA roles for add-ons that call AWS APIs

data "aws_iam_policy_document" "vpc_cni_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-node"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vpc_cni" {
  name               = "${var.cluster_name}-vpc-cni"
  assume_role_policy = data.aws_iam_policy_document.vpc_cni_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "vpc_cni" {
  role       = aws_iam_role.vpc_cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  count = var.addons.aws_ebs_csi_driver.enabled ? 1 : 0

  name               = "${var.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  count = var.addons.aws_ebs_csi_driver.enabled ? 1 : 0

  role       = aws_iam_role.ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

## Add-ons

resource "aws_eks_addon" "vpc_cni" {
  count = var.addons.vpc_cni.enabled ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "vpc-cni"
  addon_version               = var.addons.vpc_cni.version
  service_account_role_arn    = aws_iam_role.vpc_cni.arn
  resolve_conflicts_on_update = var.addons.vpc_cni.resolve_conflicts_on_update
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags
}

resource "aws_eks_addon" "kube_proxy" {
  count = var.addons.kube_proxy.enabled ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "kube-proxy"
  addon_version               = var.addons.kube_proxy.version
  resolve_conflicts_on_update = var.addons.kube_proxy.resolve_conflicts_on_update
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags
}

resource "aws_eks_addon" "coredns" {
  count = var.addons.coredns.enabled ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "coredns"
  addon_version               = var.addons.coredns.version
  resolve_conflicts_on_update = var.addons.coredns.resolve_conflicts_on_update
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags

  # CoreDNS pods need a node to schedule onto.
  depends_on = [aws_eks_node_group.this]
}

resource "aws_eks_addon" "aws_ebs_csi_driver" {
  count = var.addons.aws_ebs_csi_driver.enabled ? 1 : 0

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = var.addons.aws_ebs_csi_driver.version
  service_account_role_arn    = aws_iam_role.ebs_csi[0].arn
  resolve_conflicts_on_update = var.addons.aws_ebs_csi_driver.resolve_conflicts_on_update
  resolve_conflicts_on_create = "OVERWRITE"

  tags = var.tags

  depends_on = [aws_eks_node_group.this]
}

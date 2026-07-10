locals {
  create_public_subnets  = length(var.public_subnet_cidrs) > 0
  create_private_subnets = length(var.private_subnet_cidrs) > 0
  create_nat_gateways    = local.create_private_subnets && var.enable_nat_gateway
  nat_gateway_azs        = var.single_nat_gateway ? [var.azs[0]] : var.azs
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(var.tags, {
    Name = var.name
  })
}

resource "aws_internet_gateway" "this" {
  count = local.create_public_subnets ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = var.name
  })
}

# Lock down the default security group instead of leaving its permissive default rules in place.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name}-default"
  })
}

locals {
  public_subnets = {
    for idx, az in var.azs :
    az => var.public_subnet_cidrs[idx]
    if local.create_public_subnets
  }

  private_subnets = {
    for idx, az in var.azs :
    az => var.private_subnet_cidrs[idx]
    if local.create_private_subnets
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(var.tags, var.public_subnet_tags, {
    Name = "${var.name}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = merge(var.tags, var.private_subnet_tags, {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
  })
}

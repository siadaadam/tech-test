resource "aws_eip" "nat" {
  for_each = local.create_nat_gateways ? toset(local.nat_gateway_azs) : []

  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name}-nat-${each.key}"
  })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = local.create_nat_gateways ? toset(local.nat_gateway_azs) : []

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(var.tags, {
    Name = "${var.name}-${each.key}"
  })

  lifecycle {
    precondition {
      condition     = local.create_public_subnets
      error_message = "NAT gateways require at least one public subnet to host them; set public_subnet_cidrs or disable enable_nat_gateway."
    }
  }

  depends_on = [aws_internet_gateway.this]
}

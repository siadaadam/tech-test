output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "internet_gateway_id" {
  description = "ID of the internet gateway, if public subnets were created."
  value       = try(aws_internet_gateway.this[0].id, null)
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, keyed by Availability Zone."
  value       = { for az, subnet in aws_subnet.public : az => subnet.id }
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, keyed by Availability Zone."
  value       = { for az, subnet in aws_subnet.private : az => subnet.id }
}

output "public_subnet_ids_list" {
  description = "IDs of the public subnets as a flat list, for modules that expect a plain list."
  value       = [for subnet in aws_subnet.public : subnet.id]
}

output "private_subnet_ids_list" {
  description = "IDs of the private subnets as a flat list, for modules that expect a plain list."
  value       = [for subnet in aws_subnet.private : subnet.id]
}

output "nat_gateway_ids" {
  description = "IDs of the NAT gateways, keyed by Availability Zone."
  value       = { for az, nat in aws_nat_gateway.this : az => nat.id }
}

output "nat_gateway_public_ips" {
  description = "Public (Elastic) IPs of the NAT gateways, keyed by Availability Zone."
  value       = { for az, eip in aws_eip.nat : az => eip.public_ip }
}

output "public_route_table_id" {
  description = "ID of the shared public route table, if public subnets were created."
  value       = try(aws_route_table.public[0].id, null)
}

output "private_route_table_ids" {
  description = "IDs of the private route tables, keyed by Availability Zone."
  value       = { for az, rt in aws_route_table.private : az => rt.id }
}

output "default_security_group_id" {
  description = "ID of the VPC's default security group, hardened to have no rules."
  value       = aws_default_security_group.this.id
}

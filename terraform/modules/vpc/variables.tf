## Core

variable "name" {
  description = "Name used to tag the VPC and derive resource names."
  type        = string
}

variable "cidr_block" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
}

variable "azs" {
  description = "Availability Zones to spread subnets across, e.g. [\"us-east-1a\", \"us-east-1b\"]."
  type        = list(string)

  validation {
    condition     = length(var.azs) > 0
    error_message = "At least one Availability Zone must be provided."
  }
}

variable "enable_dns_support" {
  description = "Whether DNS resolution is enabled for the VPC."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Whether instances with public IPs get public DNS hostnames."
  type        = bool
  default     = true
}

## Subnets

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets, one per element of var.azs. Leave empty to create no public subnets."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.public_subnet_cidrs) == 0 || length(var.public_subnet_cidrs) == length(var.azs)
    error_message = "public_subnet_cidrs must be empty or have exactly one CIDR per element of var.azs."
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets, one per element of var.azs. Leave empty to create no private subnets."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.private_subnet_cidrs) == 0 || length(var.private_subnet_cidrs) == length(var.azs)
    error_message = "private_subnet_cidrs must be empty or have exactly one CIDR per element of var.azs."
  }
}

variable "map_public_ip_on_launch" {
  description = "Whether instances launched into public subnets are auto-assigned a public IP."
  type        = bool
  default     = true
}

variable "public_subnet_tags" {
  description = "Additional tags applied to every public subnet."
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Additional tags applied to every private subnet."
  type        = map(string)
  default     = {}
}

## NAT gateways

variable "enable_nat_gateway" {
  description = "Whether to create NAT gateway(s) so private subnets can reach the internet. Has no effect if there are no private subnets."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "If true, create one NAT gateway shared by all private subnets (cheaper, single point of failure). If false, create one NAT gateway per AZ (highly available, costs more)."
  type        = bool
  default     = false
}

## Flow logs

variable "enable_flow_logs" {
  description = "Whether to enable VPC flow logs to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "flow_logs_traffic_type" {
  description = "Type of traffic to capture in flow logs: ALL, ACCEPT, or REJECT."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be one of: ALL, ACCEPT, REJECT."
  }
}

variable "flow_logs_retention_in_days" {
  description = "Retention period for the flow logs CloudWatch log group."
  type        = number
  default     = 90
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}

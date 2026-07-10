# vpc

Provisions a VPC with public and private subnets spread across the given
Availability Zones, an internet gateway, optional NAT gateway(s) for
private-subnet egress, per-subnet route tables, a hardened default security
group (all rules removed), and optional VPC flow logs to CloudWatch.

## NAT gateway modes

Controlled by `enable_nat_gateway` and `single_nat_gateway`:

| `enable_nat_gateway` | `single_nat_gateway` | Result |
|---|---|---|
| `false` | – | No NAT gateways created. Private subnets have no internet egress. |
| `true` | `false` (default) | One NAT gateway per AZ. Each private subnet routes through its own AZ's NAT gateway — no cross-AZ data transfer charges, tolerates a single NAT gateway failure. |
| `true` | `true` | One NAT gateway total, in the first AZ. Cheaper, but all private subnets share it as a single point of failure and pay cross-AZ data transfer for traffic from other AZs. |

NAT gateways require at least one public subnet to host them; this is
enforced with a plan-time precondition.

## Example

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name       = "my-vpc"
  cidr_block = "10.0.0.0/16"
  azs        = ["us-east-1a", "us-east-1b", "us-east-1c"]

  public_subnet_cidrs  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnet_cidrs = ["10.0.16.0/20", "10.0.32.0/20", "10.0.48.0/20"]

  enable_nat_gateway = true
  single_nat_gateway = false # one NAT gateway per AZ

  tags = {
    Environment = "production"
  }
}
```

### Dev/cost-optimized example (single shared NAT gateway)

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name       = "my-vpc-dev"
  cidr_block = "10.1.0.0/16"
  azs        = ["us-east-1a", "us-east-1b"]

  public_subnet_cidrs  = ["10.1.0.0/24", "10.1.1.0/24"]
  private_subnet_cidrs = ["10.1.16.0/20", "10.1.32.0/20"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Environment = "dev"
  }
}
```

### Public-only, no NAT

```hcl
module "vpc" {
  source = "../../modules/vpc"

  name       = "my-vpc-public-only"
  cidr_block = "10.2.0.0/16"
  azs        = ["us-east-1a", "us-east-1b"]

  public_subnet_cidrs = ["10.2.0.0/24", "10.2.1.0/24"]
  enable_nat_gateway  = false
}
```

## Notes

- `public_subnet_cidrs` and `private_subnet_cidrs` must each be empty or have
  exactly one CIDR per element of `azs`.
- Subnets from this module tag with `Tier = "public"` / `"private"`; add
  EKS ELB-discovery tags (`kubernetes.io/role/elb`,
  `kubernetes.io/role/internal-elb`, `kubernetes.io/cluster/<name>`) via
  `public_subnet_tags` / `private_subnet_tags` if feeding these subnets into
  the `eks` module.

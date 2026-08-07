module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "event-app-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = []          # no NAT gateway — nodes sit in public subnets to save cost

  enable_dns_hostnames    = true
  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
}

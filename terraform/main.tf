# NETWORKING MODULE

module "networking" {
  source = "./modules/networking"

  # Basic configuration
  project_name = var.project_name
  environment  = terraform.workspace

  # VPC configuration
  vpc_cidr = var.vpc_cidr

  # Availability zones
  availability_zones = var.availability_zones

  # Subnet configuration
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs

  # NAT Gateway configuration
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.single_nat_gateway

  # Tags
  tags = var.common_tags
}
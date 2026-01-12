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


# SECURITY GROUPS MODULE

module "security" {
  source = "./modules/security"

  vpc_id      = module.networking.vpc_id
  environment = terraform.workspace
  my_ip       = "190.158.28.120/32"
  vpc_cidr    = var.vpc_cidr
}


# COMPUTE MODULE

module "compute" {
  source = "./modules/compute"

  project_name = var.project_name
  environment  = terraform.workspace
  vpc_id       = module.networking.vpc_id

  # Bastion configuration
  public_subnet_ids     = module.networking.public_subnet_ids
  bastion_sg_id         = module.security.bastion_sg_id
  key_name              = aws_key_pair.bastion.key_name
  bastion_instance_type = "t3.micro"

  # Backend configuration
  private_subnet_ids       = module.networking.private_subnet_ids
  backend_sg_id            = module.security.backend_sg_id
  backend_instance_type    = "t3.micro"
  backend_instance_count   = 2
  backend_instance_profile = aws_iam_instance_profile.backend.name
}

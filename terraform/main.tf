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
  private_subnet_ids     = module.networking.private_subnet_ids
  backend_sg_id          = module.security.backend_sg_id
  backend_instance_type  = "t3.micro"
  backend_instance_count = 2

  # Database configuration
  db_master_secret_arn = module.database.db_master_secret_arn

  # Frontend configuration
  frontend_instance_count = 2
  frontend_instance_type  = "t3.micro"
  frontend_sg_id          = module.security.frontend_sg_id


  tags                       = var.common_tags
  aws_region                 = var.aws_region
  enable_detailed_monitoring = terraform.workspace == "prod"

}


# DATABASE MODULE

module "database" {
  source = "./modules/database"

  environment           = terraform.workspace
  vpc_id                = module.networking.vpc_id
  database_subnet_ids   = module.networking.database_subnet_ids
  rds_security_group_id = module.security.rds_sg_id

  # Database configuration
  db_name     = "movieanalyst"
  db_username = "admin"


  # Instance sizing
  allocated_storage = 20
  instance_class    = "db.t3.micro"
  engine_version    = "8.0"
}



# LOAD BALANCER MODULE
module "alb" {
  source = "./modules/loadbalancer"

  name        = "${terraform.workspace}-${var.project_name}-alb"
  environment = terraform.workspace

  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  alb_sg_id         = module.security.alb_sg_id

  # Frontend configuration
  frontend_instance_ids = module.compute.frontend_instance_ids
  frontend_port         = 3030

  # Backend configuration
  backend_instance_ids      = module.compute.backend_instance_ids
  backend_port              = 3000
  backend_health_check_path = "/health"

  enable_deletion_protection = terraform.workspace == "prod"

  tags = merge(
    var.common_tags,
    {
      Environment = terraform.workspace
      Name        = "${terraform.workspace}-${var.project_name}-alb"
    }
  )
}


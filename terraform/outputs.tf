output "workspace" {
  description = "Current Terraform workspace"
  value       = terraform.workspace
}

output "aws_region" {
  description = "AWS region being used"
  value       = var.aws_region
}

# NETWORKING OUTPUTS
# ============================================

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = module.networking.private_subnet_ids
}

output "database_subnet_ids" {
  description = "Database subnet IDs"
  value       = module.networking.database_subnet_ids
}

output "nat_gateway_ip" {
  description = "NAT Gateway public IP"
  value       = module.networking.nat_gateway_ip
}

# SECURITY OUTPUTS
# ============================================

output "bastion_sg_id" {
  description = "Bastion Security Group ID"
  value       = module.security.bastion_sg_id
}

output "alb_sg_id" {
  description = "ALB Security Group ID"
  value       = module.security.alb_sg_id
}

output "frontend_sg_id" {
  description = "Frontend Security Group ID"
  value       = module.security.frontend_sg_id
}

output "backend_sg_id" {
  description = "Backend Security Group ID"
  value       = module.security.backend_sg_id
}

output "rds_sg_id" {
  description = "RDS Security Group ID"
  value       = module.security.rds_sg_id
}


# COMPUTE OUTPUTS

output "bastion_public_ip" {
  description = "Public IP of Bastion Host"
  value       = module.compute.bastion_public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to Bastion"
  value       = "ssh -i keys/movie-analyst-bastion-key ec2-user@${module.compute.bastion_public_ip}"
}
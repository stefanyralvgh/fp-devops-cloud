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


# COMPUTE OUTPUTS (BASTION)

output "bastion_public_ip" {
  description = "Public IP of Bastion Host"
  value       = module.compute.bastion_public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to Bastion (with agent forwarding)"
  value       = "ssh -A -i ~/.ssh/movie-analyst-bastion-key ec2-user@${module.compute.bastion_public_ip}"
}


# COMPUTE OUTPUTS (BACKEND)

output "backend_private_ips" {
  description = "Private IPs of Backend instances"
  value       = module.compute.backend_private_ips
}

output "backend_ssh_commands" {
  description = "SSH commands to connect to backend instances (via Bastion)"
  value = [
    for idx, ip in module.compute.backend_private_ips :
    "ssh -A -i ~/.ssh/movie-analyst-bastion-key -J ec2-user@${module.compute.bastion_public_ip} ec2-user@${ip}  # backend-${idx + 1}"
  ]
}

output "backend_availability_zones" {
  description = "Availability zones of Backend instances"
  value       = module.compute.backend_availability_zones
}


# COMPUTE OUTPUTS (FRONTEND)

output "frontend_public_ips" {
  description = "Public IPs of frontend instances"
  value       = module.compute.frontend_public_ips
}

output "frontend_ssh_commands" {
  description = "SSH commands to connect to frontend instances (via Bastion)"
  value = [
    for idx, ip in module.compute.frontend_private_ips :
    "ssh -A -i ~/.ssh/movie-analyst-bastion-key -J ec2-user@${module.compute.bastion_public_ip} ec2-user@${ip}  # frontend-${idx + 1}"
  ]
}

output "quick_access_guide" {
  description = "Quick reference for accessing infrastructure"
  value       = <<-EOT
  
  ═══════════════════════════════════════════════════════════
  MOVIE ANALYST - QUICK ACCESS GUIDE
  ═══════════════════════════════════════════════════════════

  🔑 PREREQUISITE (Run once per terminal session):
     eval $(ssh-agent -s)
     ssh-add ~/.ssh/movie-analyst-bastion-key
  
  📦 BASTION (Jump Host):
     ssh -A -i ~/.ssh/movie-analyst-bastion-key ec2-user@${module.compute.bastion_public_ip}
  
  🔧 BACKEND INSTANCES:
     ${join("\n     ", [for idx, ip in module.compute.backend_private_ips : "ssh -A -i ~/.ssh/movie-analyst-bastion-key -J ec2-user@${module.compute.bastion_public_ip} ec2-user@${ip}  # backend-${idx + 1}"])}
  
  🌐 FRONTEND INSTANCES:
     ${join("\n     ", [for idx, ip in module.compute.frontend_private_ips : "ssh -A -i ~/.ssh/movie-analyst-bastion-key -J ec2-user@${module.compute.bastion_public_ip} ec2-user@${ip}  # frontend-${idx + 1}"])}
  
  🌍 FRONTEND WEB ACCESS:
     ${join("\n     ", [for idx, ip in module.compute.frontend_public_ips : "http://${ip}  # frontend-${idx + 1}"])}
  
  ═══════════════════════════════════════════════════════════
  EOT
}
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
# ============================================

output "bastion_public_ip" {
  description = "Public IP of Bastion Host"
  value       = module.compute.bastion_public_ip
}

output "bastion_ssh_command" {
  description = "SSH command to connect to Bastion (with agent forwarding)"
  value       = "ssh -A -i ~/.ssh/movie-analyst-bastion-key ec2-user@${module.compute.bastion_public_ip}"
}


# COMPUTE OUTPUTS (BACKEND)
# ============================================

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
# ============================================

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

# DATABASE OUTPUTS
# ============================================

output "db_endpoint" {
  description = "RDS instance endpoint"
  value       = module.database.db_instance_endpoint
}

output "db_address" {
  description = "RDS instance address"
  value       = module.database.db_instance_address
}

output "db_name" {
  description = "Database name"
  value       = module.database.db_instance_name
}

output "db_connection_string" {
  description = "Database connection string (without password)"
  value       = module.database.db_connection_string
  sensitive   = true
}

output "db_master_secret_arn" {
  value     = module.database.db_master_secret_arn
  sensitive = true
}



# LOAD BALANCER OUTPUTS
# ============================================

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.dns_name
}


output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.arn
}

output "frontend_access_urls" {
  description = "URLs to access frontend instances directly"
  value = [
    for idx, ip in module.compute.frontend_public_ips :
    "http://${ip}  # frontend-${idx + 1}"
  ]
}

output "architecture_info" {
  description = "Architecture flow information"
  value       = <<-EOT
  
  ═══════════════════════════════════════════════════════════
  ARCHITECTURE FLOW
  ═══════════════════════════════════════════════════════════
  
  USER ACCESS:
  └─ Frontend: Use any frontend public IP (load balanced by DNS round-robin)
     ${join("\n     ", [for idx, ip in module.compute.frontend_public_ips : "http://${ip}  # frontend-${idx + 1}"])}
  
  API FLOW:
  User → Frontend (http://frontend-ip)
       → JavaScript makes /api/* request
       → Nginx proxy_pass to ALB
       → ALB (${module.alb.dns_name})
       → Backend instances
       → RDS MySQL
  
  ═══════════════════════════════════════════════════════════
  EOT
}


# STORAGE OUTPUTS
# ==========================================
output "assets_bucket_name" {
  description = "Name of the assets S3 bucket"
  value       = module.storage.bucket_name
}

output "assets_bucket_url" {
  description = "URL of the assets S3 bucket"
  value       = module.storage.bucket_url
}



# MONITORING OUTPUTS
# ========================================

output "monitoring_dashboard_url" {
  description = "URL to CloudWatch Dashboard"
  value       = module.monitoring.dashboard_url
}

output "monitoring_alarms" {
  description = "Summary of configured CloudWatch alarms"
  value = {
    frontend_cpu = module.monitoring.frontend_cpu_alarm_names
    backend_cpu  = module.monitoring.backend_cpu_alarm_names
    rds          = module.monitoring.rds_alarm_names
  }
}


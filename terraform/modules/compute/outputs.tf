# BASTION OUTPUTS
output "bastion_id" {
  description = "ID of the Bastion instance"
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IP of the Bastion (Elastic IP)"
  value       = aws_eip.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IP of the Bastion"
  value       = aws_instance.bastion.private_ip
}

output "bastion_public_dns" {
  description = "Public DNS of the Bastion"
  value       = aws_eip.bastion.public_dns
}


# BACKEND OUTPUTS

output "backend_instance_ids" {
  description = "IDs of Backend instances"
  value       = aws_instance.backend[*].id
}

output "backend_private_ips" {
  description = "Private IPs of Backend instances"
  value       = aws_instance.backend[*].private_ip
}

output "backend_availability_zones" {
  description = "Availability zones of Backend instances"
  value       = aws_instance.backend[*].availability_zone
}


# FRONTEND OUTPUTS

output "frontend_instance_ids" {
  description = "IDs of frontend instances"
  value       = aws_instance.frontend[*].id
}

output "frontend_private_ips" {
  description = "Private IPs of frontend instances"
  value       = aws_instance.frontend[*].private_ip
}

output "frontend_public_ips" {
  description = "Public IPs of frontend instances"
  value       = aws_instance.frontend[*].public_ip
}
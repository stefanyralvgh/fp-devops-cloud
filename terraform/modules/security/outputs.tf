output "bastion_sg_id" {
  description = "ID of the Bastion Security Group"
  value       = aws_security_group.bastion.id
}

output "alb_sg_id" {
  description = "ID of the ALB Security Group"
  value       = aws_security_group.alb.id
}

output "frontend_sg_id" {
  description = "ID of the Frontend Security Group"
  value       = aws_security_group.frontend.id
}

output "backend_sg_id" {
  description = "ID of the Backend Security Group"
  value       = aws_security_group.backend.id
}

output "rds_sg_id" {
  description = "ID of the RDS Security Group"
  value       = aws_security_group.rds.id
}

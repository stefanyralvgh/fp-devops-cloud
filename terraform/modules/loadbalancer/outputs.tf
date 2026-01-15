output "arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.lb_arn
}

output "dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.lb_dns_name
}

output "zone_id" {
  description = "Route53 zone ID of the ALB"
  value       = module.alb.lb_zone_id
}

output "target_group_arn" {
  description = "ARN of the frontend target group"
  value       = module.alb.target_group_arns[0]
}
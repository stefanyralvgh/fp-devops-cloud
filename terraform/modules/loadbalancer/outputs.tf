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


# Monitoring Outputs

output "alb_arn_suffix" {
  description = "ARN suffix of the Application Load Balancer (for CloudWatch metrics)"
  value       = join("/", slice(split("/", module.alb.lb_arn), 1, 4))
}


output "target_group_arn_suffix" {
  description = "ARN suffix of the frontend target group (for CloudWatch metrics)"
  value       = join("/", slice(split("/", module.alb.target_group_arns[0]), 1, 3))
}
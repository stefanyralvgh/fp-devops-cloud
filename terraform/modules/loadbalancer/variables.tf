variable "name" {
  description = "Name of the load balancer"
  type        = string
}

variable "environment" {
  description = "Environment name (qa, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ALB will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for ALB"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

# Frontend configuration
#variable "frontend_instance_ids" {
#  description = "List of frontend instance IDs for target group"
#  type        = list(string)
#}

#variable "frontend_port" {
#  description = "Port where frontend listens"
#  type        = number
#  default     = 80
#}

# Backend configuration
variable "backend_instance_ids" {
  description = "List of backend instance IDs for target group"
  type        = list(string)
}

variable "backend_port" {
  description = "Port where backend API listens"
  type        = number
  default     = 3000
}

variable "backend_health_check_path" {
  description = "Health check path for backend"
  type        = string
  default     = "/health"
}
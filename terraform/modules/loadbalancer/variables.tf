variable "name" {
  description = "Name of the Application Load Balancer"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where ALB is deployed"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security Group ID for the ALB"
  type        = string
}

#variable "frontend_instance_ids" {
#  description = "IDs of frontend EC2 instances"
#  type        = list(string)
#}

#variable "frontend_port" {
#  description = "Port where frontend listens"
#  type        = number
#  default     = 80
#}

variable "health_check_path" {
  description = "Health check path for backend"
  type        = string
  default     = "/"
}

variable "health_check_interval" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
}

variable "target_group_name" {
  description = "Name of the target group"
  type        = string
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for ALB"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to ALB resources"
  type        = map(string)
}

variable "backend_port" {
  description = "Port where backend API listens"
  type        = number
  default     = 3000
}

variable "backend_instance_ids" {
  description = "List of backend instance IDs to attach to target group"
  type        = list(string)
}
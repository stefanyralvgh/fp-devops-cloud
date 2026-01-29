
variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (qa/prod)"
  type        = string
}




variable "alb_arn_suffix" {
  description = "ARN suffix of the Application Load Balancer"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "ARN suffix of the backend target group"
  type        = string
}

variable "frontend_instance_ids" {
  description = "List of frontend EC2 instance IDs"
  type        = list(string)
}

variable "backend_instance_ids" {
  description = "List of backend EC2 instance IDs"
  type        = list(string)
}

variable "rds_instance_id" {
  description = "RDS instance identifier"
  type        = string
}


# ALARM CONFIGURATION

variable "cpu_alarm_threshold" {
  description = "CPU utilization threshold for alarms (%)"
  type        = number
  default     = 80
}

variable "rds_connections_threshold" {
  description = "Maximum database connections threshold"
  type        = number
  default     = 80
}

variable "enable_sns_alerts" {
  description = "Enable SNS topic for alarm notifications"
  type        = bool
  default     = false
}

variable "alert_email" {
  description = "Email address for alarm notifications (if SNS enabled)"
  type        = string
  default     = ""
}


# TAGS

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
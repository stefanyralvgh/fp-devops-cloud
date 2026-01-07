variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "movie-analyst"
}

variable "environment" {
  description = "Environment name (qa or prod)"
  type        = string
  default     = "qa"
}

# VPC CIDR blocks
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# Tags
variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project   = "movie-analyst"
    ManagedBy = "terraform"
  }
}
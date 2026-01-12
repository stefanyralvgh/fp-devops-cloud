# BASTION VARIABLES
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (qa or prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where resources will be created"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs for Bastion"
  type        = list(string)
}

variable "bastion_sg_id" {
  description = "Security Group ID for Bastion"
  type        = string
}

variable "key_name" {
  description = "SSH key pair name for EC2 instances"
  type        = string
}

variable "bastion_instance_type" {
  description = "Instance type for Bastion host"
  type        = string
  default     = "t3.micro"
}




# BACKEND VARIABLES

variable "private_subnet_ids" {
  description = "List of private subnet IDs for Backend instances"
  type        = list(string)
}

variable "backend_sg_id" {
  description = "Security Group ID for Backend instances"
  type        = string
}

variable "backend_instance_type" {
  description = "Instance type for Backend instances"
  type        = string
  default     = "t3.micro"
}

variable "backend_instance_count" {
  description = "Number of backend instances to create"
  type        = number
  default     = 2
}

variable "tags" {
  description = "Common tags for compute resources"
  type        = map(string)
}

variable "aws_region" {
  type = string
}


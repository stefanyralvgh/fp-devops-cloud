variable "vpc_id" {
  description = "ID of the VPC where the Security Groups will be created"
  type        = string
}

variable "environment" {
  description = "Environment (qa or prod)"
  type        = string
}

variable "my_ip" {
  description = "Public IP for SSH access to the Bastion"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR to allow internal traffic"
  type        = string
}

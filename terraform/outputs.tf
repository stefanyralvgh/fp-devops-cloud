output "workspace" {
  description = "Current Terraform workspace"
  value       = terraform.workspace
}

output "aws_region" {
  description = "AWS region being used"
  value       = var.aws_region
}

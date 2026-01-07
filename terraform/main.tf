# terraform/main.tf

# Main Terraform configuration
# Modules will be called from here as we create them

# Temporary test resource to validate backend connectivity
#resource "null_resource" "backend_test" {
#  provisioner "local-exec" {
#   command = "echo Backend validated - Workspace: ${terraform.workspace}"
#  }
#}
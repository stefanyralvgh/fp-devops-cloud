output "db_instance_endpoint" {
  description = "The connection endpoint (host:port)"
  value       = module.rds.db_instance_endpoint
}

output "db_instance_address" {
  description = "The hostname of the RDS instance"
  value       = module.rds.db_instance_address
}

output "db_instance_name" {
  description = "The database name"
  value       = module.rds.db_instance_name
}

output "db_instance_username" {
  description = "The master username"
  value       = module.rds.db_instance_username
  sensitive   = true
}

output "db_instance_port" {
  description = "The database port"
  value       = module.rds.db_instance_port
}

output "db_instance_identifier" {
  value = module.rds.db_instance_identifier
}

output "db_connection_string" {
  description = "Database connection string (without password)"
  value       = "mysql://${module.rds.db_instance_username}@${module.rds.db_instance_address}:${module.rds.db_instance_port}/${module.rds.db_instance_name}"
  sensitive   = true
}

output "db_master_secret_arn" {
  description = "ARN of the RDS master user secret"
  value       = module.rds.db_instance_master_user_secret_arn
  sensitive   = true
}


# Monitoring Outputs

output "db_instance_id" {
  description = "RDS instance identifier"
  value       = module.rds.db_instance_identifier
}
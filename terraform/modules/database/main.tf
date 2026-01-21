# DB Subnet Group
resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.environment}-rds-subnet-group-"
  description = "Subnet group for RDS MySQL instance"
  subnet_ids  = var.database_subnet_ids

  tags = {
    Name        = "${var.environment}-rds-subnet-group"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# IAM Role for Enhanced Monitoring (PROD only)
resource "aws_iam_role" "rds_monitoring" {
  count = var.environment == "prod" ? 1 : 0

  name_prefix = "${var.environment}-rds-monitoring-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.environment}-rds-monitoring-role"
    Environment = var.environment
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  count = var.environment == "prod" ? 1 : 0

  role       = aws_iam_role.rds_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# RDS MySQL Instance using Terraform Registry Module
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  # Database identification
  identifier = "${var.environment}-movie-analyst-db"

  # Engine configuration
  engine               = "mysql"
  engine_version       = var.engine_version
  family               = "mysql8.0"
  major_engine_version = "8.0"
  instance_class       = var.instance_class

  # Storage configuration
  allocated_storage     = var.allocated_storage
  max_allocated_storage = 100
  storage_encrypted     = true
  storage_type          = "gp3"

  # Database credentials
  db_name  = var.db_name
  username = var.db_username
  manage_master_user_password = true

  port     = 3306

  # Network configuration
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false

  # High Availability (workspace-aware)
  multi_az = var.environment == "prod" ? true : false

  # Backup configuration (workspace-aware)
  backup_retention_period = var.environment == "prod" ? 7 : 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # CloudWatch Logs
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  # Deletion protection (workspace-aware)
  deletion_protection = var.environment == "prod" ? true : false

  # Final snapshot (workspace-aware)
  skip_final_snapshot = var.environment == "prod" ? false : true


  # Performance Insights - Disabled for cost optimization
  performance_insights_enabled = false

  # Enhanced Monitoring (workspace-aware)
  monitoring_interval = var.environment == "prod" ? 60 : 0
  monitoring_role_arn = var.environment == "prod" ? aws_iam_role.rds_monitoring[0].arn : null

  # Parameter group settings
  parameters = [
    {
      name  = "character_set_server"
      value = "utf8mb4"
    },
    {
      name  = "collation_server"
      value = "utf8mb4_unicode_ci"
    },
    {
      name  = "max_connections"
      value = var.environment == "prod" ? "200" : "100"
    }
  ]

  tags = {
    Name        = "${var.environment}-movie-analyst-db"
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = "movie-analyst"
  }
}
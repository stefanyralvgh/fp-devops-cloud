# CLOUDWATCH DASHBOARD

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.environment}-${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # ROW 1: ALB METRICS
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 0
        y      = 0
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "ALB - Requests & Response Time"
          yAxis = {
            left = {
              label = "Count / Seconds"
            }
          }
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 12
        y      = 0
        properties = {
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", var.target_group_arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "TargetGroup", var.target_group_arn_suffix]
          ]
          period = 60
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "ALB - Target Health"
          yAxis = {
            left = {
              label = "Count"
              min   = 0
            }
          }
        }
      },

      # ROW 2: EC2 FRONTEND METRICS
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 0
        y      = 6
        properties = {
          metrics = [
            for instance_id in var.frontend_instance_ids :
            ["AWS/EC2", "CPUUtilization", "InstanceId", instance_id]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Frontend Instances - CPU Utilization"
          yAxis = {
            left = {
              label = "Percent"
              min   = 0
              max   = 100
            }
          }
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 12
        y      = 6
        properties = {
          metrics = [
            for instance_id in var.frontend_instance_ids :
            ["AWS/EC2", "NetworkIn", "InstanceId", instance_id]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Frontend Instances - Network In"
          yAxis = {
            left = {
              label = "Bytes"
            }
          }
        }
      },

      # ROW 3: EC2 BACKEND METRICS
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 0
        y      = 12
        properties = {
          metrics = [
            for instance_id in var.backend_instance_ids :
            ["AWS/EC2", "CPUUtilization", "InstanceId", instance_id]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "Backend Instances - CPU Utilization"
          yAxis = {
            left = {
              label = "Percent"
              min   = 0
              max   = 100
            }
          }
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 12
        y      = 12
        properties = {
          metrics = [
            for instance_id in var.backend_instance_ids :
            ["AWS/EC2", "NetworkOut", "InstanceId", instance_id]
          ]
          period = 300
          stat   = "Sum"
          region = data.aws_region.current.name
          title  = "Backend Instances - Network Out"
          yAxis = {
            left = {
              label = "Bytes"
            }
          }
        }
      },

      # ROW 4: RDS METRICS
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 0
        y      = 18
        properties = {
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.rds_instance_id]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "RDS - CPU Utilization"
          yAxis = {
            left = {
              label = "Percent"
              min   = 0
              max   = 100
            }
          }
        }
      },
      {
        type   = "metric"
        width  = 12
        height = 6
        x      = 12
        y      = 18
        properties = {
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.rds_instance_id]
          ]
          period = 60
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "RDS - Database Connections"
          yAxis = {
            left = {
              label = "Count"
              min   = 0
            }
          }
        }
      },
      {
        type   = "metric"
        width  = 24
        height = 6
        x      = 0
        y      = 24
        properties = {
          metrics = [
            ["AWS/RDS", "FreeableMemory", "DBInstanceIdentifier", var.rds_instance_id],
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", var.rds_instance_id]
          ]
          period = 300
          stat   = "Average"
          region = data.aws_region.current.name
          title  = "RDS - Memory & Storage"
          yAxis = {
            left = {
              label = "Bytes"
            }
          }
        }
      }
    ]
  })
}

# DATA SOURCE FOR CURRENT REGION
data "aws_region" "current" {}

# SNS TOPIC FOR ALARMS (OPTIONAL)
resource "aws_sns_topic" "alarms" {
  count = var.enable_sns_alerts ? 1 : 0

  name = "${var.environment}-${var.project_name}-alarms"

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-${var.project_name}-alarms"
      Environment = var.environment
    }
  )
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count = var.enable_sns_alerts && var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CLOUDWATCH ALARMS - EC2 CPU
resource "aws_cloudwatch_metric_alarm" "frontend_cpu_high" {
  count = length(var.frontend_instance_ids)

  alarm_name          = "${var.environment}-frontend-${count.index + 1}-cpu-high"
  alarm_description   = "Alert when Frontend-${count.index + 1} CPU exceeds ${var.cpu_alarm_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = var.frontend_instance_ids[count.index]
  }

  alarm_actions = var.enable_sns_alerts ? [aws_sns_topic.alarms[0].arn] : []

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-frontend-${count.index + 1}-cpu-alarm"
      Environment = var.environment
      Instance    = "frontend-${count.index + 1}"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "backend_cpu_high" {
  count = length(var.backend_instance_ids)

  alarm_name          = "${var.environment}-backend-${count.index + 1}-cpu-high"
  alarm_description   = "Alert when Backend-${count.index + 1} CPU exceeds ${var.cpu_alarm_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = var.backend_instance_ids[count.index]
  }

  alarm_actions = var.enable_sns_alerts ? [aws_sns_topic.alarms[0].arn] : []

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-backend-${count.index + 1}-cpu-alarm"
      Environment = var.environment
      Instance    = "backend-${count.index + 1}"
    }
  )
}

# CLOUDWATCH ALARMS - RDS
resource "aws_cloudwatch_metric_alarm" "rds_connections_high" {
  alarm_name          = "${var.environment}-rds-connections-high"
  alarm_description   = "Alert when RDS connections exceed ${var.rds_connections_threshold}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.rds_connections_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = var.enable_sns_alerts ? [aws_sns_topic.alarms[0].arn] : []

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-rds-connections-alarm"
      Environment = var.environment
      Resource    = "rds"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  alarm_name          = "${var.environment}-rds-cpu-high"
  alarm_description   = "Alert when RDS CPU exceeds ${var.cpu_alarm_threshold}%"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_id
  }

  alarm_actions = var.enable_sns_alerts ? [aws_sns_topic.alarms[0].arn] : []

  tags = merge(
    var.tags,
    {
      Name        = "${var.environment}-rds-cpu-alarm"
      Environment = var.environment
      Resource    = "rds"
    }
  )
}
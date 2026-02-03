# DASHBOARD OUTPUTS

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard"
  value       = aws_cloudwatch_dashboard.main.dashboard_name
}

output "dashboard_url" {
  description = "URL to access the CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}


# ALARM OUTPUTS

output "frontend_cpu_alarm_names" {
  description = "Names of frontend CPU alarms"
  value       = aws_cloudwatch_metric_alarm.frontend_cpu_high[*].alarm_name
}

output "backend_cpu_alarm_names" {
  description = "Names of backend CPU alarms"
  value       = aws_cloudwatch_metric_alarm.backend_cpu_high[*].alarm_name
}

output "rds_alarm_names" {
  description = "Names of RDS alarms"
  value = [
    aws_cloudwatch_metric_alarm.rds_connections_high.alarm_name,
    aws_cloudwatch_metric_alarm.rds_cpu_high.alarm_name
  ]
}


# SNS TOPIC OUTPUT 

output "sns_topic_arn" {
  description = "ARN of SNS topic for alarms (if enabled)"
  value       = var.enable_sns_alerts ? aws_sns_topic.alarms[0].arn : null
}
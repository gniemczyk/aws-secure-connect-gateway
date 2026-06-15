output "cluster_name" {
  value = aws_ecs_cluster.bastion_cluster.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.bastion_task.arn
}

output "service_name" {
  value = aws_ecs_service.bastion_service.name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.bastion_logs.name
}

output "ecs_exec_log_group_name" {
  value = aws_cloudwatch_log_group.ecs_exec_logs.name
}

output "ecr_repository_url" {
  value = aws_ecr_repository.bastion.repository_url
}

output "lambda_function_name" {
  value = aws_lambda_function.auto_stop.function_name
}

output "cloudwatch_alarm_names" {
  value = [
    aws_cloudwatch_metric_alarm.lambda_errors.alarm_name,
    aws_cloudwatch_metric_alarm.auto_stop_failure.alarm_name
  ]
}

output "console_notification_info" {
  description = "AWS Console alert location"
  value       = "CloudWatch -> Alarms -> ${var.bastion_name}-stop-failure (ALARM when auto-stop fails)"
}

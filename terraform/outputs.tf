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

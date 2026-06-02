# Wyjścia z konfiguracji Terraform

output "cluster_name" {
  description = "Nazwa klastra ECS"
  value       = aws_ecs_cluster.bastion_cluster.name
}

output "task_id" {
  description = "ID uruchomionego tasku"
  value       = aws_ecs_task.bastion_task.id
}

output "subnet_id" {
  description = "ID utworzonej podsieci"
  value       = aws_subnet.bastion_subnet.id
}

output "security_group_id" {
  description = "ID utworzonej Security Group"
  value       = aws_security_group.bastion_sg.id
}

output "log_group_name" {
  description = "Nazwa grupy logów CloudWatch"
  value       = aws_cloudwatch_log_group.bastion_logs.name
}

output "serveo_subdomain" {
  description = "Subdomena Serveo.net użyta dla tunelu"
  value       = var.serveo_subdomain != "" ? var.serveo_subdomain : "${var.bastion_name}-${random_id.serveo_suffix.hex}"
}

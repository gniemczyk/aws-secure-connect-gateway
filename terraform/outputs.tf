# Outputs from Terraform configuration

output "cluster_name" {
  description = "ECS Cluster name"
  value       = aws_ecs_cluster.bastion_cluster.name
}

output "cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.bastion_cluster.arn
}

output "task_definition_arn" {
  description = "ECS Task Definition ARN (latest revision)"
  value       = aws_ecs_task_definition.bastion_task.arn
}

output "subnet_id" {
  description = "Subnet ID (reused if exists, or newly created)"
  value       = local.bastion_subnet_id
}

output "security_group_id" {
  description = "Security Group ID (reused if exists, or newly created)"
  value       = local.bastion_sg_id
}

output "log_group_name" {
  description = "CloudWatch Log Group name"
  value       = aws_cloudwatch_log_group.bastion_logs.name
}

output "bore_port" {
  description = "TCP port on bore.pub for SSH connection"
  value       = var.bore_port
}

output "service_name" {
  description = "ECS Service name"
  value       = aws_ecs_service.bastion_service.name
}

output "connection_command" {
  description = "SSH command to connect to bastion"
  value       = "ssh -p ${var.bore_port} root@bore.pub"
}

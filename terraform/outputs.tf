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
  description = "ECS Task Definition ARN"
  value       = aws_ecs_task_definition.bastion_task.arn
}

output "subnet_id" {
  description = "Subnet ID"
  value       = aws_subnet.bastion_subnet.id
}

output "subnet_cidr" {
  description = "Subnet CIDR block (automatically selected from available range)"
  value       = aws_subnet.bastion_subnet.cidr_block
}

output "security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.bastion_sg.id
}

output "log_group_name" {
  description = "CloudWatch Log Group name"
  value       = local.log_group_name
}

output "serveo_subdomain" {
  description = "Serveo.net subdomain for tunnel"
  value       = var.serveo_subdomain != "" ? var.serveo_subdomain : "${var.bastion_name}-${random_id.serveo_suffix.hex}"
}


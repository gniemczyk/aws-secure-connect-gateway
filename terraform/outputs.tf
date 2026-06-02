# Outputs from Terraform configuration

output "debug_existing_subnets" {
  description = "DEBUG: All existing subnets in VPC"
  value       = [for subnet in data.aws_subnet.existing : "${subnet.id}: ${subnet.cidr_block}"]
}

output "debug_available_cidrs" {
  description = "DEBUG: First 10 available CIDR blocks"
  value       = slice(local.available_cidrs, 0, min(10, length(local.available_cidrs)))
}

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
  description = "Subnet ID (reused if exists, or newly created)"
  value       = local.bastion_subnet_id
}

output "subnet_cidr" {
  description = "Subnet CIDR block (reused if exists, or auto-allocated)"
  value       = length(data.aws_subnets.existing_bastion.ids) > 0 ? data.aws_subnet.existing_bastion[0].cidr_block : aws_subnet.bastion_subnet[0].cidr_block
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


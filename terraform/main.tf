# Główna konfiguracja Terraform dla efemerycznego bastionu ECS Fargate

provider "aws" {
  region = var.region
}

# --- NETWORKING ---

# Get existing VPC
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Get ALL existing subnets in VPC (to detect used CIDRs)
data "aws_subnets" "existing" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

# Get details of existing subnets
data "aws_subnet" "existing" {
  for_each = toset(data.aws_subnets.existing.ids)
  id       = each.value
}

# Get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Find first available CIDR block that doesn't conflict
# Algorithm:
# 1. VPC CIDR = 10.0.0.0/16
# 2. Existing subnets occupy specific /24s (e.g., 10.0.1.0/24, 10.0.2.0/24)
# 3. Generate all possible /24s from VPC (0-255)
# 4. Filter out ones that conflict with existing
# 5. Pick the first available one
locals {
  vpc_cidr       = data.aws_vpc.selected.cidr_block
  existing_cidrs = toset([for subnet in data.aws_subnet.existing : subnet.cidr_block])
  
  # Generate ALL possible /24 CIDRs from this VPC
  all_possible_cidrs = [
    for idx in range(0, 256) :
    cidrsubnet(local.vpc_cidr, 8, idx)
  ]
  
  # Filter to only AVAILABLE CIDRs (not in existing_cidrs)
  available_cidrs = [
    for cidr in local.all_possible_cidrs :
    cidr if !contains(local.existing_cidrs, cidr)
  ]
  
  # Use first available, or fallback to first possible (shouldn't happen)
  new_subnet_cidr = length(local.available_cidrs) > 0 ? local.available_cidrs[0] : local.all_possible_cidrs[0]
}

# Create temporary subnet for bastion
resource "aws_subnet" "bastion_subnet" {
  vpc_id                  = var.vpc_id
  cidr_block              = local.new_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.bastion_name}-subnet"
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }

  lifecycle {
    ignore_changes = [tags]
    create_before_destroy = true
  }
}

# Security Group - inbound blocked, outbound SSH + DNS only
resource "aws_security_group" "bastion_sg" {
  name_prefix = "${var.bastion_name}-sg-"
  description = "Security Group for ephemeral bastion - blocked inbound, SSH+DNS outbound"
  vpc_id      = var.vpc_id

  # Outbound SSH (port 22) for Serveo.net tunnel
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound DNS (port 53) for name resolution
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound HTTPS (port 443) for ECR authentication and image pull
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.bastion_name}-sg"
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# --- ECS ---

# ECS Cluster
resource "aws_ecs_cluster" "bastion_cluster" {
  name = "${var.bastion_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

# Try to get existing CloudWatch Log Group (if it exists from previous run)
data "aws_cloudwatch_log_group" "existing" {
  name = "/ecs/${var.bastion_name}"
}

# Create log group only if it doesn't already exist
resource "aws_cloudwatch_log_group" "bastion_logs" {
  # Skip creation if log group already exists
  count             = try(data.aws_cloudwatch_log_group.existing.arn, null) != null ? 0 : 1
  name              = "/ecs/${var.bastion_name}"
  retention_in_days = 1
  skip_destroy      = true

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

# Use existing or newly created log group
locals {
  log_group_arn  = try(data.aws_cloudwatch_log_group.existing.arn, aws_cloudwatch_log_group.bastion_logs[0].arn)
  log_group_name = try(data.aws_cloudwatch_log_group.existing.name, aws_cloudwatch_log_group.bastion_logs[0].name)
}

# IAM Role for ECS Task Execution
data "aws_iam_policy_document" "ecs_task_execution_role_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name_prefix        = "${var.bastion_name}-exec-role-"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_role_assume.json

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Random suffix for Serveo subdomain
resource "random_id" "serveo_suffix" {
  byte_length = 4
}

# ECS Task Definition (no task execution - workflow will run it on-demand)
resource "aws_ecs_task_definition" "bastion_task" {
  family                   = "${var.bastion_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "bastion"
      image     = var.container_image
      essential = true

      # Security hardening
      readonlyRootFilesystem = true
      disableNetworking      = false

      # Run as non-root user (nobody - UID 65534)
      user = "65534:65534"

      # No privilege escalation
      privileged = false

      # Drop all capabilities
      linuxParameters = {
        capabilities = {
          drop = ["ALL"]
          add  = []
        }
        devices = []
      }

      # No mount points
      mountPoints = []

      # CloudWatch Logs
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.log_group_name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "bastion"
        }
      }

      # Environment variables
      environment = [
        {
          name  = "SERVEO_SUBDOMAIN"
          value = var.serveo_subdomain != "" ? var.serveo_subdomain : "${var.bastion_name}-${random_id.serveo_suffix.hex}"
        }
      ]

      # No secrets
      secrets = []
    }
  ])

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

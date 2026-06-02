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
# 3. Find first /24 index (0-255) that is NOT used
# 4. Create new subnet with that /24
locals {
  vpc_cidr       = data.aws_vpc.selected.cidr_block
  existing_cidrs = toset([for subnet in data.aws_subnet.existing : subnet.cidr_block])
  
  # Try CIDR blocks from 10.0.0.0/24 to 10.0.255.0/24
  # Find first one NOT in existing_cidrs
  available_subnet_index = range(0, 256)[index(
    [for idx in range(0, 256) : true if !contains(local.existing_cidrs, cidrsubnet(local.vpc_cidr, 8, idx))],
    true
  )]
  
  new_subnet_cidr = cidrsubnet(local.vpc_cidr, 8, local.available_subnet_index)
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

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "bastion_logs" {
  name              = "/ecs/${var.bastion_name}"
  retention_in_days = 1
  skip_destroy      = true

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
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
          "awslogs-group"         = aws_cloudwatch_log_group.bastion_logs.name
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

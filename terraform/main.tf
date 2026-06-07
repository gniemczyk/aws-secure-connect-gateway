# Główna konfiguracja Terraform dla efemerycznego bastionu ECS Fargate

provider "aws" {
  region = var.region
}

# --- NETWORKING ---

# Get existing VPC
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Find Internet Gateway attached to VPC (required for outbound connectivity)
data "aws_internet_gateway" "selected" {
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

# Try to find existing ephemeral-bastion subnet (from previous run)
data "aws_subnets" "existing_bastion" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "tag:Environment"
    values = ["ephemeral"]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.bastion_name}-subnet"]
  }
}

# Get details of existing bastion subnet if found
data "aws_subnet" "existing_bastion" {
  count = length(data.aws_subnets.existing_bastion.ids) > 0 ? 1 : 0
  id    = data.aws_subnets.existing_bastion.ids[0]
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

  # Use first available, or fallback to first possible
  new_subnet_cidr = length(local.available_cidrs) > 0 ? local.available_cidrs[0] : local.all_possible_cidrs[0]
}

# Create temporary subnet for bastion (only if doesn't already exist)
resource "aws_subnet" "bastion_subnet" {
  count                   = length(data.aws_subnets.existing_bastion.ids) > 0 ? 0 : 1
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
  }
}

# Use existing bastion subnet if found, or newly created one
locals {
  bastion_subnet_id = length(data.aws_subnets.existing_bastion.ids) > 0 ? data.aws_subnets.existing_bastion.ids[0] : aws_subnet.bastion_subnet[0].id
}

# --- ROUTE TABLE (zapewnia dostep do internetu przez IGW) ---

resource "aws_route_table" "bastion_rt" {
  vpc_id = var.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.aws_internet_gateway.selected.id
  }

  tags = {
    Name        = "${var.bastion_name}-rt"
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

resource "aws_route_table_association" "bastion_rt_assoc" {
  subnet_id      = local.bastion_subnet_id
  route_table_id = aws_route_table.bastion_rt.id
}

# --- SECURITY GROUP ---

# Try to find existing ephemeral-bastion security group (from previous run)
data "aws_security_groups" "existing_bastion_sg" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "tag:Environment"
    values = ["ephemeral"]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.bastion_name}-sg"]
  }
}

# Security Group - inbound blocked, outbound SSH + DNS + HTTPS only
resource "aws_security_group" "bastion_sg" {
  count       = length(data.aws_security_groups.existing_bastion_sg.ids) > 0 ? 0 : 1
  name        = "${var.bastion_name}-sg"
  description = "Security Group for ephemeral bastion - blocked inbound, SSH+DNS+HTTPS outbound"
  vpc_id      = var.vpc_id

  # Outbound SSH (port 22) for Serveo.net tunnel
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound DNS (port 53 TCP+UDP) for name resolution
  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
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
    ignore_changes = [tags]
  }
}

# Use existing bastion SG if found, or newly created one
locals {
  bastion_sg_id = length(data.aws_security_groups.existing_bastion_sg.ids) > 0 ? data.aws_security_groups.existing_bastion_sg.ids[0] : aws_security_group.bastion_sg[0].id
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

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }

  lifecycle {
    # Ignoruj zmiany retention (może być zmienione ręcznie)
    ignore_changes = [retention_in_days]
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
  name               = "${var.bastion_name}-exec-role"
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

# Computed subdomain (passed from workflow, always fresh random)
locals {
  serveo_subdomain = var.serveo_subdomain
}

# ECS Task Definition
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

      # Filesystem musi byc writable dla generowania kluczy SSH
      readonlyRootFilesystem = false
      disableNetworking      = false

      # Run as root (wymagane dla sshd)
      user = "0:0"

      # No extra privilege escalation
      privileged = false

      # Fargate - nie mozna dodawac capabilities, usuwamy zbedne
      linuxParameters = {
        initProcessEnabled = true
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
          value = local.serveo_subdomain
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

# --- ECS SERVICE (pilnuje aby zawsze byl DOKLADNIE 1 task uruchomiony) ---

resource "aws_ecs_service" "bastion_service" {
  name            = "${var.bastion_name}-service"
  cluster         = aws_ecs_cluster.bastion_cluster.id
  task_definition = aws_ecs_task_definition.bastion_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # KLUCZOWE: deployment config zapewnia ze NIGDY nie ma wiecej niz 1 task
  # minimum_healthy_percent=0 -> ECS najpierw ZATRZYMA stary task
  # maximum_percent=100 -> ECS NIGDY nie uruchomi wiecej niz 1 task
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = [local.bastion_subnet_id]
    security_groups  = [local.bastion_sg_id]
    assign_public_ip = true
  }

  # NIE ignorujemy task_definition - chcemy aby service zawsze uzywal najnowszej
  # lifecycle {
  #   ignore_changes = [task_definition]
  # }

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_ecs_task_definition.bastion_task,
    aws_cloudwatch_log_group.bastion_logs,
    aws_route_table_association.bastion_rt_assoc
  ]
}

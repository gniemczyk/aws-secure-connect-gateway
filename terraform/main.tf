# Główna konfiguracja Terraform dla efemerycznego bastionu ECS Fargate

provider "aws" {
  region = var.region
}

# --- NETWORKING ---

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_internet_gateway" "selected" {
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

# Find existing bastion subnet
data "aws_subnets" "existing_bastion" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.bastion_name}-subnet"]
  }
}

data "aws_subnet" "existing_bastion" {
  count = length(data.aws_subnets.existing_bastion.ids) > 0 ? 1 : 0
  id    = data.aws_subnets.existing_bastion.ids[0]
}

data "aws_subnets" "existing" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

data "aws_subnet" "existing" {
  for_each = toset(data.aws_subnets.existing.ids)
  id       = each.value
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  vpc_cidr       = data.aws_vpc.selected.cidr_block
  existing_cidrs = toset([for subnet in data.aws_subnet.existing : subnet.cidr_block])
  all_possible_cidrs = [for idx in range(0, 256) : cidrsubnet(local.vpc_cidr, 8, idx)]
  available_cidrs    = [for cidr in local.all_possible_cidrs : cidr if !contains(local.existing_cidrs, cidr)]
  new_subnet_cidr    = length(local.available_cidrs) > 0 ? local.available_cidrs[0] : local.all_possible_cidrs[0]
}

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
}

locals {
  bastion_subnet_id = length(data.aws_subnets.existing_bastion.ids) > 0 ? data.aws_subnets.existing_bastion.ids[0] : aws_subnet.bastion_subnet[0].id
}

# --- ROUTE TABLE ---

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

data "aws_security_groups" "existing_bastion_sg" {
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = ["${var.bastion_name}-sg"]
  }
}

resource "aws_security_group" "bastion_sg" {
  count       = length(data.aws_security_groups.existing_bastion_sg.ids) > 0 ? 0 : 1
  name        = "${var.bastion_name}-sg"
  description = "Security Group for ephemeral bastion - outbound only"
  vpc_id      = var.vpc_id

  # Outbound ALL (ECS Exec needs SSM endpoints + general bastion use)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.bastion_name}-sg"
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

locals {
  bastion_sg_id = length(data.aws_security_groups.existing_bastion_sg.ids) > 0 ? data.aws_security_groups.existing_bastion_sg.ids[0] : aws_security_group.bastion_sg[0].id
}

# --- ECS ---

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

resource "aws_cloudwatch_log_group" "bastion_logs" {
  name              = "/ecs/${var.bastion_name}"
  retention_in_days = 1

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }

  lifecycle {
    ignore_changes = [retention_in_days]
  }
}

# --- IAM ---

# Task Execution Role (pulling images, writing logs)
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.bastion_name}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Role (what the container can do - needs SSM for ECS Exec)
resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.bastion_name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

# SSM permissions for ECS Exec
resource "aws_iam_role_policy" "ecs_exec_ssm" {
  name = "${var.bastion_name}-ssm-policy"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- ECS TASK DEFINITION ---

resource "aws_ecs_task_definition" "bastion_task" {
  family                   = "${var.bastion_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "bastion"
      image     = var.container_image
      essential = true

      linuxParameters = {
        initProcessEnabled = true
      }

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.bastion_logs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "bastion"
        }
      }
    }
  ])

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

# --- ECS SERVICE (exactly 1 task, ECS Exec enabled) ---

resource "aws_ecs_service" "bastion_service" {
  name            = "${var.bastion_name}-service"
  cluster         = aws_ecs_cluster.bastion_cluster.id
  task_definition = aws_ecs_task_definition.bastion_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  platform_version = "LATEST"

  # ECS Exec - pozwala na polaczenie przez aws ecs execute-command
  enable_execute_command = true

  # Max 1 task: stop old first, then start new
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  network_configuration {
    subnets          = [local.bastion_subnet_id]
    security_groups  = [local.bastion_sg_id]
    assign_public_ip = true
  }

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

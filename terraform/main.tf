# Glowna konfiguracja Terraform dla efemerycznego bastionu ECS Fargate

provider "aws" {
  region = var.region
}

# --- ECR ---

resource "aws_ecr_repository" "bastion" {
  name                 = var.ecr_repository
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }

  # Pozwala usunąć repozytorium nawet z obrazami przy terraform destroy
  force_delete = true

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_ecr_lifecycle_policy" "bastion" {
  repository = aws_ecr_repository.bastion.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Zachowaj tylko 2 najnowsze obrazy"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 2
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# --- SIEC ---

data "aws_vpc" "selected" {
  id = var.vpc_id
}

data "aws_internet_gateway" "selected" {
  filter {
    name   = "attachment.vpc-id"
    values = [var.vpc_id]
  }
}

# Subnet zawsze tworzymy nowy - nie importujemy istniejących
# To gwarantuje że Terraform będzie potrafić go usunąć

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
  vpc_cidr           = data.aws_vpc.selected.cidr_block
  existing_cidrs     = toset([for subnet in data.aws_subnet.existing : subnet.cidr_block])
  all_possible_cidrs = [for idx in range(0, 256) : cidrsubnet(local.vpc_cidr, 8, idx)]
  available_cidrs    = [for cidr in local.all_possible_cidrs : cidr if !contains(local.existing_cidrs, cidr)]
  new_subnet_cidr    = length(local.available_cidrs) > 0 ? local.available_cidrs[0] : local.all_possible_cidrs[0]
}

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
}

locals {
  bastion_subnet_id = aws_subnet.bastion_subnet.id
}

# --- TABELA TRAS ---

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

  depends_on = [aws_route_table.bastion_rt]
}

# --- GRUPA ZABEZPIECZEN ---

# Security Group zawsze tworzymy nowy - nie importujemy istniejących

resource "aws_security_group" "bastion_sg" {
  name        = "${var.bastion_name}-sg"
  description = "Security Group for ephemeral bastion - outbound only"
  vpc_id      = var.vpc_id

  tags = {
    Name        = "${var.bastion_name}-sg"
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  bastion_sg_id = aws_security_group.bastion_sg.id
}

# Regula wyjsciowa (egress) - WSZYSTKIE protokoly/porty
resource "aws_security_group_rule" "bastion_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion_sg.id
}

# --- ECS ---

resource "aws_ecs_cluster" "bastion_cluster" {
  name = "${var.bastion_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      logging = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = false
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_exec_logs.name
      }
    }
  }

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

resource "aws_cloudwatch_log_group" "bastion_logs" {
  name              = "/ecs/${var.bastion_name}"
  retention_in_days = 1
  skip_destroy      = false

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }

  lifecycle {
    ignore_changes = [retention_in_days]
  }
}

resource "aws_cloudwatch_log_group" "ecs_exec_logs" {
  name              = "/ecs/${var.bastion_name}-exec"
  retention_in_days = 1
  skip_destroy      = false

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }

  lifecycle {
    ignore_changes = [retention_in_days]
  }
}

# --- IAM ---

# Rola wykonawcza zadania (Task Execution Role) - pobieranie obrazow, zapisywanie logow
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

# Rola zadania (Task Role) - uprawnienia kontenera, wymaga SSM dla ECS Exec
resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.bastion_name}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

# Uprawnienia SSM dla ECS Exec
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
      },
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "${aws_cloudwatch_log_group.ecs_exec_logs.arn}:*"
        ]
      }
    ]
  })
}

# --- DEFINICJA ZADANIA ECS ---

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

      healthCheck = {
        command     = ["CMD-SHELL", "pgrep -f start.sh || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
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

# --- SERWIS ECS (dokladnie 1 zadanie, ECS Exec wlaczony) ---

resource "aws_ecs_service" "bastion_service" {
  name             = "${var.bastion_name}-service"
  cluster          = aws_ecs_cluster.bastion_cluster.id
  task_definition  = aws_ecs_task_definition.bastion_task.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  # ECS Exec - umozliwia polaczenie przez aws ecs execute-command
  enable_execute_command = true

  # Maksymalnie 1 zadanie: najpierw zatrzymaj stare, potem uruchom nowe
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

# --- HARMONOGRAM AUTO-STOP ---

# Lambda do zatrzymania serwisu ECS
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_stop.py"
  output_path = "${path.module}/lambda_stop.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.bastion_name}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy" "lambda_ecs_policy" {
  name = "${var.bastion_name}-lambda-ecs-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ]
        Resource = [
          aws_ecs_service.bastion_service.id,
          "${aws_ecs_service.bastion_service.id}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "auto_stop" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "${var.bastion_name}-auto-stop"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_stop.lambda_handler"
  runtime         = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      CLUSTER_NAME = aws_ecs_cluster.bastion_cluster.name
      SERVICE_NAME = aws_ecs_service.bastion_service.name
    }
  }

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.bastion_name}-auto-stop"
  retention_in_days = 1
  skip_destroy      = false

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auto_stop.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.auto_stop.arn
}

resource "aws_cloudwatch_event_rule" "auto_stop" {
  name                = "${var.bastion_name}-auto-stop"
  description         = "Automatyczne zatrzymanie bastionu"
  schedule_expression = var.auto_stop_cron

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

resource "aws_cloudwatch_event_target" "auto_stop" {
  rule           = aws_cloudwatch_event_rule.auto_stop.name
  target_id      = "${var.bastion_name}-auto-stop-target"
  arn            = aws_lambda_function.auto_stop.arn

  retry_policy {
    maximum_retry_attempts = 3
    maximum_event_age_in_seconds = 3600
  }
}

# --- CLOUDWATCH ALARM ---

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.bastion_name}-auto-stop-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert: Lambda do zatrzymania bastionu się nie powiódł"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.auto_stop.function_name
  }

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

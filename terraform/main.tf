# Główna konfiguracja Terraform dla efemerycznego bastionu ECS Fargate

provider "aws" {
  region = var.region
}

# --- Sieć ---

# Pobranie danych VPC
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# Pobranie wszystkich podsieci w VPC aby uniknąć kolizji CIDR
data "aws_subnets" "existing" {
  vpc_id = var.vpc_id
}

# Pobranie CIDR bloku VPC
data "aws_vpc_cidr_block_associations" "vpc_cidrs" {
  vpc_id = var.vpc_id
}

# Pobranie dostępnych stref dostępności
data "aws_availability_zones" "available" {
  state = "available"
}

# Losowy sufiks dla unikalności podsieci
resource "random_id" "subnet_suffix" {
  byte_length = 2
}

# Tworzenie tymczasowej podsieci IPv4 wewnątrz VPC
# Używamy losowego CIDR z zakresu VPC, unikając kolizji
resource "aws_subnet" "bastion_subnet" {
  vpc_id                  = var.vpc_id
  cidr_block              = cidrsubnet(data.aws_vpc.selected.cidr_block, 8, random_id.subnet_suffix.dec % 256)
  availability_zone       = element(data.aws_availability_zones.available.names, 0)
  map_public_ip_on_launch = true # Potrzebne dla dostępu do internetu (Serveo.net)

  tags = {
    Name        = "${var.bastion_name}-subnet"
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }

  lifecycle {
    ignore_changes = [tags]
  }
}

# Tymczasowa Security Group - zablokowany inbound, otwarty outbound
resource "aws_security_group" "bastion_sg" {
  name_prefix = "${var.bastion_name}-sg-"
  description = "Security Group dla efemerycznego bastionu - zablokowany inbound, otwarty outbound"
  vpc_id      = var.vpc_id

  # Brak reguł inbound - całkowicie zablokowany
  # To jest bezpieczne, bo kontener nie przyjmuje połączeń, tylko inicjuje tunel wychodzący

  # Outbound - tylko SSH (port 22) dla połączenia z Serveo.net
  egress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound DNS (port 53) dla resolucji nazw
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

# CloudWatch Log Group dla kontenera
resource "aws_cloudwatch_log_group" "bastion_logs" {
  name              = "/ecs/${var.bastion_name}"
  retention_in_days = 1 # Tylko 1 dzień retencji dla logów

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

# IAM Role dla execution task (potrzebne do pobrania obrazu i wysyłania logów)
data "aws_iam_policy_document" "ecs_task_execution_role" {
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
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_role.json

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Task Definition z maksymalnym hardeningiem
resource "aws_ecs_task_definition" "bastion_task" {
  family                   = "${var.bastion_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn # Brak dodatkowych uprawnień

  container_definitions = jsonencode([
    {
      name      = "bastion"
      image     = var.container_image
      essential = true

      # Maksymalne hardening bezpieczeństwa
      readonlyRootFilesystem = true  # System plików całkowicie zablokowany do zapisu
      disableNetworking      = false # Potrzebne dla połączenia z Serveo.net

      # Uruchomienie jako nieuprzywilejowany użytkownik
      user = "65534:65534" # nobody user (UID 65534)

      # Brak uprawnień do escalacji uprawnień
      privileged = false

      # Brak możliwości dodawania capabilities
      linuxParameters = {
        capabilities = {
          drop = ["ALL"]
          add  = []
        }
        devices = []
      }

      # Tylko niezbędne mounty (tmpfs dla /tmp jeśli potrzebne)
      mountPoints = []

      # Logi do CloudWatch
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.bastion_logs.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "bastion"
        }
      }

      # Zmienne środowiskowe dla tunelu Serveo.net
      environment = [
        {
          name  = "SERVEO_SUBDOMAIN"
          value = var.serveo_subdomain != "" ? var.serveo_subdomain : "${var.bastion_name}-${random_id.serveo_suffix.hex}"
        }
      ]

      # Brak sekretów
      secrets = []
    }
  ])

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

# Losowy sufiks dla unikalności nazwy tunelu
resource "random_id" "serveo_suffix" {
  byte_length = 4
}

# Uruchomienie pojedynczego tasku (nie Service, tylko Task dla efemeryczności)
resource "aws_ecs_task" "bastion_task" {
  cluster         = aws_ecs_cluster.bastion_cluster.arn
  task_definition = aws_ecs_task_definition.bastion_task.arn
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.bastion_subnet.id]
    security_groups  = [aws_security_group.bastion_sg.id]
    assign_public_ip = true # Potrzebne dla połączenia z Serveo.net
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_task_execution_role_policy]

  tags = {
    Environment = "ephemeral"
    ManagedBy   = "terraform"
  }
}

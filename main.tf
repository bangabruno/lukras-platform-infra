############################################
# Provider & AZs
############################################
provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}

locals {
  name_prefix = var.project_name
  region      = var.aws_region
  azs         = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

############################################
# VPC, Subnets, Rotas
############################################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }

  lifecycle {
    prevent_destroy       = false
    create_before_destroy = true
  }
}

resource "aws_subnet" "public" {
  for_each = {
    "${local.azs[0]}" = "10.0.0.0/24"
    "${local.azs[1]}" = "10.0.1.0/24"
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = { Name = "${local.name_prefix}-public-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each = {
    "${local.azs[0]}" = "10.0.100.0/24"
    "${local.azs[1]}" = "10.0.101.0/24"
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = { Name = "${local.name_prefix}-private-${each.key}" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat_eip" {
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${local.name_prefix}-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = values(aws_subnet.public)[0].id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "${local.name_prefix}-nat" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "${local.name_prefix}-private-rt" }
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

############################################
# Security Groups
############################################
# Para tasks ECS (somente saída; sem portas de entrada pois não expomos serviços)
resource "aws_security_group" "ecs_sg" {
  name        = "${local.name_prefix}-ecs-sg"
  vpc_id      = aws_vpc.main.id
  description = "ECS tasks egress only"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-ecs-sg" }
}

# Para EFS aceitar NFS (2049/TCP) apenas das ECS tasks
resource "aws_security_group" "efs_sg" {
  name        = "${local.name_prefix}-efs-sg"
  description = "Allow NFS from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "NFS from ECS tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-efs-sg" }
}

############################################
# CloudWatch Logs (console)
############################################
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 30
}

############################################
# EFS para logs (persistente)
############################################
resource "aws_efs_file_system" "bot_logs" {
  creation_token   = "${local.name_prefix}-bot-logs"
  performance_mode = "generalPurpose"
  encrypted        = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = { Name = "${local.name_prefix}-bot-logs" }
}

resource "aws_efs_mount_target" "bot_logs_mt" {
  for_each = aws_subnet.private

  file_system_id  = aws_efs_file_system.bot_logs.id
  subnet_id       = each.value.id
  security_groups = [aws_security_group.efs_sg.id]
}

############################################
# IAM roles (exec + task) + acesso aos secrets
############################################
data "aws_iam_policy_document" "task_execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution_role" {
  name               = "${local.name_prefix}-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume.json
}

# Política padrão de execução (logs, pull de imagem ECR)
resource "aws_iam_role_policy_attachment" "exec_role_policy" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Permitir GetSecretValue para secrets "prod/lukras/*"
data "aws_iam_policy_document" "secrets_access" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.me.account_id}:secret:prod/lukras/*"]
  }
}

resource "aws_iam_policy" "secrets_access" {
  name   = "${local.name_prefix}-secrets-access"
  policy = data.aws_iam_policy_document.secrets_access.json
}

resource "aws_iam_role_policy_attachment" "exec_role_secrets" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = aws_iam_policy.secrets_access.arn
}

data "aws_caller_identity" "me" {}

# Task role (se sua app precisar acessar AWS APIs diretamente)
resource "aws_iam_role" "task_role" {
  name               = "${local.name_prefix}-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume.json
}

############################################
# ECS Cluster
############################################
resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

############################################
# Secrets por usuário (1 secret JSON por bot)
############################################
# Exigimos que exista um secret por usuário: "prod/lukras/<user>"
data "aws_secretsmanager_secret" "user_secret" {
  for_each = toset(var.users)
  name     = "prod/lukras/${each.key}"
}

############################################
# Task Definition (1 por user) + EFS /<user> -> /app/logs
############################################
resource "aws_ecs_task_definition" "bot_task" {
  for_each = toset(var.users)

  family                   = "${local.name_prefix}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.task_execution_role.arn
  task_role_arn            = aws_iam_role.task_role.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  # Monta o EFS no path /<user> e dentro do container em /app/logs
  volume {
    name = "bot-logs"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.bot_logs.id
      transit_encryption = "ENABLED"
      root_directory     = "/${each.key}"
    }
  }

  container_definitions = jsonencode([{
    name  = each.key
    image = var.container_image
    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = each.key
      }
    }
    mountPoints = [{
      sourceVolume  = "bot-logs"
      containerPath = "/app/logs"
      readOnly      = false
    }]
    environment = [
      { name = "BOT_NAME", value = each.key },

      # seus parâmetros "fixos" (mantidos)
      { name = "LNM_ENABLED", value = "true" },
      { name = "LNM_LEVERAGE", value = "10" },
      { name = "LNM_GET_PRICE_EVERY_SECS", value = "3" },
      { name = "LNM_ORDER_MARGIN_ENTRY_SATS", value = "5000" },
      { name = "LNM_ORDER_MARGIN_ADD_PERCENT", value = "0.2" },
      { name = "LNM_ORDER_MARGIN_CHECK_PERCENT", value = "0.03" },
      { name = "LNM_ORDER_PRICE_VARIATION_USD", value = "100" },
      { name = "LNM_ORDER_TAKE_PROFIT_PERCENT", value = "0.006" },
      { name = "LNM_ORDER_TOTAL_LIMIT", value = "100" },
      { name = "LNM_ORDER_MARGIN_ENTRY_DYNAMIC_ENABLED", value = "true" },
      { name = "LNM_ORDER_PRICE_LIMIT", value = "180000" },
      { name = "LNM_MULTI_ACCOUNT_ENABLED", value = "true" },
      { name = "USER_WALLET", value = "0x7Be83Fbf23E4a0241BFD1b97F1863D44b661B056" },
      { name = "HL_ENABLED", value = "true" },
      { name = "HL_LEVERAGE", value = "10" },
      { name = "HL_GET_PRICE_EVERY_SECS", value = "3" },
      { name = "HL_ORDER_MARGIN_ENTRY_USD", value = "20" },
      { name = "HL_ORDER_PRICE_VARIATION_USD", value = "100" },
      { name = "HL_ORDER_TAKE_PROFIT_PERCENT", value = "0.006" },
      { name = "HL_MAX_MARGIN_ALLOCATED_PERCENT", value = "0.5" }
    ]
    # secrets vindos do secret JSON "prod/lukras/<user>"
    secrets = [
      { name = "LNM_KEY",          valueFrom = "${data.aws_secretsmanager_secret.user_secret[each.key].arn}:LNM_KEY::" },
      { name = "LNM_SECRET",       valueFrom = "${data.aws_secretsmanager_secret.user_secret[each.key].arn}:LNM_SECRET::" },
      { name = "LNM_PASSPHRASE",   valueFrom = "${data.aws_secretsmanager_secret.user_secret[each.key].arn}:LNM_PASSPHRASE::" },
      { name = "LNM_KEY1",         valueFrom = "${data.aws_secretsmanager_secret.user_secret[each.key].arn}:LNM_KEY1::" },
      { name = "LNM_PASSPHRASE1",  valueFrom = "${data.aws_secretsmanager_secret.user_secret[each.key].arn}:LNM_PASSPHRASE1::" },
      { name = "LNM_SECRET1",      valueFrom = "${data.aws_secretsmanager_secret.user_secret[each.key].arn}:LNM_SECRET1::" },
      { name = "HL_PRIVATE_KEY",   valueFrom = "${data.aws_secretsmanager_secret.user_secret[each.key].arn}:HL_PRIVATE_KEY::" }
    ]
  }])

  # Garantir que os Mount Targets existam antes do service tentar subir
  depends_on = [aws_efs_mount_target.bot_logs_mt]
}

############################################
# ECS Service (1 por user)
############################################
resource "aws_ecs_service" "bot_service" {
  for_each        = toset(var.users)
  name            = "${local.name_prefix}-${each.key}"
  cluster         = aws_ecs_cluster.this.id
  launch_type     = "FARGATE"
  desired_count   = 1
  task_definition = aws_ecs_task_definition.bot_task[each.key].arn

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_sg.id]
  }

  depends_on = [aws_efs_mount_target.bot_logs_mt]
}
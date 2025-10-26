########################################
# Provider & Caller
########################################
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

########################################
# Variáveis
########################################
variable "aws_region"     { type = string }
variable "project_name"   { type = string }
variable "enable_alb"     { type = bool }
variable "container_image"{ type = string }
variable "cpu"            { type = number }
variable "memory"         { type = number }
variable "container_port" { type = number }

# users = { "n8w0lff" = { ENV_NAME = "value", ... } }
variable "users" {
  description = "Mapa de usuários -> mapa de variáveis simples (opcionais)."
  type        = map(map(string))
}

########################################
# Infra EXISTENTE (somente data sources)
# (IDs confirmados por você)
########################################

# VPC em uso (NÃO criar outra)
data "aws_vpc" "main" {
  id = "vpc-0305525ea1ca6a1e1"
}

# Subnets privadas em uso
data "aws_subnet" "private_a" { id = "subnet-06c53b145439031a3" } # 10.0.100.0/24 us-east-1a
data "aws_subnet" "private_b" { id = "subnet-01133a83253cbdc8d" } # 10.0.101.0/24 us-east-1b

# (Se um dia for usar ALB, já tem públicas:)
data "aws_subnet" "public_a"  { id = "subnet-0fba36c75cc949407" } # 10.0.0.0/24   us-east-1a
data "aws_subnet" "public_b"  { id = "subnet-01c66fa7137b495a8" } # 10.0.1.0/24   us-east-1b

locals {
  private_subnet_ids = [
    data.aws_subnet.private_a.id,
    data.aws_subnet.private_b.id,
  ]
}

# Security Group usado pelas tasks Fargate (já existente)
data "aws_security_group" "ecs_tasks_sg" {
  id = "sg-0c6468f217e707e46"
}

# ECS Cluster existente
data "aws_ecs_cluster" "main" {
  cluster_name = "${var.project_name}-cluster" # lukras-platform-cluster
}

# Log group existente para ecs logs
data "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/${var.project_name}" # /ecs/lukras-platform
}

# EFS existente para logs persistentes dos bots
data "aws_efs_file_system" "bot_logs" {
  file_system_id = "fs-0d8e8c64186dbf47b" # lukras-platform-bot-logs
}

# IAM roles já existentes
data "aws_iam_role" "task_execution_role" {
  name = "${var.project_name}-exec-role"         # lukras-platform-exec-role
}

data "aws_iam_role" "task_role" {
  name = "${var.project_name}-task-role"         # lukras-platform-task-role
}

########################################
# ECS Task Definition (1 por user)
########################################
resource "aws_ecs_task_definition" "bot" {
  for_each = var.users

  family                   = "${var.project_name}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = data.aws_iam_role.task_execution_role.arn
  task_role_arn            = data.aws_iam_role.task_role.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  volume {
    name = "logs"
    efs_volume_configuration {
      file_system_id     = data.aws_efs_file_system.bot_logs.id
      transit_encryption = "ENABLED"
      root_directory     = "/"
    }
  }

  container_definitions = jsonencode([
    {
      name  = each.key
      image = var.container_image

      portMappings = [{
        containerPort = var.container_port
        hostPort      = var.container_port
      }]

      mountPoints = [{
        sourceVolume  = "logs"
        containerPath = "/app/logs"
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = data.aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = each.key
        }
      }

      # ENV simples por usuário (apenas as chaves presentes no tfvars)
      environment = [
        for k, v in var.users[each.key] : {
          name  = k
          value = v
        }
        if v != null && trim(v) != ""
      ]

      # Secrets no padrão "prod/lukras/<user>" — DEVEM existir já
      secrets = [
        for secret_name in [
          "LNM_KEY", "LNM_SECRET", "LNM_PASSPHRASE",
          "LNM_KEY1", "LNM_SECRET1", "LNM_PASSPHRASE1",
          "HL_PRIVATE_KEY"
        ] : {
          name      = secret_name
          valueFrom = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/lukras/${each.key}:${secret_name}::"
        }
      ]
    }
  ])

  lifecycle {
    create_before_destroy = true
  }
}

########################################
# ECS Service (1 por user, sem ALB)
########################################
resource "aws_ecs_service" "bot" {
  for_each       = var.users
  name           = "${var.project_name}-${each.key}"
  cluster        = data.aws_ecs_cluster.main.arn
  task_definition = aws_ecs_task_definition.bot[each.key].arn
  launch_type    = "FARGATE"
  desired_count  = 1

  network_configuration {
    subnets          = local.private_subnet_ids
    security_groups  = [data.aws_security_group.ecs_tasks_sg.id]
    assign_public_ip = false
  }

  # Permite que o deploy-bot force novos deployments sem drift chato
  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition
    ]
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
}

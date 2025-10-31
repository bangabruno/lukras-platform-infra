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

# users = { "n8w0lff" = { env = {...}, secrets = [...] } }
variable "users" {
  description = "Mapa de usuários com variáveis de ambiente e secrets."
  type = map(object({
    env     = map(string)
    secrets = list(string)
  }))
}

########################################
# Infra EXISTENTE (somente data sources)
# (IDs confirmados por você)
########################################

# VPC em uso (NÃO criar outra)
data "aws_vpc" "main" {
  id = "vpc-04bafb351cafaf66b"
}

# Subnets privadas em uso
data "aws_subnet" "private_a" { id = "subnet-06c53b145439031a3" } # 10.0.100.0/24 us-east-1a
data "aws_subnet" "private_b" { id = "subnet-062a2285292ed20da" } # 10.0.101.0/24 us-east-1b

# (Se um dia for usar ALB, já tem públicas:)
data "aws_subnet" "public_a"  { id = "subnet-0fba36c75cc949407" } # 10.0.0.0/24   us-east-1a
data "aws_subnet" "public_b"  { id = "subnet-0c646430a91b6d777" } # 10.0.1.0/24   us-east-1b

locals {
  private_subnet_ids = [
    data.aws_subnet.private_a.id,
    data.aws_subnet.private_b.id,
  ]

  public_subnet_ids = [
    data.aws_subnet.public_a.id,
    data.aws_subnet.public_b.id,
  ]
}

# Security Group usado pelas tasks Fargate (já existente)
data "aws_security_group" "ecs_tasks_sg" {
  id = "sg-0b2c40b72a6eebb5b"
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
  file_system_id = "fs-02397a9848be9686c" # lukras-platform-logs
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

      # ENV simples por usuário
      environment = concat(
        [
          {
            name  = "BOT_NAME"
            value = each.key
          }
        ],
        [
          for k, v in each.value.env : {
          name  = k
          value = v
        }
          if v != null && trimspace(v) != ""
        ]
      )

      # Secrets dinâmicos por usuário
      secrets = [
        for secret_name in each.value.secrets : {
          name      = secret_name
          valueFrom = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/lukras/${each.key}:${secret_name}::"
        }
      ]
    }
  ])

  lifecycle {
    create_before_destroy = true
    ignore_changes        = []
    replace_triggered_by  = [data.aws_iam_role.task_role.arn]
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
  enable_execute_command = true

  network_configuration {
    subnets          = local.public_subnet_ids
    security_groups  = [data.aws_security_group.ecs_tasks_sg.id]
    assign_public_ip = true
  }

  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition
    ]
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
}

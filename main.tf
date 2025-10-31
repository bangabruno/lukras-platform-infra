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
########################################

# VPC em uso
data "aws_vpc" "main" {
  id = "vpc-04bafb351cafaf66b"
}

# Subnets públicas (EM USO - bots com IP público via Internet Gateway)
data "aws_subnet" "public_a"  { id = "subnet-0fba36c75cc949407" } # 10.0.0.0/24   us-east-1a
data "aws_subnet" "public_b"  { id = "subnet-0c646430a91b6d777" } # 10.0.1.0/24   us-east-1b

locals {
  public_subnet_ids = [
    data.aws_subnet.public_a.id,
    data.aws_subnet.public_b.id,
  ]
}

# ECS Cluster existente
data "aws_ecs_cluster" "main" {
  cluster_name = "${var.project_name}-cluster"
}

# Log group existente
data "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/${var.project_name}"
}

# EFS existente
data "aws_efs_file_system" "bot_logs" {
  file_system_id = "fs-02397a9848be9686c"
}

# IAM roles existentes
data "aws_iam_role" "task_execution_role" {
  name = "${var.project_name}-exec-role"
}

data "aws_iam_role" "task_role" {
  name = "${var.project_name}-task-role"
}

########################################
# Security Group NOVO - Otimizado para bots
########################################
resource "aws_security_group" "bot_tasks" {
  name        = "${var.project_name}-bot-tasks-sg"
  description = "Security group para tasks ECS dos bots - SOMENTE EGRESS"
  vpc_id      = data.aws_vpc.main.id

  # EGRESS: Permitir HTTPS para APIs externas
  egress {
    description = "HTTPS para APIs externas"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }



  # EGRESS: Comunicação com EFS (NFS) na VPC
  egress {
    description = "NFS para EFS (logs persistentes)"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  # INGRESS: NENHUMA regra externa!
  # Bots NÃO recebem requisições da internet

  # INGRESS: Apenas comunicação interna na VPC (se necessário entre tasks)
  ingress {
    description = "Tráfego interno VPC (entre tasks, se necessário)"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  tags = {
    Name        = "${var.project_name}-bot-tasks-sg"
    Environment = "production"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
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
        protocol      = "tcp"
      }]

      mountPoints = [{
        sourceVolume  = "logs"
        containerPath = "/app/logs"
        readOnly      = false
      }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = data.aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = each.key
        }
      }

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
        } if v != null && trimspace(v) != ""
        ]
      )

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
  }
}

########################################
# ECS Service (1 por user) - Subnet PÚBLICA
########################################
resource "aws_ecs_service" "bot" {
  for_each = var.users

  name            = "${var.project_name}-${each.key}"
  cluster         = data.aws_ecs_cluster.main.arn
  task_definition = aws_ecs_task_definition.bot[each.key].arn
  launch_type     = "FARGATE"
  desired_count   = 1

  enable_execute_command = true

  network_configuration {
    subnets          = local.public_subnet_ids
    security_groups  = [aws_security_group.bot_tasks.id]  # SG NOVO otimizado
    assign_public_ip = true                                # IP público para acesso direto à internet
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [
      desired_count,
      task_definition
    ]
  }

  tags = {
    User        = each.key
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

########################################
# Outputs
########################################
output "security_group_id" {
  description = "ID do Security Group dos bots (sem ingress externo)"
  value       = aws_security_group.bot_tasks.id
}

output "bot_services" {
  description = "Serviços ECS criados"
  value = {
    for k, svc in aws_ecs_service.bot :
    k => {
      name    = svc.name
      cluster = svc.cluster
      status  = "Running em subnet PÚBLICA com IP público (via Internet Gateway)"
    }
  }
}
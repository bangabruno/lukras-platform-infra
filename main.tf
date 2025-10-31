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
# Variables
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
  description = "Map of users with environment variables and secrets"
  type = map(object({
    env     = map(string)
    secrets = list(string)
  }))
}

########################################
# Existing Infrastructure (data sources only)
########################################

# VPC in use - do not create another one
data "aws_vpc" "main" {
  id = "vpc-04bafb351cafaf66b"
}

# Public subnets - NOW IN USE for bots with public IP via Internet Gateway
data "aws_subnet" "public_a"  { id = "subnet-0fba36c75cc949407" } # 10.0.0.0/24   us-east-1a
data "aws_subnet" "public_b"  { id = "subnet-0c646430a91b6d777" } # 10.0.1.0/24   us-east-1b

locals {
  public_subnet_ids = [
    data.aws_subnet.public_a.id,
    data.aws_subnet.public_b.id,
  ]
}

# Existing ECS Cluster
data "aws_ecs_cluster" "main" {
  cluster_name = "${var.project_name}-cluster"
}

# Existing CloudWatch log group for ECS logs
data "aws_cloudwatch_log_group" "ecs" {
  name = "/ecs/${var.project_name}"
}

# Existing EFS for persistent bot logs
data "aws_efs_file_system" "bot_logs" {
  file_system_id = "fs-02397a9848be9686c"
}

# Existing IAM roles
data "aws_iam_role" "task_execution_role" {
  name = "${var.project_name}-exec-role"
}

data "aws_iam_role" "task_role" {
  name = "${var.project_name}-task-role"
}

########################################
# IAM Policy for EFS access
########################################

# Policy document for EFS access
data "aws_iam_policy_document" "efs_access" {
  statement {
    sid    = "AllowEFSAccess"
    effect = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
      "elasticfilesystem:DescribeFileSystems",
      "elasticfilesystem:DescribeMountTargets"
    ]
    resources = [
      data.aws_efs_file_system.bot_logs.arn
    ]
  }
}

# Create inline policy for EFS access
resource "aws_iam_role_policy" "task_role_efs" {
  name   = "${var.project_name}-task-efs-access"
  role   = data.aws_iam_role.task_role.name
  policy = data.aws_iam_policy_document.efs_access.json
}

# Policy for ECS Exec (enable_execute_command)
data "aws_iam_policy_document" "ecs_exec" {
  statement {
    sid    = "AllowECSExec"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }
}

# Create inline policy for ECS Exec
resource "aws_iam_role_policy" "task_role_ecs_exec" {
  name   = "${var.project_name}-task-ecs-exec"
  role   = data.aws_iam_role.task_role.name
  policy = data.aws_iam_policy_document.ecs_exec.json
}

########################################
# NEW Security Group - Optimized for bots
########################################
resource "aws_security_group" "bot_tasks" {
  name        = "${var.project_name}-bot-tasks-sg"
  description = "Security group for ECS bot tasks - EGRESS ONLY"
  vpc_id      = data.aws_vpc.main.id

  # EGRESS: Allow HTTPS for external APIs
  egress {
    description = "HTTPS for external APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # EGRESS: Communication with EFS NFS within VPC
  egress {
    description = "NFS for EFS - persistent logs"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main.cidr_block]
  }

  # INGRESS: NO external rules!
  # Bots do NOT receive requests from the internet

  # INGRESS: Only internal VPC communication if needed between tasks
  ingress {
    description = "Internal VPC traffic between tasks"
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
}

########################################
# ECS Task Definition (1 per user)
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
# ECS Service (1 per user) - PUBLIC subnet
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
    security_groups  = [aws_security_group.bot_tasks.id]  # NEW optimized SG
    assign_public_ip = true                                # Public IP for direct internet access
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
  description = "ID of the bot Security Group - no external ingress"
  value       = aws_security_group.bot_tasks.id
}

output "bot_services" {
  description = "ECS services created"
  value = {
    for k, svc in aws_ecs_service.bot :
    k => {
      name    = svc.name
      cluster = svc.cluster
      status  = "Running in PUBLIC subnet with public IP via Internet Gateway"
    }
  }
}
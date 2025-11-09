terraform {
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

data "aws_vpc" "main" {
  id = "vpc-04bafb351cafaf66b"
}

########################################
# SECURITY GROUPS
########################################
resource "aws_security_group" "alb_admin" {
  name        = "${var.project_name}-admin-alb-sg"
  description = "ALB for admin API"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = length(var.admin_acm_certificate_arn) > 0 ? [1] : []
    content {
      description = "HTTPS access"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "admin_tasks" {
  name        = "${var.project_name}-admin-tasks-sg"
  description = "Admin ECS tasks"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "Allow ALB to reach ECS tasks"
    from_port       = var.admin_container_port
    to_port         = var.admin_container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_admin.id]
  }

  egress {
    description = "Allow HTTPS outbound"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow NFS access to EFS"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
}

########################################
# IAM permissions (generic DynamoDB access)
########################################
data "aws_iam_policy_document" "dynamo_generic_access" {
  statement {
    sid     = "AllowAdminAndBotsAccessToDynamoDB"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:CreateTable"
    ]
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/*",
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/*/index/*"
    ]
  }
}

resource "aws_iam_role_policy" "shared_dynamo_access" {
  name   = "${var.project_name}-shared-dynamo-access"
  role   = var.task_role_name
  policy = data.aws_iam_policy_document.dynamo_generic_access.json
}

########################################
# ECS Task Definition + Service (Fargate Spot)
########################################
resource "aws_ecs_task_definition" "admin" {
  family                   = "${var.project_name}-admin"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.admin_cpu)
  memory                   = tostring(var.admin_memory)
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  volume {
    name = "logs"
    efs_volume_configuration {
      file_system_id     = var.efs_id
      transit_encryption = "ENABLED"
      root_directory     = "/"
    }
  }

  container_definitions = jsonencode([
    {
      name  = "admin"
      image = var.admin_container_image
      portMappings = [{
        containerPort = var.admin_container_port
        hostPort      = var.admin_container_port
        protocol      = "tcp"
      }]
      mountPoints = [{
        sourceVolume  = "logs"
        containerPath = "/app/logs"
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "admin"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:${var.admin_container_port}/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])
}

resource "aws_ecs_service" "admin" {
  name                   = "${var.project_name}-admin"
  cluster                = var.cluster_arn
  task_definition        = aws_ecs_task_definition.admin.arn
  desired_count          = var.admin_desired_count
  enable_execute_command = true

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [aws_security_group.admin_tasks.id]
    assign_public_ip = true
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [aws_iam_role_policy.shared_dynamo_access]
}

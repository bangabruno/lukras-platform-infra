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

########################################
# Security Group - admin API
########################################
resource "aws_security_group" "admin_sg" {
  name        = "${var.project_name}-admin-sg"
  description = "Security group for lukras-platform-admin API"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description = "Allow HTTP access for frontend"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # CRÍTICO: Permitir acesso ao DynamoDB (via HTTPS)
  egress {
    description = "Allow HTTPS outbound (DynamoDB, Secrets Manager, etc)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Permitir DNS resolution
  egress {
    description = "Allow DNS"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-admin-sg"
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

########################################
# ECS Task Definition (lukras-platform-admin)
########################################
resource "aws_ecs_task_definition" "admin" {
  family                   = "${var.project_name}-admin"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = var.task_execution_role
  task_role_arn            = var.task_role_arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name  = "lukras-platform-admin"
      image = var.container_image
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 8080
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "admin"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/actuator/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 120  # Aumentado para 120s para dar tempo das migrations
      }
      environment = [
        {
          name  = "SPRING_PROFILES_ACTIVE"
          value = "prod"
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "JAVA_TOOL_OPTIONS"
          value = "-XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"
        }
      ]
    }
  ])
}

########################################
# ECS Service - admin (2 tasks, Spot)
########################################
resource "aws_ecs_service" "admin" {
  name            = "${var.project_name}-admin"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.admin.arn
  desired_count   = 2
  enable_execute_command = true

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  network_configuration {
    subnets          = var.public_subnet_ids
    assign_public_ip = true
    security_groups  = [aws_security_group.admin_sg.id]
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    Service     = "lukras-platform-admin"
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}

########################################
# CloudWatch alarm (reuse same SNS topic)
########################################
resource "aws_cloudwatch_metric_alarm" "admin_task_health" {
  alarm_name          = "ecs-admin-task-health"
  alarm_description   = "Triggered if lukras-platform-admin has 0 running tasks"
  namespace           = "AWS/ECS"
  metric_name         = "RunningTaskCount"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"

  dimensions = {
    ClusterName = replace(var.ecs_cluster_arn, "arn:aws:ecs:${var.aws_region}::cluster/", "")
    ServiceName = aws_ecs_service.admin.name
  }

  alarm_actions      = [data.aws_sns_topic.existing_sns.arn]
  treat_missing_data = "notBreaching"
}

########################################
# Data Sources
########################################
data "aws_vpc" "main" {
  id = "vpc-04bafb351cafaf66b"
}

data "aws_sns_topic" "existing_sns" {
  name = "ecs-task-failure-topic"
}

data "aws_caller_identity" "current" {}
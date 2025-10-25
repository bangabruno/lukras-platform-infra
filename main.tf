
########################################
# VPC, Subnets, Routes, SGs
########################################
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "public" {
  for_each = {
    "us-east-1a" = "10.0.0.0/24"
    "us-east-1b" = "10.0.1.0/24"
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${each.key}"
  }
}

resource "aws_subnet" "private" {
  for_each = {
    "us-east-1a" = "10.0.100.0/24"
    "us-east-1b" = "10.0.101.0/24"
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-${each.key}"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat_eip" {
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = values(aws_subnet.public)[0].id
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_route_table_association" "private_assoc" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

########################################
# Security Groups
########################################
resource "aws_security_group" "ecs_sg" {
  name        = "${var.project_name}-ecs"
  vpc_id      = aws_vpc.main.id
  description = "Allow outbound only"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "efs_sg" {
  name        = "${var.project_name}-efs"
  vpc_id      = aws_vpc.main.id
  description = "Allow NFS only from ECS tasks"

  ingress {
    description     = "Allow NFS"
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
}

########################################
# Logs
########################################
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 30
}

########################################
# EFS
########################################
resource "aws_efs_file_system" "bot_logs" {
  encrypted = true

  tags = {
    Name = "${var.project_name}-logs"
  }
}

resource "aws_efs_mount_target" "bot_logs_mt" {
  for_each = aws_subnet.private

  file_system_id  = aws_efs_file_system.bot_logs.id
  subnet_id       = each.value.id
  security_groups = [aws_security_group.efs_sg.id]
}

########################################
# ECS Cluster
########################################
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

resource "aws_iam_role" "task_execution_role" {
  name = "${var.project_name}-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "exec_policy" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

########################################
# ECS Services and Task Definitions (1 por user)
########################################
resource "aws_ecs_task_definition" "bot" {
  for_each = var.users

  family                   = "${var.project_name}-${each.key}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.task_execution_role.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  volume {
    name = "logs"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.bot_logs.id
      transit_encryption = "ENABLED"
      root_directory     = "/"
    }
  }

  container_definitions = jsonencode([{
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
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = each.key
      }
    }

    # ENV simples (somente se definidos no tfvars)
    environment = [
      for k, v in var.users[each.key] : {
        name  = k
        value = tostring(v)
      }
    ]

    # Secrets referenciadas direto pelo ARN, devem existir manualmente!
    secrets = [
      for k in [
        "LNM_KEY", "LNM_SECRET", "LNM_PASSPHRASE",
        "LNM_KEY1", "LNM_SECRET1", "LNM_PASSPHRASE1",
        "HL_PRIVATE_KEY"
      ] : {
        name      = k
        valueFrom = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:prod/lukras/${each.key}:${k}::"
      }
    ]
  }])
}

data "aws_caller_identity" "current" {}

resource "aws_ecs_service" "bot" {
  for_each       = var.users
  name           = "${var.project_name}-${each.key}"
  cluster        = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.bot[each.key].arn
  launch_type    = "FARGATE"
  desired_count  = 1

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }
}

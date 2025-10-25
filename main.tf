# -----------------------------
# AZ / locals
# -----------------------------
data "aws_availability_zones" "available" {}

locals {
  name_prefix = var.project_name
  azs         = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Facilita usar "for_each" com objetos enriquecidos por usuário
  users = toset(var.users)
}

# -----------------------------
# VPC
# -----------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  for_each = {
    "${var.aws_region}a" = "10.0.0.0/24"
    "${var.aws_region}b" = "10.0.1.0/24"
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = { Name = "${local.name_prefix}-public-${each.key}" }
}

resource "aws_subnet" "private" {
  for_each = {
    "${var.aws_region}a" = "10.0.100.0/24"
    "${var.aws_region}b" = "10.0.101.0/24"
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-private-${each.key}" }
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

  tags = { Name = "${local.name_prefix}-nat" }
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

# -----------------------------
# Security Groups
# -----------------------------
resource "aws_security_group" "alb_sg" {
  name        = "${local.name_prefix}-alb-sg"
  vpc_id      = aws_vpc.main.id
  description = "ALB security group - allows HTTP(S)"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-alb-sg" }
}

# SG das ECS tasks (definido ANTES do EFS SG p/ evitar ciclos)
resource "aws_security_group" "ecs_tasks" {
  name        = "${local.name_prefix}-ecs-tasks"
  vpc_id      = aws_vpc.main.id
  description = "ECS tasks outbound & intra-cluster"

  # Tráfego interno entre tasks, caso necessário
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  # Saída liberada (internet via NAT)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-ecs-tasks" }
}

# SG do EFS: permite NFS (2049) APENAS a partir das ECS tasks
resource "aws_security_group" "efs_sg" {
  name        = "${local.name_prefix}-efs-sg"
  description = "Allow NFS from ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "NFS from ECS tasks"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-efs-sg" }
}

# -----------------------------
# Logs
# -----------------------------
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = 30
}

# -----------------------------
# EFS: File System + Mount Targets + Access Points (por usuário)
# -----------------------------
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

# Access Point por usuário (raiz isolada /bots/<usuario>)
resource "aws_efs_access_point" "bot_ap" {
  for_each       = local.users
  file_system_id = aws_efs_file_system.bot_logs.id

  posix_user {
    gid = 1000
    uid = 1000
  }

  root_directory {
    path = "/bots/${each.key}"

    creation_info {
      owner_gid   = 1000
      owner_uid   = 1000
      permissions = "0755"
    }
  }

  tags = { Name = "${local.name_prefix}-ap-${each.key}" }
}

# -----------------------------
# IAM (roles de execução)
# -----------------------------
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

resource "aws_iam_role_policy_attachment" "exec_role_policy" {
  role       = aws_iam_role.task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task_role" {
  name               = "${local.name_prefix}-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume.json
}

# -----------------------------
# ECS Cluster
# -----------------------------
resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-cluster"
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

# -----------------------------
# (Opcional) ALB
# -----------------------------
resource "aws_lb" "alb" {
  count              = var.enable_alb ? 1 : 0
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for s in aws_subnet.public : s.id]
}

resource "aws_lb_target_group" "tg" {
  for_each = var.enable_alb ? { for u in var.users : u => u } : {}

  name     = "${local.name_prefix}-${each.key}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/actuator/health"
    protocol            = "HTTP"
    matcher             = "200-399"
    interval            = 30
    unhealthy_threshold = 2
    healthy_threshold   = 2
  }
}

resource "aws_lb_listener" "http" {
  count             = var.enable_alb ? 1 : 0
  load_balancer_arn = aws_lb.alb[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "bot_rules" {
  for_each = var.enable_alb ? { for idx, u in var.users : u => idx } : {}

  listener_arn = aws_lb_listener.http[0].arn
  priority     = 100 + each.value

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg[each.key].arn
  }

  condition {
    path_pattern {
      values = ["/${each.key}/*", "/${each.key}"]
    }
  }
}

# -----------------------------
# Secrets por usuário
# -----------------------------
# Nome do Secret por usuário
locals {
  user_secret_names = { for u in var.users : u => "prod/lukras/${u}" }
}

data "aws_secretsmanager_secret" "by_user" {
  for_each = local.user_secret_names
  name     = each.value
}

# -----------------------------
# Task Definitions (1 por usuário) + Service (1 por usuário)
# -----------------------------
resource "aws_ecs_task_definition" "bot_task" {
  for_each = local.users

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

  # Volume EFS via Access Point do usuário
  volume {
    name = "bot-logs"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.bot_logs.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.bot_ap[each.key].id
        iam             = "ENABLED"
      }
      # raiz do AP = /bots/<usuario>
      root_directory = "/"
    }
  }

  container_definitions = jsonencode([{
    name  = each.key
    image = var.container_image

    portMappings = [{
      containerPort = var.container_port
      hostPort      = var.container_port
      protocol      = "tcp"
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

    # Injeta todas as chaves de var.secret_keys a partir do Secret JSON de cada usuário
    secrets = [
      for k in var.secret_keys : {
        name      = k
        valueFrom = "${data.aws_secretsmanager_secret.by_user[each.key].arn}:${k}::"
      }
    ]
  }])
}

resource "aws_ecs_service" "bot_service" {
  for_each = local.users

  name            = "${var.project_name}-${each.key}"
  cluster         = aws_ecs_cluster.this.id
  launch_type     = "FARGATE"
  desired_count   = 1
  task_definition = aws_ecs_task_definition.bot_task[each.key].arn

  network_configuration {
    subnets          = [for s in aws_subnet.private : s.id]
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_tasks.id]
  }

  dynamic "load_balancer" {
    for_each = var.enable_alb ? [1] : []
    content {
      target_group_arn = aws_lb_target_group.tg[each.key].arn
      container_name   = each.key
      container_port   = var.container_port
    }
  }

  depends_on = var.enable_alb ? [aws_lb_listener.http] : []
}

# -----------------------------
# Outputs úteis
# -----------------------------
output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "services" {
  value = { for u in local.users : u => aws_ecs_service.bot_service[u].name }
}

output "efs_id" {
  value = aws_efs_file_system.bot_logs.id
}

output "log_group" {
  value = aws_cloudwatch_log_group.ecs.name
}

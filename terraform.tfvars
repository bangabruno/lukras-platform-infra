aws_region    = "us-east-1"
project_name  = "lukras-platform"
enable_alb    = false

# Usuários/bots ativos
users = [
  "n8w0lff"
]

# Imagem ARM64 (Fargate)
container_image = "659528245383.dkr.ecr.us-east-1.amazonaws.com/trader-bot:latest"

# Recursos por bot
cpu            = 256
memory         = 512
container_port = 8080

# Opcional
az_count = 2

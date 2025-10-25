aws_region    = "us-east-1"
project_name  = "lukras-platform"
enable_alb    = false

users = [
  "n8w0lff"
]

container_image = "659528245383.dkr.ecr.us-east-1.amazonaws.com/trader-bot:latest"

cpu            = 256
memory         = 512
container_port = 8080

az_count = 2

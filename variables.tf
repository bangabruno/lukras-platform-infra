variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Nome base do projeto (prefixos de recursos)"
  type        = string
}

variable "users" {
  description = "Lista de usuários/bots (ex.: [\"n8w0lff\", \"satoshi\"])"
  type        = list(string)
}

variable "container_image" {
  description = "Imagem ARM64 no ECR (ex.: 123456789012.dkr.ecr.us-east-1.amazonaws.com/trader-bot:latest)"
  type        = string
}

variable "cpu" {
  description = "CPU da task Fargate (ex.: 256)"
  type        = number
}

variable "memory" {
  description = "Memória da task Fargate (ex.: 512)"
  type        = number
}

variable "container_port" {
  description = "Porta do container (ex.: 8080)"
  type        = number
}

# opcional: quantas AZs quer usar
variable "az_count" {
  description = "Quantidade de AZs"
  type        = number
  default     = 2
}

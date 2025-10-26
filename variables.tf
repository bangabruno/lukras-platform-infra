variable "aws_region" {
  description = "AWS region (ex: us-east-1)"
  type        = string
}

variable "project_name" {
  description = "Prefixo do projeto (ex: lukras-platform)"
  type        = string
}

variable "enable_alb" {
  description = "Habilitar ALB (não usado nos bots sem endpoint)"
  type        = bool
}

variable "container_image" {
  description = "Imagem ECR (ex: 123456789012.dkr.ecr.us-east-1.amazonaws.com/trader-bot:latest)"
  type        = string
}

variable "cpu" {
  description = "CPU para cada bot"
  type        = number
}

variable "memory" {
  description = "Memória (MB) para cada bot"
  type        = number
}

variable "container_port" {
  description = "Porta do container"
  type        = number
}

variable "users" {
  description = "Mapa de usuários => variáveis simples (NÃO-secretas). Todos os nomes **exatos** conforme sua app."
  type        = map(map(string))
}

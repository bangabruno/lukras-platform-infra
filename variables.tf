variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "project_name" {
  description = "Prefixo do projeto (ex: lukras-platform)"
  type        = string
}

variable "az_count" {
  description = "Quantidade de AZs a usar"
  type        = number
  default     = 2
}

variable "enable_alb" {
  description = "Habilitar ALB para expor bots por path"
  type        = bool
  default     = false
}

variable "users" {
  description = "Lista de usuários (um bot por usuário)"
  type        = list(string)
}

variable "container_image" {
  description = "Imagem do container (mesma para todos os bots). Ex.: 6595....dkr.ecr.us-east-1.amazonaws.com/trader-bot:latest"
  type        = string
}

variable "container_port" {
  description = "Porta exposta pela aplicação no container"
  type        = number
  default     = 8080
}

variable "cpu" {
  description = "CPU da task (Fargate). Ex.: 256, 512, etc."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Memória da task (MB). Ex.: 512, 1024"
  type        = number
  default     = 512
}

variable "secret_keys" {
  description = "Chaves que serão extraídas do Secret JSON e injetadas como env vars"
  type        = list(string)
  default = [
    "LNM_KEY",
    "LNM_SECRET",
    "LNM_PASSPHRASE",
    "LNM_KEY1",
    "LNM_PASSPHRASE1",
    "LNM_SECRET1",
    "HL_PRIVATE_KEY"
  ]
}

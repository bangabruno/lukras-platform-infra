variable "aws_region" {
  description = "AWS region (ex: us-east-1)"
  type        = string
}

variable "project_name" {
  description = "Prefixo do projeto (ex: lukras-platform)"
  type        = string
}

variable "container_image" {
  description = "Imagem do container (ECR) usada por todos os bots (ex: 123456789012.dkr.ecr.us-east-1.amazonaws.com/trader-bot:latest)"
  type        = string
}

variable "cpu" {
  description = "CPU Fargate por task (ex: 256)"
  type        = number
}

variable "memory" {
  description = "Memória Fargate por task (ex: 512)"
  type        = number
}

variable "container_port" {
  description = "Porta exposta pelo container"
  type        = number
}

# Mapa de usuários -> mapa de variáveis simples (strings).
# Valores podem ser nulos; o main filtra e só injeta as que tiverem valor.
variable "users" {
  description = <<EOT
Mapa de usuários. Cada chave é o user (ex: n8w0lff, satoshi).
Cada valor é um map de variáveis de ambiente **simples** (não-secrets), todas como strings (ou null):

Exemplo:
users = {
  n8w0lff = {
    USER_WALLET                            = "0x..."
    LNM_ENABLED                            = "true"
    LNM_LEVERAGE                           = "10"
    LNM_GET_PRICE_EVERY_SECS               = "3"
    LNM_ORDER_MARGIN_ENTRY_SATS            = "5000"
    LNM_ORDER_MARGIN_ADD_PERCENT           = "0.2"
    LNM_ORDER_MARGIN_CHECK_PERCENT         = "0.03"
    LNM_ORDER_PRICE_VARIATION_USD          = "100"
    LNM_ORDER_TAKE_PROFIT_PERCENT          = "0.006"
    LNM_ORDER_TOTAL_LIMIT                  = "100"
    LNM_ORDER_MARGIN_ENTRY_DYNAMIC_ENABLED = "true"
    LNM_ORDER_PRICE_LIMIT                  = "180000"
    LNM_MULTI_ACCOUNT_ENABLED              = "true"
    HL_ENABLED                             = "true"
    HL_LEVERAGE                            = "10"
    HL_GET_PRICE_EVERY_SECS                = "3"
    HL_ORDER_MARGIN_ENTRY_USD              = "20"
    HL_ORDER_PRICE_VARIATION_USD           = "100"
    HL_ORDER_TAKE_PROFIT_PERCENT           = "0.006"
    HL_MAX_MARGIN_ALLOCATED_PERCENT        = "0.5"
  }
}
EOT
  type = map(map(any))
}

aws_region    = "us-east-1"
project_name  = "lukras-platform"
enable_alb    = false

# Imagem ARM64 (Fargate)
container_image = "659528245383.dkr.ecr.us-east-1.amazonaws.com/trader-bot:latest"

# Recursos por bot
cpu            = 256
memory         = 512
container_port = 8080

# Variáveis simples por usuário (NÃO-SECRETS)
users = {
  n8w0lff = {
    USER_WALLET                            = "0x7Be83Fbf23E4a0241BFD1b97F1863D44b661B056"
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
  # Exemplo de outro user:
  # satoshi = {
  #   USER_WALLET = "null"
  #   LNM_ENABLED = "true"
  #   ...
  # }
}

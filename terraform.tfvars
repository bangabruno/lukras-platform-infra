aws_region    = "us-east-1"
project_name  = "lukras-platform"
enable_alb    = false

# Imagem ARM64 (Fargate)
container_image = "659528245383.dkr.ecr.us-east-1.amazonaws.com/lukras-bot:latest"

# Recursos por bot
cpu            = 256
memory         = 512
container_port = 8080

# Secrets por usuário
users = {
  n8w0lff = {
    secrets = [
      "LNM_KEY",
      "LNM_SECRET",
      "LNM_PASSPHRASE",
      "LNM_KEY1",
      "LNM_SECRET1",
      "LNM_PASSPHRASE1",
      "HL_PRIVATE_KEY",
      "USER_WALLET"
    ]
  }
  hpk1991 = {
    secrets = [
      "LNM_KEY",
      "LNM_SECRET",
      "LNM_PASSPHRASE",
      "HL_PRIVATE_KEY",
      "USER_WALLET"
    ]
  }
  pedro_travassos = {
    secrets = [
      "HL_PRIVATE_KEY",
      "USER_WALLET"
    ]
  }

  # Exemplo de user com apenas 1 conta LNM:
  # satoshi = {
  #   env = {
  #     USER_WALLET = "0x..."
  #     LNM_ENABLED = "true"
  #   }
  #   secrets = [
  #     "LNM_KEY",
  #     "LNM_SECRET",
  #     "LNM_PASSPHRASE",
  #     "HL_PRIVATE_KEY"
  #   ]
  # }
}
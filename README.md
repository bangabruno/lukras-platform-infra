# Lukras Platform - Infra (Terraform)

Infraestrutura do ECS Fargate multi-bot (um Service por usuário), com:
- VPC, Subnets privadas, NAT, IGW
- EFS (logs persistentes), Access Point por usuário
- CloudWatch Logs
- (Opcional) ALB com regras por path `/usuario`
- Secrets do Secrets Manager em `prod/lukras/<usuario>`

## Pré-requisitos

- Terraform >= 1.5
- AWS CLI configurado
- IAM user/role com permissões para criar ECS, EFS, EC2 (VPC), CloudWatch Logs, IAM (roles para tasks)

## Como usar

1. Ajuste `terraform.tfvars` (usuários, imagem, região, etc).
2. `terraform init`
3. `terraform plan`
4. `terraform apply`

## Secrets esperados

Para cada `usuario` em `var.users`, crie um Secret **do tipo JSON** em:

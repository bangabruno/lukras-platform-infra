# Lukras Platform - Infra (Terraform)

Infraestrutura do ECS Fargate multi-bot (um Service por usuário), com:
- VPC, Subnets privadas, NAT, IGW
- EFS (logs persistentes), Access Point por usuário
- CloudWatch Logs
- (Opcional) ALB com regras por path `/usuario`
- Secrets do Secrets Manager em `prod/lukras/<usuario>`

# Lukras Platform

## 🏗️ Arquitetura
```mermaid
graph TB
    subgraph GitHub["☁️ GitHub Actions CI/CD"]
        GH_INFRA["📋 Workflow: Infra Apply<br/>(Terraform)"]
        GH_DEPLOY["🚀 Workflow: Deploy Bot<br/>(Update Image)"]
        GH_REPO["📦 Repository<br/>terraform.tfvars + main.tf"]
    end

    subgraph AWS["☁️ AWS Account - us-east-1"]
        direction TB
        
        ECR["📦 ECR<br/>trader-bot:latest<br/>(ARM64)"]
        
        EXEC_ROLE["🔐 IAM Execution Role<br/>lukras-platform-exec-role"]
        TASK_ROLE["🔐 IAM Task Role<br/>lukras-platform-task-role"]
        
        SM_USER1["🔑 Secrets Manager<br/>prod/lukras/n8w0lff<br/>LNM_KEY, HL_PRIVATE_KEY, etc"]
        
        CW_LOGS["📊 CloudWatch Logs<br/>/ecs/lukras-platform"]
        
        EFS["💾 EFS: fs-02397a9848be9686c<br/>📁 /logs/n8w0lff/app.log<br/>📁 /logs/n8w0lff/20251026.log"]
    end
    
    subgraph VPC["🌐 VPC: vpc-04bafb351cafaf66b (10.0.0.0/16)"]
        direction TB
        
        NAT["🔄 NAT Gateway"]
        
        subgraph PrivateSubnets["Private Subnets"]
            PRIV_A["10.0.100.0/24<br/>us-east-1a"]
            PRIV_B["10.0.101.0/24<br/>us-east-1b"]
        end
        
        subgraph ECS["⚙️ ECS Cluster: lukras-platform-cluster"]
            TASK1["🤖 Fargate Task: n8w0lff<br/>CPU: 256 | Memory: 512<br/>ENV: BOT_NAME=n8w0lff<br/>Mount: /app/logs → EFS"]
            TASK2["🤖 Fargate Task: user2<br/>(Future users)"]
        end
        
        SG["🛡️ Security Group<br/>lukras-platform-ecs<br/>(Outbound only)"]
    end
    
    subgraph External["🌍 External APIs"]
        LNM["💱 LNMarkets<br/>WebSocket + REST"]
        HL["💱 Hyperliquid<br/>WebSocket + REST"]
    end
    
    subgraph Container["📦 Container Runtime"]
        APP["☕ Spring Boot App<br/>trader-bot<br/><br/>Logback:<br/>→ Console (CloudWatch)<br/>→ Files (EFS)"]
    end

    GH_REPO --> GH_INFRA
    GH_REPO --> GH_DEPLOY
    GH_INFRA -->|"Create/Update Infrastructure"| EXEC_ROLE
    GH_DEPLOY -->|"Update Task Definition"| ECR

    EXEC_ROLE -->|"Pull Image"| ECR
    EXEC_ROLE -->|"Read Secrets"| SM_USER1
    TASK_ROLE -->|"Container Permissions"| APP

    ECR -->|"Deploy Container"| TASK1
    SM_USER1 -->|"Inject ENV Variables"| TASK1
    
    TASK1 -->|"Write Logs"| EFS
    TASK1 -->|"stdout/stderr"| CW_LOGS
    
    TASK1 -.->|"Runs in"| PRIV_A
    TASK2 -.->|"Runs in"| PRIV_B
    SG -.->|"Applied to"| TASK1
    SG -.->|"Applied to"| TASK2
    
    PRIV_A --> NAT
    PRIV_B --> NAT
    NAT -->|"Internet Access"| LNM
    NAT -->|"Internet Access"| HL

    APP -.->|"Runs inside"| TASK1
    APP <-->|"Trading Operations<br/>Market Data"| LNM
    APP <-->|"Trading Operations<br/>Market Data"| HL

    classDef github fill:#24292e,stroke:#fff,stroke-width:2px,color:#fff
    classDef aws fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:#000
    classDef ecs fill:#FF6B35,stroke:#D86613,stroke-width:3px,color:#fff
    classDef security fill:#DD344C,stroke:#870000,stroke-width:2px,color:#fff
    classDef storage fill:#3F8624,stroke:#1D4C0E,stroke-width:2px,color:#fff
    classDef external fill:#4285F4,stroke:#1a73e8,stroke-width:2px,color:#fff
    classDef network fill:#8C4FFF,stroke:#5000ca,stroke-width:2px,color:#fff
    classDef container fill:#00C853,stroke:#00872D,stroke-width:2px,color:#fff

    class GH_INFRA,GH_DEPLOY,GH_REPO github
    class ECR,EXEC_ROLE,TASK_ROLE,CW_LOGS aws
    class TASK1,TASK2,ECS ecs
    class SM_USER1,SG security
    class EFS storage
    class LNM,HL external
    class NAT,PRIV_A,PRIV_B,VPC network
    class APP,Container container
```

## 📋 Componentes

### CI/CD
- **GitHub Actions**: Automatiza deploy de infraestrutura (Terraform) e atualização de containers

### AWS Infrastructure
- **ECS Fargate**: Execução serverless de containers (ARM64)
- **ECR**: Registro privado de imagens Docker
- **EFS**: Armazenamento persistente para logs (rotação de 30 dias)
- **CloudWatch**: Monitoramento e logs em tempo real
- **Secrets Manager**: Gerenciamento seguro de credenciais por usuário

### Networking
- **VPC**: Isolamento de rede
- **Private Subnets**: Execução segura das tasks (sem IP público)
- **NAT Gateway**: Acesso controlado à internet
- **Security Groups**: Firewall com regras de saída apenas

### External Integrations
- **LNMarkets**: Trading de derivativos Bitcoin
- **Hyperliquid**: Trading DeFi perpétuo

## 🚀 Deploy

### Criar novo usuário
1. Adicionar usuário em `terraform.tfvars`
2. Criar secrets no AWS Secrets Manager: `prod/lukras/<user>`
3. Executar workflow "Infra Apply"

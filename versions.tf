terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.64"
    }
  }

  backend "s3" {
    bucket         = "lukras-platform-terraform-state"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "lukras-terraform-locks"
    encrypt        = true
  }
}
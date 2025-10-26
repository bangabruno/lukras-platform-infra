terraform {
  backend "s3" {
    bucket         = "lukras-platform-terraform-state"
    key            = "global/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "lukras-platform-terraform-lock"
    encrypt        = true
  }
}

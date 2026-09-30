terraform {
  required_version = ">= 1.14, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.38.0"
    }
  }
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = { Project = var.name, Environment = "lab", ManagedBy = "Terraform" }
  }
}

terraform {
  required_version = ">= 1.14, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.38.0"
    }
  }
}
variable "account_id" {
  type = string
  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "Indicar una cuenta de 12 digitos."
  }
}
variable "existing_oidc_provider_arn" {
  description = "ARN del proveedor GitHub existente; vacio para crear uno."
  type        = string
  default     = ""
}
provider "aws" {
  region              = "us-east-1"
  allowed_account_ids = [var.account_id]
  default_tags {
    tags = { Project = "proyecto-devops-cd", ManagedBy = "Terraform" }
  }
}
locals {
  bucket    = "proyecto-devops-state-${var.account_id}-us-east-1"
  state_key = "lab/terraform.tfstate"
  oidc_arn  = var.existing_oidc_provider_arn != "" ? var.existing_oidc_provider_arn : aws_iam_openid_connect_provider.github[0].arn
}
resource "aws_s3_bucket" "state" {
  bucket        = local.bucket
  force_destroy = false
  lifecycle { prevent_destroy = true }
}
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "tls" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.existing_oidc_provider_arn == "" ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_iam_role" "github" {
  name                 = "proyecto-devops-github-cd"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = local.oidc_arn }
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:Farid259@89980590/proyecto_devops@1394095415:environment:aws-lab"
      } }
    }]
  })
}
resource "aws_iam_role_policy" "lab" {
  name   = "lab-provision"
  role   = aws_iam_role.github.id
  policy = templatefile("${path.module}/../iam/lab-provision-policy.json.tftpl", { account_id = var.account_id })
}
resource "aws_iam_role_policy" "state" {
  name = "lab-state"
  role = aws_iam_role.github.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.state.arn },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = "${aws_s3_bucket.state.arn}/${local.state_key}" },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = "${aws_s3_bucket.state.arn}/${local.state_key}.tflock" }
    ]
  })
}
output "github_role_arn" { value = aws_iam_role.github.arn }
output "state_bucket" { value = aws_s3_bucket.state.id }
output "backend_config" {
  value = <<-EOT
bucket = "${aws_s3_bucket.state.id}"
key = "${local.state_key}"
region = "us-east-1"
encrypt = true
use_lockfile = true
EOT
}

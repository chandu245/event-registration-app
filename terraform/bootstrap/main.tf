# ---------------------------------------------------------------------------
# Bootstrap — run this ONCE before your first `terraform init` in ../
#
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#
# This creates the S3 bucket and DynamoDB table that store Terraform state.
# After apply, copy the printed bucket name into ../backend.tf.
# ---------------------------------------------------------------------------

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "aws_region" { default = "ap-southeast-1" }

provider "aws" { region = var.aws_region }

data "aws_caller_identity" "current" {}

locals {
  # Bucket name is unique per AWS account — no collision risk
  bucket_name = "tfstate-event-app-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "tfstate" {
  bucket        = local.bucket_name
  force_destroy = false   # protect state from accidental deletion

  tags = { Project = "event-registration-app", Purpose = "terraform-state" }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = { Project = "event-registration-app", Purpose = "terraform-state-lock" }
}

output "bucket_name" {
  value       = aws_s3_bucket.tfstate.bucket
  description = "Copy this value into terraform/backend.tf → bucket"
}

output "dynamodb_table" {
  value       = aws_dynamodb_table.tfstate_lock.name
  description = "DynamoDB table name for state locking"
}

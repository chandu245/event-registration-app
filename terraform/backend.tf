# ---------------------------------------------------------------------------
# Remote state backend — S3 + DynamoDB locking
#
# One-time setup before your first terraform init:
#   1. cd terraform/bootstrap && terraform init && terraform apply
#   2. Copy the printed bucket_name into the bucket field below
#   3. cd .. && terraform init   (migrates any local state to S3)
# ---------------------------------------------------------------------------

terraform {
  backend "s3" {
    bucket         = "tfstate-event-app-565968180632"
    key            = "event-registration-app/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

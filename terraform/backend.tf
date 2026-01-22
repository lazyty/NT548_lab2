# Terraform Backend Configuration
# S3 bucket for state storage with DynamoDB for state locking

terraform {
  backend "s3" {
    bucket         = "nt548-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "nt548-terraform-locks"
    
    # Optional: Enable versioning for state file history
    # versioning = true
  }
}

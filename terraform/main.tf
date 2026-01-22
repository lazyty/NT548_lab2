# Main Terraform configuration
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # Backend will be configured via backend-config during init
  # terraform init -backend-config="bucket=nt548-tfstate-<account-id>"
  backend "s3" {
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "nt548-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"
  
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidr   = var.public_subnet_cidr
  private_subnet_cidr  = var.private_subnet_cidr
  availability_zone    = var.availability_zone
  
  tags = var.common_tags
}

# Security Groups Module
module "security_groups" {
  source = "./modules/security-groups"
  
  vpc_id          = module.vpc.vpc_id
  allowed_ssh_ip  = var.allowed_ssh_ip
  
  tags = var.common_tags
}

# EC2 Module
module "ec2" {
  source = "./modules/ec2"
  
  public_subnet_id           = module.vpc.public_subnet_id
  private_subnet_id          = module.vpc.private_subnet_id
  public_security_group_id   = module.security_groups.public_sg_id
  private_security_group_id  = module.security_groups.private_sg_id
  key_pair_name             = var.key_pair_name
  
  tags = var.common_tags
}
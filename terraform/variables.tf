# Variables for Terraform configuration

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "Availability zone for subnets"
  type        = string
  default     = "us-east-1a"
}

variable "allowed_ssh_ip" {
  description = "IP address allowed to SSH to public EC2"
  type        = string
  default     = "0.0.0.0/0"  # Change this to your IP for security
}

variable "key_pair_name" {
  description = "Name of AWS key pair for EC2 instances"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "NT548-BaiTapThucHanh-01"
    Environment = "dev"
    Owner       = "student"
  }
}
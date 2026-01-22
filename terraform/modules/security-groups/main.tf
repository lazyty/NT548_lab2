# Security Groups Module

# Public EC2 Security Group
resource "aws_security_group" "public_ec2" {
  name_prefix = "nt548-public-ec2-"
  vpc_id      = var.vpc_id
  description = "Security group for public EC2 instance"

  # SSH access from specified IP only
  ingress {
    description = "SSH from allowed IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_ip]
  }

  # HTTP access (optional, for web servers)
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access (optional, for web servers)
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "NT548-Public-EC2-SG"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Private EC2 Security Group
resource "aws_security_group" "private_ec2" {
  name_prefix = "nt548-private-ec2-"
  vpc_id      = var.vpc_id
  description = "Security group for private EC2 instance"

  # SSH access from public EC2 only
  ingress {
    description     = "SSH from public EC2"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.public_ec2.id]
  }

  # HTTP access from public EC2 (for internal services)
  ingress {
    description     = "HTTP from public EC2"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.public_ec2.id]
  }

  # HTTPS access from public EC2 (for internal services)
  ingress {
    description     = "HTTPS from public EC2"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.public_ec2.id]
  }

  # Custom application port (example: 8080)
  ingress {
    description     = "Custom app port from public EC2"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.public_ec2.id]
  }

  # All outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "NT548-Private-EC2-SG"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Default Security Group for VPC
# This restricts the default SG to prevent accidental use
resource "aws_default_security_group" "default" {
  vpc_id = var.vpc_id

  # Deny all inbound traffic by default
  # (no ingress rules = no inbound traffic)

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "NT548-Default-SG"
  })
}
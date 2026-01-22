#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Setup S3 backend for Terraform state management
.DESCRIPTION
    Creates S3 bucket and DynamoDB table for Terraform remote state
#>

param(
    [string]$BucketName = "nt548-terraform-state",
    [string]$DynamoDBTable = "nt548-terraform-locks",
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up Terraform Backend ===" -ForegroundColor Cyan
Write-Host "Bucket: $BucketName" -ForegroundColor Yellow
Write-Host "DynamoDB: $DynamoDBTable" -ForegroundColor Yellow
Write-Host "Region: $Region" -ForegroundColor Yellow
Write-Host ""

# Check if bucket exists
Write-Host "Checking if S3 bucket exists..." -ForegroundColor Cyan
$bucketExists = aws s3api head-bucket --bucket $BucketName 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "S3 bucket already exists: $BucketName" -ForegroundColor Green
} else {
    Write-Host "Creating S3 bucket..." -ForegroundColor Yellow
    aws s3api create-bucket --bucket $BucketName --region $Region
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create S3 bucket" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Enabling versioning..." -ForegroundColor Yellow
    aws s3api put-bucket-versioning --bucket $BucketName --versioning-configuration Status=Enabled
    
    Write-Host "Enabling encryption..." -ForegroundColor Yellow
    aws s3api put-bucket-encryption --bucket $BucketName --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'
    
    Write-Host "Blocking public access..." -ForegroundColor Yellow
    aws s3api put-public-access-block --bucket $BucketName --public-access-block-configuration '{
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }'
    
    Write-Host "S3 bucket created successfully!" -ForegroundColor Green
}

# Check if DynamoDB table exists
Write-Host ""
Write-Host "Checking if DynamoDB table exists..." -ForegroundColor Cyan
$tableExists = aws dynamodb describe-table --table-name $DynamoDBTable --region $Region 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "DynamoDB table already exists: $DynamoDBTable" -ForegroundColor Green
} else {
    Write-Host "Creating DynamoDB table..." -ForegroundColor Yellow
    aws dynamodb create-table `
        --table-name $DynamoDBTable `
        --attribute-definitions AttributeName=LockID,AttributeType=S `
        --key-schema AttributeName=LockID,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST `
        --region $Region
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create DynamoDB table" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Waiting for table to be active..." -ForegroundColor Yellow
    aws dynamodb wait table-exists --table-name $DynamoDBTable --region $Region
    
    Write-Host "DynamoDB table created successfully!" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Backend Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Backend configuration is already in terraform/main.tf" -ForegroundColor White
Write-Host "2. Run: cd terraform" -ForegroundColor White
Write-Host "3. Run: terraform init -reconfigure" -ForegroundColor White
Write-Host "4. Your state will be migrated to S3" -ForegroundColor White

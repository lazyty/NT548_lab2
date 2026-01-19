# PowerShell script for Terraform deployment on Windows
# NT548 Infrastructure Deployment

param(
    [switch]$SkipConfirmation
)

# Colors for output
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Cyan"

Write-Host "=== NT548 Terraform Deployment Script ===" -ForegroundColor $Blue
Write-Host ""

# Check prerequisites
function Test-Prerequisites {
    Write-Host "Checking prerequisites..." -ForegroundColor $Yellow
    
    # Check Terraform
    try {
        $null = Get-Command terraform -ErrorAction Stop
        Write-Host "Terraform found" -ForegroundColor $Green
    }
    catch {
        Write-Host "Terraform not found" -ForegroundColor $Red
        Write-Host "Please install Terraform from: https://www.terraform.io/downloads.html" -ForegroundColor $Red
        exit 1
    }
    
    # Check AWS CLI
    try {
        $null = Get-Command aws -ErrorAction Stop
        Write-Host "AWS CLI found" -ForegroundColor $Green
    }
    catch {
        Write-Host "AWS CLI not found" -ForegroundColor $Red
        Write-Host "Please install AWS CLI from: https://aws.amazon.com/cli/" -ForegroundColor $Red
        exit 1
    }
    
    # Check AWS credentials
    try {
        $null = aws sts get-caller-identity 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "AWS credentials configured" -ForegroundColor $Green
        } else {
            throw "AWS credentials not configured"
        }
    }
    catch {
        Write-Host "AWS credentials not configured" -ForegroundColor $Red
        Write-Host "Please run: aws configure" -ForegroundColor $Red
        exit 1
    }
    
    Write-Host "Prerequisites check passed" -ForegroundColor $Green
    Write-Host ""
}

# Setup Terraform variables
function Set-TerraformVariables {
    Write-Host "Setting up Terraform variables..." -ForegroundColor $Yellow
    
    Set-Location terraform
    
    if (-not (Test-Path "terraform.tfvars")) {
        if (Test-Path "terraform.tfvars.example") {
            Copy-Item "terraform.tfvars.example" "terraform.tfvars"
            Write-Host "Created terraform.tfvars from example" -ForegroundColor $Yellow
            Write-Host "Please edit terraform.tfvars with your values" -ForegroundColor $Yellow
            Write-Host ""
            Write-Host "Required changes:"
            Write-Host "1. Set 'allowed_ssh_ip' to your IP address"
            Write-Host "2. Set 'key_pair_name' to your AWS key pair name"
            Write-Host "3. Update other values as needed"
            Write-Host ""
            
            # Open file in default editor
            Start-Process notepad "terraform.tfvars"
            
            if (-not $SkipConfirmation) {
                Read-Host "Press Enter after editing terraform.tfvars to continue"
            }
        } else {
            Write-Host "terraform.tfvars.example not found" -ForegroundColor $Red
            exit 1
        }
    }
    
    Write-Host "Terraform variables ready" -ForegroundColor $Green
    Write-Host ""
}

# Initialize Terraform
function Initialize-Terraform {
    Write-Host "Initializing Terraform..." -ForegroundColor $Yellow
    
    terraform init
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Terraform initialized successfully" -ForegroundColor $Green
    } else {
        Write-Host "Terraform initialization failed" -ForegroundColor $Red
        exit 1
    }
    Write-Host ""
}

# Plan Terraform deployment
function Start-TerraformPlan {
    Write-Host "Planning Terraform deployment..." -ForegroundColor $Yellow
    
    terraform plan -out=tfplan
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Terraform plan completed" -ForegroundColor $Green
    } else {
        Write-Host "Terraform plan failed" -ForegroundColor $Red
        exit 1
    }
    Write-Host ""
}

# Apply Terraform deployment
function Start-TerraformApply {
    Write-Host "Applying Terraform deployment..." -ForegroundColor $Yellow
    Write-Host "This will create AWS resources and may incur costs." -ForegroundColor $Yellow
    
    if (-not $SkipConfirmation) {
        $confirmation = Read-Host "Do you want to continue? (y/N)"
        if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
            Write-Host "Deployment cancelled"
            exit 0
        }
    }
    
    terraform apply tfplan
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Terraform deployment completed successfully" -ForegroundColor $Green
        Write-Host ""
        Write-Host "=== Deployment Outputs ===" -ForegroundColor $Blue
        terraform output
    } else {
        Write-Host "Terraform deployment failed" -ForegroundColor $Red
        exit 1
    }
}

# Main function
function Main {
    Write-Host "Starting Terraform deployment for NT548 infrastructure..."
    Write-Host ""
    
    Test-Prerequisites
    Set-TerraformVariables
    Initialize-Terraform
    Start-TerraformPlan
    Start-TerraformApply
    
    Write-Host ""
    Write-Host "=== Deployment Complete ===" -ForegroundColor $Green
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "1. Run tests: cd tests && .\run-tests.ps1"
    Write-Host "2. Test connectivity: cd tests && .\test-connectivity.ps1"
    Write-Host "3. Access your public instance via the IP shown in outputs"
    Write-Host ""
    Write-Host "To destroy the infrastructure later:"
    Write-Host "cd terraform && terraform destroy"
}

# Run main function
Main
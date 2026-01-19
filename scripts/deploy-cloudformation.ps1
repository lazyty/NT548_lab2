# PowerShell script for CloudFormation deployment on Windows
# NT548 Infrastructure Deployment

param(
    [switch]$SkipConfirmation
)

# Colors for output
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Cyan"

# Configuration
$StackName = "nt548-infrastructure"
$TemplateFile = "cloudformation/templates/main.yaml"
$ParametersFile = "cloudformation/parameters/dev.json"

Write-Host "=== NT548 CloudFormation Deployment Script ===" -ForegroundColor $Blue
Write-Host ""

# Check prerequisites
function Test-Prerequisites {
    Write-Host "Checking prerequisites..." -ForegroundColor $Yellow
    
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
    
    # Check template file
    if (-not (Test-Path $TemplateFile)) {
        Write-Host "CloudFormation template not found: $TemplateFile" -ForegroundColor $Red
        exit 1
    }
    
    # Check parameters file
    if (-not (Test-Path $ParametersFile)) {
        Write-Host "Parameters file not found: $ParametersFile" -ForegroundColor $Red
        exit 1
    }
    
    Write-Host "Prerequisites check passed" -ForegroundColor $Green
    Write-Host ""
}

# Setup parameters
function Set-Parameters {
    Write-Host "Setting up CloudFormation parameters..." -ForegroundColor $Yellow
    
    $content = Get-Content $ParametersFile -Raw
    if ($content -match "your-key-pair-name") {
        Write-Host "Please update the parameters file: $ParametersFile" -ForegroundColor $Yellow
        Write-Host ""
        Write-Host "Required changes:"
        Write-Host "1. Set 'KeyPairName' to your AWS key pair name"
        Write-Host "2. Set 'AllowedSshIp' to your IP address for security"
        Write-Host "3. Update 'AvailabilityZone' if needed"
        Write-Host ""
        
        # Open file in default editor
        Start-Process notepad $ParametersFile
        
        if (-not $SkipConfirmation) {
            Read-Host "Press Enter after editing the parameters file to continue"
        }
    }
    
    Write-Host "Parameters ready" -ForegroundColor $Green
    Write-Host ""
}

# Validate CloudFormation template
function Test-Template {
    Write-Host "Validating CloudFormation template..." -ForegroundColor $Yellow
    
    aws cloudformation validate-template --template-body "file://$TemplateFile" > $null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Template validation successful" -ForegroundColor $Green
    } else {
        Write-Host "Template validation failed" -ForegroundColor $Red
        exit 1
    }
    Write-Host ""
}

# Check if stack exists
function Test-StackExists {
    $null = aws cloudformation describe-stacks --stack-name $StackName 2>$null
    return ($LASTEXITCODE -eq 0)
}

# Deploy CloudFormation stack
function Start-StackDeployment {
    Write-Host "Deploying CloudFormation stack..." -ForegroundColor $Yellow
    Write-Host "Stack name: $StackName" -ForegroundColor $Yellow
    Write-Host "This will create AWS resources and may incur costs." -ForegroundColor $Yellow
    
    if (-not $SkipConfirmation) {
        $confirmation = Read-Host "Do you want to continue? (y/N)"
        if ($confirmation -ne 'y' -and $confirmation -ne 'Y') {
            Write-Host "Deployment cancelled"
            exit 0
        }
    }
    
    if (Test-StackExists) {
        Write-Host "Stack exists. Updating..." -ForegroundColor $Yellow
        
        aws cloudformation update-stack `
            --stack-name $StackName `
            --template-body "file://$TemplateFile" `
            --parameters "file://$ParametersFile" `
            --capabilities CAPABILITY_IAM
        
        Write-Host "Waiting for stack update to complete..."
        aws cloudformation wait stack-update-complete --stack-name $StackName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Stack update completed successfully" -ForegroundColor $Green
        } else {
            Write-Host "Stack update failed" -ForegroundColor $Red
            exit 1
        }
    } else {
        Write-Host "Creating new stack..." -ForegroundColor $Yellow
        
        aws cloudformation create-stack `
            --stack-name $StackName `
            --template-body "file://$TemplateFile" `
            --parameters "file://$ParametersFile" `
            --capabilities CAPABILITY_IAM
        
        Write-Host "Waiting for stack creation to complete..."
        aws cloudformation wait stack-create-complete --stack-name $StackName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Stack creation completed successfully" -ForegroundColor $Green
        } else {
            Write-Host "Stack creation failed" -ForegroundColor $Red
            exit 1
        }
    }
}

# Show stack outputs
function Show-Outputs {
    Write-Host ""
    Write-Host "=== Stack Outputs ===" -ForegroundColor $Blue
    aws cloudformation describe-stacks `
        --stack-name $StackName `
        --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' `
        --output table
}

# Show stack resources
function Show-Resources {
    Write-Host ""
    Write-Host "=== Stack Resources ===" -ForegroundColor $Blue
    aws cloudformation describe-stack-resources `
        --stack-name $StackName `
        --query 'StackResources[*].[ResourceType,LogicalResourceId,ResourceStatus]' `
        --output table
}

# Main function
function Main {
    Write-Host "Starting CloudFormation deployment for NT548 infrastructure..."
    Write-Host ""
    
    Test-Prerequisites
    Set-Parameters
    Test-Template
    Start-StackDeployment
    Show-Outputs
    Show-Resources
    
    Write-Host ""
    Write-Host "=== Deployment Complete ===" -ForegroundColor $Green
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "1. Note the public IP from the outputs above"
    Write-Host "2. Test HTTP connectivity: Invoke-WebRequest http://PUBLIC_IP"
    Write-Host "3. Test SSH connectivity (if key pair configured)"
    Write-Host ""
    Write-Host "To delete the stack later:"
    Write-Host "aws cloudformation delete-stack --stack-name $StackName"
}

# Run main function
Main
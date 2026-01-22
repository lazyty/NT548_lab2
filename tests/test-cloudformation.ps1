#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test CloudFormation stack deployment
.DESCRIPTION
    Validates CloudFormation stack resources and outputs
#>

param(
    [string]$StackName = "NT548-Infrastructure",
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"

# Colors
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Cyan"

Write-Host "=== CloudFormation Stack Test Suite ===" -ForegroundColor $Blue
Write-Host "Stack: $StackName" -ForegroundColor $Yellow
Write-Host "Region: $Region" -ForegroundColor $Yellow
Write-Host ""

# Check AWS credentials
function Test-AWSCredentials {
    Write-Host "Checking AWS credentials..." -ForegroundColor $Yellow
    try {
        $null = aws sts get-caller-identity 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "AWS credentials valid" -ForegroundColor $Green
            return $true
        }
    }
    catch {
        Write-Host "AWS credentials not configured" -ForegroundColor $Red
        return $false
    }
    return $false
}

# Test stack exists
function Test-StackExists {
    Write-Host "Checking if stack exists..." -ForegroundColor $Yellow
    
    $stackStatus = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].StackStatus' --output text 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Stack exists with status: $stackStatus" -ForegroundColor $Green
        
        if ($stackStatus -eq "CREATE_COMPLETE" -or $stackStatus -eq "UPDATE_COMPLETE") {
            return $true
        }
        elseif ($stackStatus -like "*IN_PROGRESS") {
            Write-Host "Stack is still being created/updated" -ForegroundColor $Yellow
            return $false
        }
        else {
            Write-Host "Stack is in unexpected state: $stackStatus" -ForegroundColor $Red
            return $false
        }
    }
    else {
        Write-Host "Stack not found: $StackName" -ForegroundColor $Red
        return $false
    }
}

# Test VPC resource
function Test-VPCResource {
    Write-Host "Testing VPC resource..." -ForegroundColor $Yellow
    
    $vpcId = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs[?OutputKey==`VPCId`].OutputValue' --output text 2>$null
    
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($vpcId)) {
        Write-Host "VPC output not found" -ForegroundColor $Red
        return $false
    }
    
    $vpcState = aws ec2 describe-vpcs --vpc-ids $vpcId --region $Region --query 'Vpcs[0].State' --output text 2>$null
    
    if ($LASTEXITCODE -eq 0 -and $vpcState -eq "available") {
        Write-Host "VPC is available: $vpcId" -ForegroundColor $Green
        return $true
    }
    else {
        Write-Host "VPC not available" -ForegroundColor $Red
        return $false
    }
}

# Test subnet resources
function Test-SubnetResources {
    Write-Host "Testing subnet resources..." -ForegroundColor $Yellow
    
    $publicSubnetId = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetId`].OutputValue' --output text 2>$null
    $privateSubnetId = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnetId`].OutputValue' --output text 2>$null
    
    if ([string]::IsNullOrEmpty($publicSubnetId) -or [string]::IsNullOrEmpty($privateSubnetId)) {
        Write-Host "Subnet outputs not found" -ForegroundColor $Red
        return $false
    }
    
    $publicState = aws ec2 describe-subnets --subnet-ids $publicSubnetId --region $Region --query 'Subnets[0].State' --output text 2>$null
    $privateState = aws ec2 describe-subnets --subnet-ids $privateSubnetId --region $Region --query 'Subnets[0].State' --output text 2>$null
    
    if ($publicState -eq "available" -and $privateState -eq "available") {
        Write-Host "Public subnet: $publicSubnetId" -ForegroundColor $Green
        Write-Host "Private subnet: $privateSubnetId" -ForegroundColor $Green
        return $true
    }
    else {
        Write-Host "Subnets not available" -ForegroundColor $Red
        return $false
    }
}

# Test EC2 instances
function Test-EC2Instances {
    Write-Host "Testing EC2 instances..." -ForegroundColor $Yellow
    
    $publicInstanceId = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs[?OutputKey==`PublicEC2InstanceId`].OutputValue' --output text 2>$null
    $privateInstanceId = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs[?OutputKey==`PrivateEC2InstanceId`].OutputValue' --output text 2>$null
    
    if ([string]::IsNullOrEmpty($publicInstanceId) -or [string]::IsNullOrEmpty($privateInstanceId)) {
        Write-Host "EC2 instance outputs not found" -ForegroundColor $Red
        return $false
    }
    
    $publicState = aws ec2 describe-instances --instance-ids $publicInstanceId --region $Region --query 'Reservations[0].Instances[0].State.Name' --output text 2>$null
    $privateState = aws ec2 describe-instances --instance-ids $privateInstanceId --region $Region --query 'Reservations[0].Instances[0].State.Name' --output text 2>$null
    
    if ($publicState -eq "running" -and $privateState -eq "running") {
        Write-Host "Public instance running: $publicInstanceId" -ForegroundColor $Green
        Write-Host "Private instance running: $privateInstanceId" -ForegroundColor $Green
        return $true
    }
    else {
        Write-Host "Public instance state: $publicState" -ForegroundColor $Yellow
        Write-Host "Private instance state: $privateState" -ForegroundColor $Yellow
        return $false
    }
}

# Test security groups
function Test-SecurityGroups {
    Write-Host "Testing security groups..." -ForegroundColor $Yellow
    
    $publicSgId = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs[?OutputKey==`PublicSecurityGroupId`].OutputValue' --output text 2>$null
    $privateSgId = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs[?OutputKey==`PrivateSecurityGroupId`].OutputValue' --output text 2>$null
    
    if ([string]::IsNullOrEmpty($publicSgId) -or [string]::IsNullOrEmpty($privateSgId)) {
        Write-Host "Security group outputs not found" -ForegroundColor $Red
        return $false
    }
    
    $publicSgExists = aws ec2 describe-security-groups --group-ids $publicSgId --region $Region --query 'SecurityGroups[0].GroupId' --output text 2>$null
    $privateSgExists = aws ec2 describe-security-groups --group-ids $privateSgId --region $Region --query 'SecurityGroups[0].GroupId' --output text 2>$null
    
    if ($publicSgExists -eq $publicSgId -and $privateSgExists -eq $privateSgId) {
        Write-Host "Public security group: $publicSgId" -ForegroundColor $Green
        Write-Host "Private security group: $privateSgId" -ForegroundColor $Green
        return $true
    }
    else {
        Write-Host "Security groups not found" -ForegroundColor $Red
        return $false
    }
}

# Test stack outputs
function Test-StackOutputs {
    Write-Host "Testing stack outputs..." -ForegroundColor $Yellow
    
    $outputs = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs' --output json 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to retrieve stack outputs" -ForegroundColor $Red
        return $false
    }
    
    $outputsObj = $outputs | ConvertFrom-Json
    $outputCount = $outputsObj.Count
    
    Write-Host "Stack has $outputCount outputs:" -ForegroundColor $Green
    foreach ($output in $outputsObj) {
        Write-Host "  - $($output.OutputKey): $($output.OutputValue)" -ForegroundColor $Green
    }
    
    return $true
}

# Main test execution
function Main {
    Write-Host "Starting CloudFormation stack tests..." -ForegroundColor $Blue
    Write-Host ""
    
    if (-not (Test-AWSCredentials)) {
        Write-Host "AWS credentials test failed" -ForegroundColor $Red
        exit 1
    }
    Write-Host ""
    
    $FailedTests = 0
    
    if (-not (Test-StackExists)) { 
        Write-Host "Stack does not exist or is not ready" -ForegroundColor $Red
        exit 1
    }
    Write-Host ""
    
    if (-not (Test-VPCResource)) { $FailedTests++ }
    Write-Host ""
    
    if (-not (Test-SubnetResources)) { $FailedTests++ }
    Write-Host ""
    
    if (-not (Test-SecurityGroups)) { $FailedTests++ }
    Write-Host ""
    
    if (-not (Test-EC2Instances)) { $FailedTests++ }
    Write-Host ""
    
    if (-not (Test-StackOutputs)) { $FailedTests++ }
    Write-Host ""
    
    # Summary
    Write-Host "=== Test Summary ===" -ForegroundColor $Blue
    if ($FailedTests -eq 0) {
        Write-Host "All tests passed!" -ForegroundColor $Green
        Write-Host "CloudFormation stack is deployed correctly."
    }
    else {
        Write-Host "$FailedTests test(s) failed" -ForegroundColor $Red
        Write-Host "Please check the stack deployment."
        exit 1
    }
}

# Run main
Main

#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploy AWS CodePipeline for CloudFormation
.DESCRIPTION
    Deploys CodePipeline stack for automated CloudFormation deployment
#>

param(
    [string]$StackName = "NT548-CodePipeline",
    [string]$RepositoryName = "nt548-infrastructure",
    [string]$BranchName = "main",
    [string]$InfraStackName = "NT548-Infrastructure",
    [string]$Region = "us-east-1",
    [string]$NotificationEmail = ""
)

$ErrorActionPreference = "Stop"

Write-Host "=== Deploying AWS CodePipeline ===" -ForegroundColor Cyan
Write-Host "Stack Name: $StackName" -ForegroundColor Yellow
Write-Host "Repository: $RepositoryName" -ForegroundColor Yellow
Write-Host "Branch: $BranchName" -ForegroundColor Yellow
Write-Host "Region: $Region" -ForegroundColor Yellow
Write-Host ""

# Check if repository exists
Write-Host "Checking if CodeCommit repository exists..." -ForegroundColor Cyan
$repoExists = aws codecommit get-repository --repository-name $RepositoryName --region $Region 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Repository not found: $RepositoryName" -ForegroundColor Red
    Write-Host "Please run: pwsh scripts/setup-codecommit.ps1" -ForegroundColor Yellow
    exit 1
}

Write-Host "Repository found!" -ForegroundColor Green
Write-Host ""

# Validate template
Write-Host "Validating CloudFormation template..." -ForegroundColor Cyan
aws cloudformation validate-template `
    --template-body file://cloudformation/pipeline/codepipeline.yaml `
    --region $Region

if ($LASTEXITCODE -ne 0) {
    Write-Host "Template validation failed" -ForegroundColor Red
    exit 1
}

Write-Host "Template is valid!" -ForegroundColor Green
Write-Host ""

# Check if stack exists
Write-Host "Checking if stack exists..." -ForegroundColor Cyan
$stackExists = aws cloudformation describe-stacks --stack-name $StackName --region $Region 2>$null

$parameters = @(
    "ParameterKey=RepositoryName,ParameterValue=$RepositoryName",
    "ParameterKey=BranchName,ParameterValue=$BranchName",
    "ParameterKey=StackName,ParameterValue=$InfraStackName"
)

if (![string]::IsNullOrEmpty($NotificationEmail)) {
    $parameters += "ParameterKey=NotificationEmail,ParameterValue=$NotificationEmail"
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "Stack exists, updating..." -ForegroundColor Yellow
    
    aws cloudformation update-stack `
        --stack-name $StackName `
        --template-body file://cloudformation/pipeline/codepipeline.yaml `
        --parameters $parameters `
        --capabilities CAPABILITY_NAMED_IAM `
        --region $Region
    
    if ($LASTEXITCODE -ne 0) {
        $errorMsg = $Error[0].Exception.Message
        if ($errorMsg -like "*No updates are to be performed*") {
            Write-Host "No updates needed" -ForegroundColor Yellow
        } else {
            Write-Host "Stack update failed" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Waiting for stack update to complete..." -ForegroundColor Yellow
        aws cloudformation wait stack-update-complete --stack-name $StackName --region $Region
        
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Stack update failed or timed out" -ForegroundColor Red
            exit 1
        }
    }
} else {
    Write-Host "Creating new stack..." -ForegroundColor Yellow
    
    aws cloudformation create-stack `
        --stack-name $StackName `
        --template-body file://cloudformation/pipeline/codepipeline.yaml `
        --parameters $parameters `
        --capabilities CAPABILITY_NAMED_IAM `
        --region $Region
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Stack creation failed" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "Waiting for stack creation to complete..." -ForegroundColor Yellow
    aws cloudformation wait stack-create-complete --stack-name $StackName --region $Region
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Stack creation failed or timed out" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "=== Deployment Complete ===" -ForegroundColor Green
Write-Host ""

# Get outputs
Write-Host "Stack Outputs:" -ForegroundColor Cyan
$outputs = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs' --output table

Write-Host $outputs
Write-Host ""

# Get pipeline URL
$pipelineUrl = aws cloudformation describe-stacks `
    --stack-name $StackName `
    --region $Region `
    --query 'Stacks[0].Outputs[?OutputKey==`PipelineUrl`].OutputValue' `
    --output text

Write-Host "Pipeline URL: $pipelineUrl" -ForegroundColor Green
Write-Host ""

Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. View pipeline: $pipelineUrl" -ForegroundColor White
Write-Host "2. Push changes to trigger pipeline: git push codecommit main" -ForegroundColor White
Write-Host "3. Monitor pipeline execution in AWS Console" -ForegroundColor White
Write-Host "4. Approve manual approval step when ready" -ForegroundColor White

#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Setup AWS CodeCommit repository and push code
.DESCRIPTION
    Creates CodeCommit repository and pushes local code to it
#>

param(
    [string]$RepositoryName = "nt548-infrastructure",
    [string]$Region = "us-east-1",
    [string]$Description = "NT548 Infrastructure as Code repository"
)

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up AWS CodeCommit Repository ===" -ForegroundColor Cyan
Write-Host "Repository: $RepositoryName" -ForegroundColor Yellow
Write-Host "Region: $Region" -ForegroundColor Yellow
Write-Host ""

# Check if repository exists
Write-Host "Checking if repository exists..." -ForegroundColor Cyan
$repoExists = aws codecommit get-repository --repository-name $RepositoryName --region $Region 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "Repository already exists: $RepositoryName" -ForegroundColor Green
    $repoInfo = $repoExists | ConvertFrom-Json
    $cloneUrl = $repoInfo.repositoryMetadata.cloneUrlHttp
} else {
    Write-Host "Creating CodeCommit repository..." -ForegroundColor Yellow
    $createResult = aws codecommit create-repository `
        --repository-name $RepositoryName `
        --repository-description $Description `
        --region $Region
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to create repository" -ForegroundColor Red
        exit 1
    }
    
    $repoInfo = $createResult | ConvertFrom-Json
    $cloneUrl = $repoInfo.repositoryMetadata.cloneUrlHttp
    Write-Host "Repository created successfully!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Clone URL: $cloneUrl" -ForegroundColor Green
Write-Host ""

# Configure Git credentials helper
Write-Host "Configuring Git credentials helper..." -ForegroundColor Cyan
git config --global credential.helper '!aws codecommit credential-helper $@'
git config --global credential.UseHttpPath true

# Check if git remote exists
$remoteExists = git remote get-url codecommit 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "Git remote 'codecommit' already exists" -ForegroundColor Yellow
    Write-Host "Updating remote URL..." -ForegroundColor Yellow
    git remote set-url codecommit $cloneUrl
} else {
    Write-Host "Adding git remote 'codecommit'..." -ForegroundColor Yellow
    git remote add codecommit $cloneUrl
}

Write-Host ""
Write-Host "=== Pushing code to CodeCommit ===" -ForegroundColor Cyan

# Check current branch
$currentBranch = git branch --show-current

if ([string]::IsNullOrEmpty($currentBranch)) {
    Write-Host "No branch checked out, creating main branch..." -ForegroundColor Yellow
    git checkout -b main
    $currentBranch = "main"
}

Write-Host "Current branch: $currentBranch" -ForegroundColor Yellow

# Add all files
Write-Host "Adding files to git..." -ForegroundColor Yellow
git add .

# Check if there are changes to commit
$status = git status --porcelain
if ([string]::IsNullOrEmpty($status)) {
    Write-Host "No changes to commit" -ForegroundColor Yellow
} else {
    Write-Host "Committing changes..." -ForegroundColor Yellow
    git commit -m "Initial commit: NT548 Infrastructure as Code"
}

# Push to CodeCommit
Write-Host "Pushing to CodeCommit..." -ForegroundColor Yellow
git push codecommit $currentBranch

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to push to CodeCommit" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Make sure AWS CLI is configured with proper credentials" -ForegroundColor White
    Write-Host "2. Verify IAM user has CodeCommit permissions" -ForegroundColor White
    Write-Host "3. Check if Git credential helper is configured correctly" -ForegroundColor White
    Write-Host ""
    Write-Host "Manual setup:" -ForegroundColor Yellow
    Write-Host "git config --global credential.helper '!aws codecommit credential-helper `$@'" -ForegroundColor White
    Write-Host "git config --global credential.UseHttpPath true" -ForegroundColor White
    exit 1
}

Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Repository URL: $cloneUrl" -ForegroundColor Green
Write-Host "Branch: $currentBranch" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Deploy CodePipeline: pwsh scripts/deploy-codepipeline.ps1" -ForegroundColor White
Write-Host "2. View repository: aws codecommit get-repository --repository-name $RepositoryName" -ForegroundColor White
Write-Host "3. Clone repository: git clone $cloneUrl" -ForegroundColor White
Write-Host ""
Write-Host "To push changes in the future:" -ForegroundColor Cyan
Write-Host "git add ." -ForegroundColor White
Write-Host "git commit -m 'Your message'" -ForegroundColor White
Write-Host "git push codecommit main" -ForegroundColor White

<#
.SYNOPSIS
    Setup AWS CodeCommit repository and push code
.DESCRIPTION
    Creates CodeCommit repository and pushes local code to it
.NOTES
    Compatible with PowerShell 5.1+
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
$repoExists = $null
try {
    $repoExists = aws codecommit get-repository --repository-name $RepositoryName --region $Region 2>&1
    $repoFound = $LASTEXITCODE -eq 0
} catch {
    $repoFound = $false
}

if ($repoFound) {
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
git config --global credential.helper "!aws codecommit credential-helper `$@"
git config --global credential.UseHttpPath true

# Verify AWS credentials work
Write-Host "Verifying AWS credentials..." -ForegroundColor Cyan
$identity = aws sts get-caller-identity 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "AWS credentials not configured properly!" -ForegroundColor Red
    Write-Host "Please run: aws configure" -ForegroundColor Yellow
    exit 1
}
Write-Host "AWS credentials verified" -ForegroundColor Green
Write-Host ""

# Check if git remote exists
$remoteExists = $null
try {
    $remoteExists = git remote get-url codecommit 2>&1
    $hasRemote = $LASTEXITCODE -eq 0
} catch {
    $hasRemote = $false
}

if ($hasRemote) {
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
Write-Host "Note: This uses AWS IAM credentials, not GitHub credentials" -ForegroundColor Cyan

$pushOutput = git push codecommit $currentBranch 2>&1
$pushSuccess = $LASTEXITCODE -eq 0

if (-not $pushSuccess) {
    Write-Host "Failed to push to CodeCommit" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error details:" -ForegroundColor Yellow
    Write-Host $pushOutput -ForegroundColor Gray
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "1. Make sure AWS CLI is configured: aws configure" -ForegroundColor White
    Write-Host "2. Verify IAM user has CodeCommit permissions:" -ForegroundColor White
    Write-Host "   - AWSCodeCommitPowerUser (recommended)" -ForegroundColor White
    Write-Host "   - Or codecommit:GitPull and codecommit:GitPush" -ForegroundColor White
    Write-Host "3. Test AWS credentials: aws sts get-caller-identity" -ForegroundColor White
    Write-Host "4. Reconfigure Git credential helper:" -ForegroundColor White
    Write-Host '   git config --global credential.helper "!aws codecommit credential-helper $@"' -ForegroundColor White
    Write-Host "   git config --global credential.UseHttpPath true" -ForegroundColor White
    Write-Host ""
    Write-Host "5. If still failing, try HTTPS with credential helper:" -ForegroundColor White
    Write-Host "   git config --global credential.helper store" -ForegroundColor White
    Write-Host "   Then manually enter AWS credentials when prompted" -ForegroundColor White
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

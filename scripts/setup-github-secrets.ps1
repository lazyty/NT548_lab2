# NT548 - GitHub Secrets Setup Helper
# PowerShell script to configure GitHub repository secrets for CI/CD

param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubRepo,
    
    [Parameter(Mandatory=$false)]
    [string]$AllowedSshIp,
    
    [Parameter(Mandatory=$false)]
    [string]$KeyPairName = "nt548-keypair",
    
    [Parameter(Mandatory=$false)]
    [switch]$SetSecrets
)

# Colors for output
$Blue = "Cyan"
$Green = "Green"
$Yellow = "Yellow"
$Red = "Red"
$Gray = "Gray"

Write-Host "=== NT548 - GitHub Secrets Setup Helper ===" -ForegroundColor $Blue
Write-Host "Configuring CI/CD secrets for automated Terraform deployment" -ForegroundColor $Gray
Write-Host ""

# Check GitHub CLI availability
$ghCliAvailable = $false
try {
    $null = Get-Command gh -ErrorAction Stop
    $ghCliAvailable = $true
    Write-Host "GitHub CLI found" -ForegroundColor $Green
    
    # Check if authenticated
    $authStatus = gh auth status 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "GitHub CLI authenticated" -ForegroundColor $Green
    } else {
        Write-Host "GitHub CLI not authenticated. Run: gh auth login" -ForegroundColor $Yellow
        $ghCliAvailable = $false
    }
} catch {
    Write-Host "GitHub CLI not found" -ForegroundColor $Red
    Write-Host "Install from: https://cli.github.com/" -ForegroundColor $Yellow
}

Write-Host ""

# Auto-detect IP if not provided
if ([string]::IsNullOrEmpty($AllowedSshIp)) {
    Write-Host "Detecting your public IP address..." -ForegroundColor $Blue
    try {
        $AllowedSshIp = (Invoke-WebRequest -Uri "https://ipinfo.io/ip" -UseBasicParsing -TimeoutSec 10).Content.Trim()
        Write-Host "Detected IP: $AllowedSshIp" -ForegroundColor $Green
    } catch {
        Write-Host "Could not auto-detect IP" -ForegroundColor $Yellow
        $AllowedSshIp = Read-Host "Please enter your public IP address"
    }
}

# Validate IP format
if ($AllowedSshIp -notmatch '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
    Write-Host "Invalid IP format: $AllowedSshIp" -ForegroundColor $Red
    exit 1
}

Write-Host ""
Write-Host "Required GitHub Secrets for NT548 CI/CD Pipeline" -ForegroundColor $Yellow
Write-Host "Repository: $GitHubRepo" -ForegroundColor $Gray
Write-Host ""

# Define secrets
$secrets = @(
    @{
        Name = "AWS_ACCESS_KEY_ID"
        Description = "Your AWS Access Key ID (from AWS IAM)"
        Value = ""
        Required = $true
    },
    @{
        Name = "AWS_SECRET_ACCESS_KEY"
        Description = "Your AWS Secret Access Key (from AWS IAM)"
        Value = ""
        Required = $true
    },
    @{
        Name = "TF_VAR_allowed_ssh_ip"
        Description = "Your public IP address for SSH access"
        Value = "$AllowedSshIp/32"
        Required = $true
    },
    @{
        Name = "TF_VAR_key_pair_name"
        Description = "AWS EC2 Key Pair name"
        Value = $KeyPairName
        Required = $true
    }
)

# Display secrets information
foreach ($secret in $secrets) {
    Write-Host "$($secret.Name)" -ForegroundColor $Green
    Write-Host "   Description: $($secret.Description)" -ForegroundColor $Gray
    if ($secret.Value) {
        Write-Host "   Value: $($secret.Value)" -ForegroundColor $Gray
    } else {
        Write-Host "   Value: <Enter your value>" -ForegroundColor $Yellow
    }
    Write-Host ""
}

# GitHub CLI commands
if ($ghCliAvailable) {
    Write-Host "GitHub CLI Commands:" -ForegroundColor $Green
    Write-Host ""
    
    foreach ($secret in $secrets) {
        if ($secret.Value) {
            Write-Host "gh secret set $($secret.Name) --body `"$($secret.Value)`" --repo $GitHubRepo" -ForegroundColor $Blue
        } else {
            Write-Host "gh secret set $($secret.Name) --repo $GitHubRepo" -ForegroundColor $Blue
        }
    }
    Write-Host ""
    
    # Option to set secrets automatically
    if ($SetSecrets) {
        Write-Host "Setting secrets automatically..." -ForegroundColor $Blue
        
        # Set secrets with values
        foreach ($secret in $secrets) {
            if ($secret.Value) {
                Write-Host "Setting $($secret.Name)..." -ForegroundColor $Gray
                $result = gh secret set $secret.Name --body $secret.Value --repo $GitHubRepo 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "$($secret.Name) set successfully" -ForegroundColor $Green
                } else {
                    Write-Host "Failed to set $($secret.Name): $result" -ForegroundColor $Red
                }
            } else {
                Write-Host "Skipping $($secret.Name) - requires manual input" -ForegroundColor $Yellow
            }
        }
        
        Write-Host ""
        Write-Host "Please set AWS credentials manually:" -ForegroundColor $Yellow
        Write-Host "gh secret set AWS_ACCESS_KEY_ID --repo $GitHubRepo" -ForegroundColor $Blue
        Write-Host "gh secret set AWS_SECRET_ACCESS_KEY --repo $GitHubRepo" -ForegroundColor $Blue
    }
}

# Manual setup instructions
Write-Host "Manual Setup Instructions:" -ForegroundColor $Yellow
Write-Host "1. Go to: https://github.com/$GitHubRepo/settings/secrets/actions" -ForegroundColor $Gray
Write-Host "2. Click 'New repository secret'" -ForegroundColor $Gray
Write-Host "3. Add each secret listed above with their respective values" -ForegroundColor $Gray
Write-Host ""

# AWS setup instructions
Write-Host "AWS Prerequisites:" -ForegroundColor $Blue
Write-Host "1. Create AWS IAM user with programmatic access" -ForegroundColor $Gray
Write-Host "2. Attach policies: EC2FullAccess, VPCFullAccess, IAMReadOnlyAccess" -ForegroundColor $Gray
Write-Host "3. Create EC2 Key Pair named '$KeyPairName' in your AWS region" -ForegroundColor $Gray
Write-Host "4. Note down Access Key ID and Secret Access Key" -ForegroundColor $Gray
Write-Host ""

# Security best practices
Write-Host "Security Best Practices:" -ForegroundColor $Red
Write-Host "- Use IAM user with minimal required permissions" -ForegroundColor $Gray
Write-Host "- Enable MFA on your AWS account" -ForegroundColor $Gray
Write-Host "- Regularly rotate AWS access keys" -ForegroundColor $Gray
Write-Host "- Monitor AWS CloudTrail for unexpected activity" -ForegroundColor $Gray
Write-Host "- Never commit secrets to your repository" -ForegroundColor $Gray
Write-Host "- Use specific IP addresses instead of 0.0.0.0/0" -ForegroundColor $Gray
Write-Host ""

# Testing instructions
Write-Host "Testing Your Setup:" -ForegroundColor $Green
Write-Host "1. Create a Pull Request to test validation workflow" -ForegroundColor $Gray
Write-Host "2. Push to main branch to trigger deployment workflow" -ForegroundColor $Gray
Write-Host "3. Check GitHub Actions tab for workflow results" -ForegroundColor $Gray
Write-Host "4. Monitor AWS console for created resources" -ForegroundColor $Gray
Write-Host ""

# Workflow information
Write-Host "Available Workflows:" -ForegroundColor $Blue
Write-Host "- terraform-deploy.yml: Main deployment pipeline" -ForegroundColor $Gray
Write-Host "- terraform-pr-check.yml: PR validation and security scanning" -ForegroundColor $Gray
Write-Host ""

Write-Host "Setup guide complete!" -ForegroundColor $Green
Write-Host "Your NT548 CI/CD pipeline is ready for automated Terraform deployment!" -ForegroundColor $Green
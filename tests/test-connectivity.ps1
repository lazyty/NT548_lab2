# PowerShell Connectivity Test Script
# Tests SSH and HTTP connectivity to deployed instances

# Colors
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Cyan"

Write-Host "=== Connectivity Test Suite ===" -ForegroundColor $Blue
Write-Host ""

# Get outputs from Terraform
function Get-TerraformOutputs {
    Set-Location "../terraform"
    $script:PublicIp = ""
    $script:PrivateIp = ""
    
    try {
        $script:PublicIp = terraform output -raw public_ec2_ip 2>$null
        $script:PrivateIp = terraform output -raw private_ec2_ip 2>$null
    }
    catch {
        # Ignore error
    }
    
    Set-Location "../tests"
    
    if ([string]::IsNullOrEmpty($script:PublicIp) -or [string]::IsNullOrEmpty($script:PrivateIp)) {
        Write-Host "Could not get EC2 IPs from Terraform outputs" -ForegroundColor $Red
        exit 1
    }
    
    Write-Host "Public EC2 IP: $($script:PublicIp)"
    Write-Host "Private EC2 IP: $($script:PrivateIp)"
    Write-Host ""
}

# Test HTTP connectivity to public instance
function Test-HTTPConnectivity {
    Write-Host "Testing HTTP connectivity to public instance..." -ForegroundColor $Yellow
    
    try {
        $response = Invoke-WebRequest -Uri "http://$($script:PublicIp)" -TimeoutSec 10 -ErrorAction Stop
        if ($response.StatusCode -eq 200 -and $response.Content -match "NT548") {
            Write-Host "HTTP connectivity successful" -ForegroundColor $Green
            Write-Host "Web page content retrieved successfully"
        } else {
            Write-Host "HTTP connectivity failed - unexpected response" -ForegroundColor $Red
        }
    }
    catch {
        Write-Host "HTTP connectivity failed" -ForegroundColor $Red
        Write-Host "The web server may still be starting up"
        Write-Host "Error: $($_.Exception.Message)"
    }
    Write-Host ""
}

# Test SSH connectivity (requires SSH client and key file)
function Test-SSHConnectivity {
    Write-Host "Testing SSH connectivity..." -ForegroundColor $Yellow
    
    # Check if SSH_KEY_PATH environment variable is set
    $SshKeyPath = $env:SSH_KEY_PATH
    if ([string]::IsNullOrEmpty($SshKeyPath)) {
        Write-Host "SSH_KEY_PATH not set. Skipping SSH tests." -ForegroundColor $Yellow
        Write-Host "To test SSH, set SSH_KEY_PATH environment variable:"
        Write-Host "`$env:SSH_KEY_PATH = 'C:\path\to\your\key.pem'"
        return
    }
    
    if (-not (Test-Path $SshKeyPath)) {
        Write-Host "SSH key file not found: $SshKeyPath" -ForegroundColor $Red
        return
    }
    
    # Check if SSH client is available
    try {
        $null = Get-Command ssh -ErrorAction Stop
    }
    catch {
        Write-Host "SSH client not found. Please install OpenSSH or use WSL." -ForegroundColor $Red
        Write-Host "You can install OpenSSH via Windows Features or use Git Bash."
        return
    }
    
    # Test SSH to public instance
    Write-Host "Testing SSH to public instance..."
    try {
        $sshResult = ssh -i $SshKeyPath -o ConnectTimeout=5 -o StrictHostKeyChecking=no ec2-user@$($script:PublicIp) "echo 'SSH to public instance successful'" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "SSH to public instance successful" -ForegroundColor $Green
            
            # Test SSH from public to private instance
            Write-Host "Testing SSH from public to private instance..."
            $sshToPrivate = ssh -i $SshKeyPath -o ConnectTimeout=5 -o StrictHostKeyChecking=no ec2-user@$($script:PublicIp) "ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ec2-user@$($script:PrivateIp) 'echo SSH to private instance successful'" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "SSH from public to private instance successful" -ForegroundColor $Green
            } else {
                Write-Host "SSH from public to private instance failed" -ForegroundColor $Red
                Write-Host "Make sure the private key is also available on the public instance"
            }
        } else {
            Write-Host "SSH to public instance failed" -ForegroundColor $Red
            Write-Host "Check security group rules and key pair configuration"
        }
    }
    catch {
        Write-Host "SSH test failed: $($_.Exception.Message)" -ForegroundColor $Red
    }
    Write-Host ""
}

# Test network connectivity
function Test-NetworkConnectivity {
    Write-Host "Testing network connectivity..." -ForegroundColor $Yellow
    
    # Ping test to public IP
    try {
        $pingResult = Test-Connection -ComputerName $script:PublicIp -Count 3 -Quiet -ErrorAction Stop
        if ($pingResult) {
            Write-Host "Public instance is reachable via ping" -ForegroundColor $Green
        } else {
            Write-Host "Public instance not reachable via ping (ICMP may be blocked)" -ForegroundColor $Yellow
        }
    }
    catch {
        Write-Host "Public instance not reachable via ping (ICMP may be blocked)" -ForegroundColor $Yellow
    }
    
    # Port connectivity tests
    Write-Host "Testing port connectivity..."
    
    # Test SSH port (22)
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ConnectAsync($script:PublicIp, 22).Wait(5000)
        if ($tcpClient.Connected) {
            Write-Host "SSH port (22) is open" -ForegroundColor $Green
            $tcpClient.Close()
        } else {
            Write-Host "SSH port (22) is not accessible" -ForegroundColor $Red
        }
    }
    catch {
        Write-Host "SSH port (22) is not accessible" -ForegroundColor $Red
    }
    
    # Test HTTP port (80)
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.ConnectAsync($script:PublicIp, 80).Wait(5000)
        if ($tcpClient.Connected) {
            Write-Host "HTTP port (80) is open" -ForegroundColor $Green
            $tcpClient.Close()
        } else {
            Write-Host "HTTP port (80) is not accessible" -ForegroundColor $Red
        }
    }
    catch {
        Write-Host "HTTP port (80) is not accessible" -ForegroundColor $Red
    }
    
    Write-Host ""
}

# Main function
function Main {
    Write-Host "Starting connectivity tests..."
    Write-Host ""
    
    Get-TerraformOutputs
    Test-HTTPConnectivity
    Test-NetworkConnectivity
    Test-SSHConnectivity
    
    Write-Host "=== Connectivity Test Complete ===" -ForegroundColor $Blue
    Write-Host ""
    Write-Host "Notes:"
    Write-Host "- If HTTP tests fail, the web server may still be starting"
    Write-Host "- For SSH tests, set SSH_KEY_PATH environment variable"
    Write-Host "- Some tests may fail due to security group restrictions (this is expected)"
    Write-Host "- You can use Git Bash or WSL for better SSH support on Windows"
}

# Run main function
Main
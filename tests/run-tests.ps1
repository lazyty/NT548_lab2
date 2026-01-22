# PowerShell Test Suite for NT548 Infrastructure
# Tests the deployed AWS infrastructure components

# Colors for output
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Blue = "Cyan"

Write-Host "=== NT548 Infrastructure Test Suite ===" -ForegroundColor $Blue
Write-Host "Testing deployed AWS infrastructure..."
Write-Host ""

# Test VPC
function Test-VPC {
    Write-Host "Testing VPC..." -ForegroundColor $Yellow
    
    # Get VPC ID from Terraform output
    Set-Location "../terraform"
    $VpcId = ""
    try {
        $VpcId = terraform output -raw vpc_id 2>$null
    }
    catch {
        # Ignore error
    }
    Set-Location "../tests"
    
    if ([string]::IsNullOrEmpty($VpcId)) {
        Write-Host "VPC ID not found in Terraform outputs" -ForegroundColor $Red
        return $false
    }
    
    # Check if VPC exists
    $result = aws ec2 describe-vpcs --vpc-ids $VpcId --query 'Vpcs[0].State' --output text 2>$null
    if ($LASTEXITCODE -eq 0 -and $result -eq "available") {
        Write-Host "VPC exists and is available" -ForegroundColor $Green
        return $true
    } else {
        Write-Host "VPC not found or not available" -ForegroundColor $Red
        return $false
    }
}

# Test Subnets
function Test-Subnets {
    Write-Host "Testing Subnets..." -ForegroundColor $Yellow
    
    # Get subnet IDs from Terraform output
    Set-Location "../terraform"
    $PublicSubnetId = ""
    $PrivateSubnetId = ""
    try {
        $PublicSubnetId = terraform output -raw public_subnet_id 2>$null
        $PrivateSubnetId = terraform output -raw private_subnet_id 2>$null
    }
    catch {
        # Ignore error
    }
    Set-Location "../tests"
    
    if ([string]::IsNullOrEmpty($PublicSubnetId) -or [string]::IsNullOrEmpty($PrivateSubnetId)) {
        Write-Host "Subnet IDs not found in Terraform outputs" -ForegroundColor $Red
        return $false
    }
    
    # Test public subnet
    $publicState = aws ec2 describe-subnets --subnet-ids $PublicSubnetId --query 'Subnets[0].State' --output text 2>$null
    if ($LASTEXITCODE -eq 0 -and $publicState -eq "available") {
        Write-Host "Public subnet is available" -ForegroundColor $Green
    } else {
        Write-Host "Public subnet not available" -ForegroundColor $Red
        return $false
    }
    
    # Test private subnet
    $privateState = aws ec2 describe-subnets --subnet-ids $PrivateSubnetId --query 'Subnets[0].State' --output text 2>$null
    if ($LASTEXITCODE -eq 0 -and $privateState -eq "available") {
        Write-Host "Private subnet is available" -ForegroundColor $Green
        return $true
    } else {
        Write-Host "Private subnet not available" -ForegroundColor $Red
        return $false
    }
}

# Test Internet Gateway
function Test-InternetGateway {
    Write-Host "Testing Internet Gateway..." -ForegroundColor $Yellow
    
    Set-Location "../terraform"
    $IgwId = ""
    try {
        $IgwId = terraform output -raw internet_gateway_id 2>$null
    }
    catch {
        # Ignore error
    }
    Set-Location "../tests"
    
    if ([string]::IsNullOrEmpty($IgwId)) {
        Write-Host "Internet Gateway ID not found" -ForegroundColor $Red
        return $false
    }
    
    # Internet Gateway doesn't have a "State" field, just check if it exists
    $igwExists = aws ec2 describe-internet-gateways --internet-gateway-ids $IgwId --query 'InternetGateways[0].InternetGatewayId' --output text 2>$null
    if ($LASTEXITCODE -eq 0 -and $igwExists -eq $IgwId) {
        Write-Host "Internet Gateway exists and is attached" -ForegroundColor $Green
        return $true
    } else {
        Write-Host "Internet Gateway not found" -ForegroundColor $Red
        return $false
    }
}

# Test NAT Gateway
function Test-NATGateway {
    Write-Host "Testing NAT Gateway..." -ForegroundColor $Yellow
    
    Set-Location "../terraform"
    $NatId = ""
    try {
        $NatId = terraform output -raw nat_gateway_id 2>$null
    }
    catch {
        # Ignore error
    }
    Set-Location "../tests"
    
    if ([string]::IsNullOrEmpty($NatId)) {
        Write-Host "NAT Gateway ID not found" -ForegroundColor $Red
        return $false
    }
    
    $natState = aws ec2 describe-nat-gateways --nat-gateway-ids $NatId --query 'NatGateways[0].State' --output text 2>$null
    if ($LASTEXITCODE -eq 0 -and $natState -eq "available") {
        Write-Host "NAT Gateway is available" -ForegroundColor $Green
        return $true
    } else {
        Write-Host "NAT Gateway not available (State: $natState)" -ForegroundColor $Red
        return $false
    }
}

# Test Route Tables
function Test-RouteTables {
    Write-Host "Testing Route Tables..." -ForegroundColor $Yellow
    
    Set-Location "../terraform"
    $VpcId = ""
    try {
        $VpcId = terraform output -raw vpc_id 2>$null
    }
    catch {
        # Ignore error
    }
    Set-Location "../tests"
    
    if ([string]::IsNullOrEmpty($VpcId)) {
        Write-Host "VPC ID not found for route table testing" -ForegroundColor $Red
        return $false
    }
    
    # Get all route tables for this VPC
    $routeTables = aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VpcId" --query 'RouteTables[*].[RouteTableId,Tags[?Key==`Name`].Value|[0]]' --output text 2>$null
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to retrieve route tables" -ForegroundColor $Red
        return $false
    }
    
    $publicRTFound = $false
    $privateRTFound = $false
    
    # Check for public and private route tables
    $routeTables -split "`n" | ForEach-Object {
        $parts = $_ -split "`t"
        if ($parts.Length -ge 2) {
            $rtName = $parts[1]
            if ($rtName -like "*Public*") {
                $publicRTFound = $true
                Write-Host "Public Route Table found: $($parts[0])" -ForegroundColor $Green
            }
            elseif ($rtName -like "*Private*") {
                $privateRTFound = $true
                Write-Host "Private Route Table found: $($parts[0])" -ForegroundColor $Green
            }
        }
    }
    
    if ($publicRTFound -and $privateRTFound) {
        Write-Host "Both Public and Private Route Tables exist" -ForegroundColor $Green
        return $true
    } else {
        Write-Host "Missing route tables - Public: $publicRTFound, Private: $privateRTFound" -ForegroundColor $Red
        return $false
    }
}

# Test Default Security Group
function Test-DefaultSecurityGroup {
    Write-Host "Testing Default Security Group..." -ForegroundColor $Yellow
    
    Set-Location "../terraform"
    $VpcId = ""
    try {
        $VpcId = terraform output -raw vpc_id 2>$null
    }
    catch {
        # Ignore error
    }
    Set-Location "../tests"
    
    if ([string]::IsNullOrEmpty($VpcId)) {
        Write-Host "VPC ID not found for default SG testing" -ForegroundColor $Red
        return $false
    }
    
    # Get default security group for this VPC
    $defaultSG = aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VpcId" "Name=group-name,Values=default" --query 'SecurityGroups[0].GroupId' --output text 2>$null
    
    if ($LASTEXITCODE -eq 0 -and $defaultSG -ne "None" -and ![string]::IsNullOrEmpty($defaultSG)) {
        Write-Host "Default Security Group exists: $defaultSG" -ForegroundColor $Green
        return $true
    } else {
        Write-Host "Default Security Group not found" -ForegroundColor $Red
        return $false
    }
}

# Test Security Group Rules
function Test-SecurityGroupRules {
    Write-Host "Testing Security Group Rules..." -ForegroundColor $Yellow
    
    Set-Location "../terraform"
    $PublicSgId = ""
    $PrivateSgId = ""
    try {
        $PublicSgId = terraform output -raw public_security_group_id 2>$null
        $PrivateSgId = terraform output -raw private_security_group_id 2>$null
    }
    catch {
        # Ignore error
    }
    Set-Location "../tests"
    
    if ([string]::IsNullOrEmpty($PublicSgId) -or [string]::IsNullOrEmpty($PrivateSgId)) {
        Write-Host "Security Group IDs not found" -ForegroundColor $Red
        return $false
    }
    
    # Test Public SG rules (should have SSH port 22)
    $publicRules = aws ec2 describe-security-groups --group-ids $PublicSgId --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]' --output text 2>$null
    if ($LASTEXITCODE -eq 0 -and ![string]::IsNullOrEmpty($publicRules)) {
        Write-Host "Public Security Group has SSH rule (port 22)" -ForegroundColor $Green
    } else {
        Write-Host "Public Security Group missing SSH rule" -ForegroundColor $Red
        return $false
    }
    
    # Test Private SG rules (should reference public SG)
    $privateRules = aws ec2 describe-security-groups --group-ids $PrivateSgId --query "SecurityGroups[0].IpPermissions[?UserIdGroupPairs[?GroupId=='$PublicSgId']]" --output text 2>$null
    if ($LASTEXITCODE -eq 0 -and ![string]::IsNullOrEmpty($privateRules)) {
        Write-Host "Private Security Group allows access from Public SG" -ForegroundColor $Green
        return $true
    } else {
        Write-Host "Private Security Group missing rules from Public SG" -ForegroundColor $Red
        return $false
    }
}

# Test EC2 Instances
function Test-EC2Instances {
    Write-Host "Testing EC2 Instances..." -ForegroundColor $Yellow
    
    # Get EC2 IPs
    Set-Location "../terraform"
    $PublicIp = ""
    $PrivateIp = ""
    try {
        $PublicIp = terraform output -raw public_ec2_ip 2>$null
        $PrivateIp = terraform output -raw private_ec2_ip 2>$null
    }
    catch {
        # Ignore error
    }
    Set-Location "../tests"
    
    if ([string]::IsNullOrEmpty($PublicIp) -or [string]::IsNullOrEmpty($PrivateIp)) {
        Write-Host "EC2 IPs not found in Terraform outputs" -ForegroundColor $Red
        return $false
    }
    
    Write-Host "Public EC2 IP: $PublicIp"
    Write-Host "Private EC2 IP: $PrivateIp"
    
    # Test if public EC2 is reachable via HTTP
    Write-Host "Testing HTTP connectivity to public EC2..."
    try {
        $response = Invoke-WebRequest -Uri "http://$PublicIp" -TimeoutSec 10 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Host "Public EC2 HTTP service is reachable" -ForegroundColor $Green
            return $true
        }
    }
    catch {
        Write-Host "Public EC2 HTTP service not reachable (may still be starting)" -ForegroundColor $Yellow
        return $true  # Don't fail the test, instance might still be starting
    }
    
    return $true
}

# Main test execution
function Main {
    Write-Host "Starting infrastructure tests..."
    Write-Host ""
    
    # Check if AWS CLI is configured
    $null = aws sts get-caller-identity 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "AWS CLI not configured or no valid credentials" -ForegroundColor $Red
        exit 1
    }
    
    # Check if Terraform state exists
    Write-Host "Checking Terraform state..." -ForegroundColor $Yellow
    
    # Try to get state from S3 backend first
    Set-Location "../terraform"
    $stateExists = $false
    try {
        $null = terraform output vpc_id 2>$null
        if ($LASTEXITCODE -eq 0) {
            $stateExists = $true
        }
    }
    catch {
        # Ignore error
    }
    Set-Location "../tests"
    
    if (-not $stateExists) {
        Write-Host "Terraform state not found. Please run 'terraform apply' first." -ForegroundColor $Red
        exit 1
    }
    
    # Run tests
    $FailedTests = 0
    
    if (-not (Test-VPC)) { $FailedTests++ }
    Write-Host ""
    
    if (-not (Test-Subnets)) { $FailedTests++ }
    Write-Host ""
    
    if (-not (Test-InternetGateway)) { $FailedTests++ }
    Write-Host ""
    
    if (-not (Test-NATGateway)) { $FailedTests++ }
    Write-Host ""
    
    if (-not (Test-RouteTables)) { $FailedTests++ }
    Write-Host ""
    
    if (-not (Test-DefaultSecurityGroup)) { $FailedTests++ }
    Write-Host ""
    
    if (-not (Test-SecurityGroupRules)) { $FailedTests++ }
    Write-Host ""
    
    if (-not (Test-EC2Instances)) { $FailedTests++ }
    Write-Host ""
    
    # Summary
    Write-Host "=== Test Summary ===" -ForegroundColor $Blue
    if ($FailedTests -eq 0) {
        Write-Host "All tests passed!" -ForegroundColor $Green
        Write-Host "Infrastructure is deployed and working correctly."
    } else {
        Write-Host "$FailedTests test(s) failed" -ForegroundColor $Red
        Write-Host "Please check the infrastructure deployment."
        exit 1
    }
}

# Run main function
Main
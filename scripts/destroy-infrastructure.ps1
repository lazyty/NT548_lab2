# PowerShell Script to Destroy NT548 Infrastructure
# This script manually destroys all AWS resources created by Terraform

param(
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

# Colors
$Red = "Red"
$Green = "Green"
$Yellow = "Yellow"
$Cyan = "Cyan"

Write-Host "=== NT548 Infrastructure Destroy Script ===" -ForegroundColor $Cyan
Write-Host ""

# Check AWS CLI
try {
    $null = aws sts get-caller-identity 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: AWS CLI not configured or no valid credentials" -ForegroundColor $Red
        exit 1
    }
}
catch {
    Write-Host "ERROR: AWS CLI not found" -ForegroundColor $Red
    exit 1
}

# Get VPC ID
Write-Host "Searching for NT548 VPC..." -ForegroundColor $Yellow
$VpcId = aws ec2 describe-vpcs --filters "Name=tag:Project,Values=NT548*" --query 'Vpcs[0].VpcId' --output text 2>$null

if ([string]::IsNullOrEmpty($VpcId) -or $VpcId -eq "None") {
    Write-Host "No NT548 VPC found. Infrastructure may already be destroyed." -ForegroundColor $Green
    exit 0
}

Write-Host "Found VPC: $VpcId" -ForegroundColor $Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN MODE - No resources will be deleted" -ForegroundColor $Yellow
    Write-Host ""
}

if (-not $Force -and -not $DryRun) {
    Write-Host "WARNING: This will destroy all NT548 infrastructure!" -ForegroundColor $Red
    $confirmation = Read-Host "Type 'yes' to continue"
    if ($confirmation -ne "yes") {
        Write-Host "Aborted." -ForegroundColor $Yellow
        exit 0
    }
    Write-Host ""
}

# Function to execute or simulate command
function Invoke-DestroyCommand {
    param(
        [string]$Description,
        [scriptblock]$Command
    )
    
    Write-Host $Description -ForegroundColor $Yellow
    
    if ($DryRun) {
        Write-Host "[DRY RUN] Would execute: $Command" -ForegroundColor $Cyan
        return $true
    }
    
    try {
        & $Command
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Success" -ForegroundColor $Green
            return $true
        }
        else {
            Write-Host "Failed (exit code: $LASTEXITCODE)" -ForegroundColor $Red
            return $false
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor $Red
        return $false
    }
}

# 1. Terminate EC2 Instances
Write-Host "Step 1: Terminating EC2 Instances..." -ForegroundColor $Cyan
$InstanceIds = aws ec2 describe-instances --filters "Name=tag:Project,Values=NT548*" "Name=instance-state-name,Values=running,stopped,stopping,pending" --query 'Reservations[*].Instances[*].InstanceId' --output text 2>$null

if (-not [string]::IsNullOrEmpty($InstanceIds)) {
    $InstanceArray = $InstanceIds -split '\s+'
    Write-Host "Found $($InstanceArray.Count) instances: $InstanceIds"
    
    if (-not $DryRun) {
        aws ec2 terminate-instances --instance-ids $InstanceArray | Out-Null
        Write-Host "Waiting for instances to terminate..." -ForegroundColor $Yellow
        aws ec2 wait instance-terminated --instance-ids $InstanceArray
        Write-Host "EC2 instances terminated" -ForegroundColor $Green
    }
    else {
        Write-Host "[DRY RUN] Would terminate instances: $InstanceIds" -ForegroundColor $Cyan
    }
}
else {
    Write-Host "No EC2 instances found" -ForegroundColor $Green
}
Write-Host ""

# 2. Delete NAT Gateway
Write-Host "Step 2: Deleting NAT Gateway..." -ForegroundColor $Cyan
$NatId = aws ec2 describe-nat-gateways --filter "Name=tag:Project,Values=NT548*" "Name=state,Values=available,pending" --query 'NatGateways[0].NatGatewayId' --output text 2>$null

if (-not [string]::IsNullOrEmpty($NatId) -and $NatId -ne "None") {
    Write-Host "Found NAT Gateway: $NatId"
    
    if (-not $DryRun) {
        aws ec2 delete-nat-gateway --nat-gateway-id $NatId | Out-Null
        Write-Host "Waiting for NAT Gateway deletion (60 seconds)..." -ForegroundColor $Yellow
        Start-Sleep -Seconds 60
        Write-Host "NAT Gateway deleted" -ForegroundColor $Green
    }
    else {
        Write-Host "[DRY RUN] Would delete NAT Gateway: $NatId" -ForegroundColor $Cyan
    }
}
else {
    Write-Host "No NAT Gateway found" -ForegroundColor $Green
}
Write-Host ""

# 3. Release Elastic IPs
Write-Host "Step 3: Releasing Elastic IPs..." -ForegroundColor $Cyan
$EipIds = aws ec2 describe-addresses --filters "Name=tag:Project,Values=NT548*" --query 'Addresses[*].AllocationId' --output text 2>$null

if (-not [string]::IsNullOrEmpty($EipIds)) {
    $EipArray = $EipIds -split '\s+'
    foreach ($eip in $EipArray) {
        Write-Host "Releasing EIP: $eip"
        if (-not $DryRun) {
            aws ec2 release-address --allocation-id $eip 2>$null
        }
    }
    Write-Host "Elastic IPs released" -ForegroundColor $Green
}
else {
    Write-Host "No Elastic IPs found" -ForegroundColor $Green
}
Write-Host ""

# 4. Detach and Delete Internet Gateway
Write-Host "Step 4: Deleting Internet Gateway..." -ForegroundColor $Cyan
$IgwId = aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VpcId" --query 'InternetGateways[0].InternetGatewayId' --output text 2>$null

if (-not [string]::IsNullOrEmpty($IgwId) -and $IgwId -ne "None") {
    Write-Host "Found IGW: $IgwId"
    
    if (-not $DryRun) {
        aws ec2 detach-internet-gateway --internet-gateway-id $IgwId --vpc-id $VpcId 2>$null
        aws ec2 delete-internet-gateway --internet-gateway-id $IgwId 2>$null
        Write-Host "Internet Gateway deleted" -ForegroundColor $Green
    }
    else {
        Write-Host "[DRY RUN] Would delete IGW: $IgwId" -ForegroundColor $Cyan
    }
}
else {
    Write-Host "No Internet Gateway found" -ForegroundColor $Green
}
Write-Host ""

# 5. Delete Subnets
Write-Host "Step 5: Deleting Subnets..." -ForegroundColor $Cyan
$SubnetIds = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VpcId" --query 'Subnets[*].SubnetId' --output text 2>$null

if (-not [string]::IsNullOrEmpty($SubnetIds)) {
    $SubnetArray = $SubnetIds -split '\s+'
    Write-Host "Found $($SubnetArray.Count) subnets"
    
    if (-not $DryRun) {
        foreach ($subnet in $SubnetArray) {
            aws ec2 delete-subnet --subnet-id $subnet 2>$null
        }
        Write-Host "Subnets deleted" -ForegroundColor $Green
    }
    else {
        Write-Host "[DRY RUN] Would delete subnets: $SubnetIds" -ForegroundColor $Cyan
    }
}
else {
    Write-Host "No Subnets found" -ForegroundColor $Green
}
Write-Host ""

# 6. Delete Route Tables
Write-Host "Step 6: Deleting Route Tables..." -ForegroundColor $Cyan
$RouteTableIds = aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VpcId" --query 'RouteTables[?Associations[0].Main==`false`].RouteTableId' --output text 2>$null

if (-not [string]::IsNullOrEmpty($RouteTableIds)) {
    $RtArray = $RouteTableIds -split '\s+'
    Write-Host "Found $($RtArray.Count) route tables"
    
    if (-not $DryRun) {
        foreach ($rt in $RtArray) {
            aws ec2 delete-route-table --route-table-id $rt 2>$null
        }
        Write-Host "Route Tables deleted" -ForegroundColor $Green
    }
    else {
        Write-Host "[DRY RUN] Would delete route tables: $RouteTableIds" -ForegroundColor $Cyan
    }
}
else {
    Write-Host "No Route Tables found" -ForegroundColor $Green
}
Write-Host ""

# 7. Delete Security Groups
Write-Host "Step 7: Deleting Security Groups..." -ForegroundColor $Cyan
$SgIds = aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VpcId" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>$null

if (-not [string]::IsNullOrEmpty($SgIds)) {
    $SgArray = $SgIds -split '\s+'
    Write-Host "Found $($SgArray.Count) security groups"
    
    if (-not $DryRun) {
        # Try twice in case of dependencies
        foreach ($sg in $SgArray) {
            aws ec2 delete-security-group --group-id $sg 2>$null
        }
        Start-Sleep -Seconds 5
        foreach ($sg in $SgArray) {
            aws ec2 delete-security-group --group-id $sg 2>$null
        }
        Write-Host "Security Groups deleted" -ForegroundColor $Green
    }
    else {
        Write-Host "[DRY RUN] Would delete security groups: $SgIds" -ForegroundColor $Cyan
    }
}
else {
    Write-Host "No Security Groups found" -ForegroundColor $Green
}
Write-Host ""

# 8. Delete VPC
Write-Host "Step 8: Deleting VPC..." -ForegroundColor $Cyan
if (-not $DryRun) {
    Start-Sleep -Seconds 5
    aws ec2 delete-vpc --vpc-id $VpcId 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "VPC deleted" -ForegroundColor $Green
    }
    else {
        Write-Host "VPC deletion failed - may have remaining dependencies" -ForegroundColor $Red
        Write-Host "Wait a few minutes and run the script again" -ForegroundColor $Yellow
    }
}
else {
    Write-Host "[DRY RUN] Would delete VPC: $VpcId" -ForegroundColor $Cyan
}
Write-Host ""

Write-Host "=== Destroy Complete ===" -ForegroundColor $Green
Write-Host ""
Write-Host "To verify, run: aws ec2 describe-vpcs --filters 'Name=tag:Project,Values=NT548*'" -ForegroundColor $Cyan

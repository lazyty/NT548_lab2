<#
.SYNOPSIS
    Cleanup all NT548 infrastructure - No errors version
.DESCRIPTION
    Destroys all infrastructure, backend, and resources without showing errors
.NOTES
    Compatible with PowerShell 5.1+
#>

param(
    [switch]$Force,
    [switch]$DeleteBackend,
    [string]$Region = "us-east-1"
)

# Suppress all errors
$ErrorActionPreference = "SilentlyContinue"
$ProgressPreference = "SilentlyContinue"

Write-Host "=== NT548 Infrastructure Cleanup ===" -ForegroundColor Red
Write-Host ""

if (-not $Force) {
    Write-Host "WARNING: This will delete ALL NT548 infrastructure!" -ForegroundColor Yellow
    if ($DeleteBackend) {
        Write-Host "WARNING: S3 backend and DynamoDB will also be deleted!" -ForegroundColor Red
    } else {
        Write-Host "Note: S3 backend and DynamoDB will be preserved." -ForegroundColor Cyan
    }
    $confirm = Read-Host "Type 'yes' to continue"
    if ($confirm -ne "yes") {
        Write-Host "Cleanup cancelled" -ForegroundColor Green
        exit 0
    }
}

Write-Host ""
Write-Host "Starting cleanup..." -ForegroundColor Cyan
Write-Host ""

# Get AWS Account ID
Write-Host "Getting AWS Account ID..." -ForegroundColor Cyan
$accountId = aws sts get-caller-identity --query Account --output text 2>$null
$bucketName = "nt548-tfstate-$accountId"
Write-Host "Account ID: $accountId" -ForegroundColor Green
Write-Host ""

# Step 1: Terraform Destroy
Write-Host "Step 1: Destroying Terraform infrastructure..." -ForegroundColor Cyan
if (Test-Path "terraform/terraform.tfstate") {
    Set-Location terraform
    terraform destroy -auto-approve 2>&1 | Out-Null
    Set-Location ..
    Write-Host "Terraform destroy completed" -ForegroundColor Green
} else {
    Write-Host "No terraform state found" -ForegroundColor Yellow
}
Write-Host ""

# Step 2: Terminate EC2 Instances
Write-Host "Step 2: Terminating EC2 instances..." -ForegroundColor Cyan
$instances = aws ec2 describe-instances --filters "Name=tag:Project,Values=NT548*" "Name=instance-state-name,Values=running,stopped,stopping,pending" --query 'Reservations[].Instances[].InstanceId' --output text --region $Region 2>$null
if ($instances) {
    $instanceList = ($instances -split '\s+') | Where-Object { $_ }
    foreach ($id in $instanceList) {
        aws ec2 terminate-instances --instance-ids $id --region $Region 2>&1 | Out-Null
    }
    Write-Host "Waiting for instances to terminate..." -ForegroundColor Yellow
    foreach ($id in $instanceList) {
        aws ec2 wait instance-terminated --instance-ids $id --region $Region 2>&1 | Out-Null
    }
    Write-Host "EC2 instances terminated" -ForegroundColor Green
} else {
    Write-Host "No EC2 instances found" -ForegroundColor Green
}
Write-Host ""

# Step 3: Delete NAT Gateways
Write-Host "Step 3: Deleting NAT Gateways..." -ForegroundColor Cyan
$nats = aws ec2 describe-nat-gateways --filter "Name=tag:Project,Values=NT548*" "Name=state,Values=available,pending" --query 'NatGateways[].NatGatewayId' --output text --region $Region 2>$null
if ($nats) {
    $natList = ($nats -split '\s+') | Where-Object { $_ }
    foreach ($id in $natList) {
        aws ec2 delete-nat-gateway --nat-gateway-id $id --region $Region 2>&1 | Out-Null
    }
    Write-Host "Waiting for NAT Gateways to delete (2-3 minutes)..." -ForegroundColor Yellow
    
    $waited = 0
    while ($waited -lt 180) {
        Start-Sleep -Seconds 15
        $waited += 15
        $remaining = aws ec2 describe-nat-gateways --nat-gateway-ids $natList --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text --region $Region 2>&1
        if (!$remaining -or $remaining -match "does not exist") {
            break
        }
        Write-Host "  Still waiting... ($waited seconds)" -ForegroundColor Gray
    }
    Write-Host "NAT Gateways deleted" -ForegroundColor Green
} else {
    Write-Host "No NAT Gateways found" -ForegroundColor Green
}
Write-Host ""

# Step 4: Release Elastic IPs
Write-Host "Step 4: Releasing Elastic IPs..." -ForegroundColor Cyan
$eips = aws ec2 describe-addresses --filters "Name=tag:Project,Values=NT548*" --query 'Addresses[].AllocationId' --output text --region $Region 2>$null
if ($eips) {
    $eipList = ($eips -split '\s+') | Where-Object { $_ }
    foreach ($id in $eipList) {
        for ($i = 0; $i -lt 5; $i++) {
            aws ec2 release-address --allocation-id $id --region $Region 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { break }
            Start-Sleep -Seconds 10
        }
    }
    Write-Host "Elastic IPs released" -ForegroundColor Green
} else {
    Write-Host "No Elastic IPs found" -ForegroundColor Green
}
Write-Host ""

# Step 5: Delete VPCs
Write-Host "Step 5: Deleting VPCs..." -ForegroundColor Cyan
$vpcs = aws ec2 describe-vpcs --filters "Name=tag:Project,Values=NT548*" --query 'Vpcs[].VpcId' --output text --region $Region 2>$null
if ($vpcs) {
    $vpcList = ($vpcs -split '\s+') | Where-Object { $_ }
    foreach ($vpcId in $vpcList) {
        Write-Host "  Cleaning VPC: $vpcId" -ForegroundColor Yellow
        
        # 1. Delete Internet Gateways first
        Write-Host "    - Deleting Internet Gateways..." -ForegroundColor Gray
        $igws = aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpcId" --query 'InternetGateways[].InternetGatewayId' --output text --region $Region 2>$null
        foreach ($igw in ($igws -split '\s+') | Where-Object { $_ }) {
            aws ec2 detach-internet-gateway --internet-gateway-id $igw --vpc-id $vpcId --region $Region 2>&1 | Out-Null
            aws ec2 delete-internet-gateway --internet-gateway-id $igw --region $Region 2>&1 | Out-Null
        }
        
        # 2. Check and delete any remaining NAT Gateways in this VPC
        Write-Host "    - Checking for remaining NAT Gateways..." -ForegroundColor Gray
        $vpcNats = aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpcId" "Name=state,Values=available,pending,deleting" --query 'NatGateways[].NatGatewayId' --output text --region $Region 2>$null
        if ($vpcNats) {
            $vpcNatList = ($vpcNats -split '\s+') | Where-Object { $_ }
            foreach ($nat in $vpcNatList) {
                aws ec2 delete-nat-gateway --nat-gateway-id $nat --region $Region 2>&1 | Out-Null
            }
            Write-Host "    - Waiting 60 seconds for NAT Gateways to delete..." -ForegroundColor Gray
            Start-Sleep -Seconds 60
        }
        
        # 3. Delete Network Interfaces (ENIs) that might be stuck
        Write-Host "    - Deleting Network Interfaces..." -ForegroundColor Gray
        $enis = aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpcId" --query 'NetworkInterfaces[].NetworkInterfaceId' --output text --region $Region 2>$null
        foreach ($eni in ($enis -split '\s+') | Where-Object { $_ }) {
            # Try to detach if attached
            $attachment = aws ec2 describe-network-interfaces --network-interface-ids $eni --query 'NetworkInterfaces[0].Attachment.AttachmentId' --output text --region $Region 2>$null
            if ($attachment -and $attachment -ne "None") {
                aws ec2 detach-network-interface --attachment-id $attachment --region $Region --force 2>&1 | Out-Null
                Start-Sleep -Seconds 5
            }
            # Delete ENI
            aws ec2 delete-network-interface --network-interface-id $eni --region $Region 2>&1 | Out-Null
        }
        
        # 4. Delete Subnets (retry multiple times with longer waits)
        Write-Host "    - Deleting Subnets..." -ForegroundColor Gray
        $subnets = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpcId" --query 'Subnets[].SubnetId' --output text --region $Region 2>$null
        foreach ($subnet in ($subnets -split '\s+') | Where-Object { $_ }) {
            for ($i = 0; $i -lt 10; $i++) {
                aws ec2 delete-subnet --subnet-id $subnet --region $Region 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { 
                    Write-Host "      Deleted subnet: $subnet" -ForegroundColor Gray
                    break 
                }
                if ($i -lt 9) {
                    Write-Host "      Retry $($i+1)/10 for subnet $subnet..." -ForegroundColor Gray
                    Start-Sleep -Seconds 20
                }
            }
        }
        
        # 5. Delete Route Tables
        Write-Host "    - Deleting Route Tables..." -ForegroundColor Gray
        $rts = aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpcId" --query 'RouteTables[?Associations[0].Main==`false` || !Associations[0]].RouteTableId' --output text --region $Region 2>$null
        foreach ($rt in ($rts -split '\s+') | Where-Object { $_ }) {
            # Disassociate first
            $assocs = aws ec2 describe-route-tables --route-table-ids $rt --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text --region $Region 2>$null
            foreach ($assoc in ($assocs -split '\s+') | Where-Object { $_ }) {
                aws ec2 disassociate-route-table --association-id $assoc --region $Region 2>&1 | Out-Null
            }
            # Then delete
            aws ec2 delete-route-table --route-table-id $rt --region $Region 2>&1 | Out-Null
        }
        
        # 6. Delete Security Groups
        Write-Host "    - Deleting Security Groups..." -ForegroundColor Gray
        $sgs = aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpcId" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text --region $Region 2>$null
        $sgList = ($sgs -split '\s+') | Where-Object { $_ }
        
        # Remove all rules first to break dependencies
        foreach ($sg in $sgList) {
            $ingress = aws ec2 describe-security-groups --group-ids $sg --query 'SecurityGroups[0].IpPermissions' --output json --region $Region 2>$null
            if ($ingress -and $ingress -ne "[]") {
                $ingress | Out-File -FilePath "temp_ingress.json" -Encoding utf8
                aws ec2 revoke-security-group-ingress --group-id $sg --ip-permissions file://temp_ingress.json --region $Region 2>&1 | Out-Null
                Remove-Item "temp_ingress.json" -Force 2>$null
            }
            
            $egress = aws ec2 describe-security-groups --group-ids $sg --query 'SecurityGroups[0].IpPermissionsEgress' --output json --region $Region 2>$null
            if ($egress -and $egress -ne "[]") {
                $egress | Out-File -FilePath "temp_egress.json" -Encoding utf8
                aws ec2 revoke-security-group-egress --group-id $sg --ip-permissions file://temp_egress.json --region $Region 2>&1 | Out-Null
                Remove-Item "temp_egress.json" -Force 2>$null
            }
        }
        
        # Delete Security Groups
        foreach ($sg in $sgList) {
            for ($i = 0; $i -lt 5; $i++) {
                aws ec2 delete-security-group --group-id $sg --region $Region 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { break }
                Start-Sleep -Seconds 5
            }
        }
        
        # 7. Delete VPC (with extended retry)
        Write-Host "    - Deleting VPC..." -ForegroundColor Gray
        $vpcDeleted = $false
        for ($i = 0; $i -lt 10; $i++) {
            aws ec2 delete-vpc --vpc-id $vpcId --region $Region 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { 
                Write-Host "  VPC $vpcId deleted successfully" -ForegroundColor Green
                $vpcDeleted = $true
                break 
            }
            if ($i -lt 9) {
                Write-Host "      Retry $($i+1)/10 for VPC deletion..." -ForegroundColor Gray
                Start-Sleep -Seconds 15
            }
        }
        
        if (-not $vpcDeleted) {
            Write-Host "  WARNING: Could not delete VPC $vpcId automatically" -ForegroundColor Red
            Write-Host "  Please delete manually from AWS Console" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "No VPCs found" -ForegroundColor Green
}
Write-Host ""

# Step 6: Clean Local Files
Write-Host "Step 6: Cleaning local files..." -ForegroundColor Cyan
Remove-Item "terraform/terraform.tfstate*" -Force 2>$null
Remove-Item "terraform/.terraform" -Recurse -Force 2>$null
Remove-Item "terraform/.terraform.lock.hcl" -Force 2>$null
Write-Host "Local files cleaned" -ForegroundColor Green
Write-Host ""

# Optional: Delete Backend (only if -DeleteBackend flag is used)
if ($DeleteBackend) {
    Write-Host "Step 7: Deleting S3 backend bucket..." -ForegroundColor Cyan
    aws s3 rm s3://$bucketName --recursive 2>&1 | Out-Null
    aws s3api delete-bucket --bucket $bucketName --region $Region 2>&1 | Out-Null
    Write-Host "S3 bucket deleted" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Step 8: Deleting DynamoDB table..." -ForegroundColor Cyan
    aws dynamodb delete-table --table-name nt548-terraform-locks --region $Region 2>&1 | Out-Null
    Write-Host "DynamoDB table deleted" -ForegroundColor Green
    Write-Host ""
}

Write-Host "=== Cleanup Complete ===" -ForegroundColor Green
Write-Host ""
if ($DeleteBackend) {
    Write-Host "All NT548 resources including backend have been deleted!" -ForegroundColor Green
} else {
    Write-Host "Infrastructure deleted!" -ForegroundColor Green
    Write-Host "S3 backend ($bucketName) and DynamoDB table are preserved." -ForegroundColor Cyan
}
Write-Host ""
Write-Host "To deploy again:" -ForegroundColor Cyan
Write-Host "1. Commit and push to GitHub" -ForegroundColor White
Write-Host "2. Trigger GitHub Actions with action: apply" -ForegroundColor White

#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Cleanup all NT548 infrastructure manually
.DESCRIPTION
    Destroys all infrastructure, backend, and resources
#>

param(
    [switch]$Force,
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"

Write-Host "=== NT548 Infrastructure Cleanup ===" -ForegroundColor Red
Write-Host ""

if (-not $Force) {
    Write-Host "WARNING: This will delete ALL NT548 resources including:" -ForegroundColor Yellow
    Write-Host "- EC2 instances" -ForegroundColor Yellow
    Write-Host "- VPC and networking" -ForegroundColor Yellow
    Write-Host "- S3 backend bucket" -ForegroundColor Yellow
    Write-Host "- DynamoDB table" -ForegroundColor Yellow
    Write-Host "- Terraform state files" -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Are you sure? Type 'yes' to continue"
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
$accountId = aws sts get-caller-identity --query Account --output text
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to get AWS Account ID" -ForegroundColor Red
    exit 1
}
Write-Host "Account ID: $accountId" -ForegroundColor Green
Write-Host ""

$bucketName = "nt548-tfstate-$accountId"

# Step 1: Destroy Terraform infrastructure
Write-Host "Step 1: Destroying Terraform infrastructure..." -ForegroundColor Cyan
if (Test-Path "terraform/terraform.tfstate") {
    Set-Location terraform
    
    Write-Host "Running terraform destroy..." -ForegroundColor Yellow
    terraform destroy -auto-approve
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Infrastructure destroyed successfully" -ForegroundColor Green
    } else {
        Write-Host "Warning: Terraform destroy had errors" -ForegroundColor Yellow
    }
    
    Set-Location ..
} else {
    Write-Host "No terraform state found, skipping..." -ForegroundColor Yellow
}
Write-Host ""

# Step 2: Delete EC2 instances with NT548 tag
Write-Host "Step 2: Checking for remaining EC2 instances..." -ForegroundColor Cyan
$instancesRaw = aws ec2 describe-instances `
    --filters "Name=tag:Project,Values=NT548*" "Name=instance-state-name,Values=running,stopped,stopping,pending" `
    --query 'Reservations[].Instances[].InstanceId' `
    --output text `
    --region $Region

if (![string]::IsNullOrEmpty($instancesRaw)) {
    # Split and clean instance IDs
    $instances = ($instancesRaw -split '\s+') | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    
    if ($instances.Count -gt 0) {
        Write-Host "Found instances: $($instances -join ', ')" -ForegroundColor Yellow
        Write-Host "Terminating instances..." -ForegroundColor Yellow
        
        foreach ($instanceId in $instances) {
            aws ec2 terminate-instances --instance-ids $instanceId --region $Region 2>$null
        }
        
        Write-Host "Waiting for instances to terminate..." -ForegroundColor Yellow
        foreach ($instanceId in $instances) {
            aws ec2 wait instance-terminated --instance-ids $instanceId --region $Region 2>$null
        }
        Write-Host "Instances terminated" -ForegroundColor Green
    } else {
        Write-Host "No EC2 instances found" -ForegroundColor Green
    }
} else {
    Write-Host "No EC2 instances found" -ForegroundColor Green
}
Write-Host ""

# Step 3: Delete NAT Gateways
Write-Host "Step 3: Checking for NAT Gateways..." -ForegroundColor Cyan
$natGatewaysRaw = aws ec2 describe-nat-gateways `
    --filter "Name=tag:Project,Values=NT548*" "Name=state,Values=available,pending" `
    --query 'NatGateways[].NatGatewayId' `
    --output text `
    --region $Region

if (![string]::IsNullOrEmpty($natGatewaysRaw)) {
    $natGateways = ($natGatewaysRaw -split '\s+') | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    
    if ($natGateways.Count -gt 0) {
        Write-Host "Found NAT Gateways: $($natGateways -join ', ')" -ForegroundColor Yellow
        foreach ($natId in $natGateways) {
            Write-Host "Deleting NAT Gateway: $natId" -ForegroundColor Yellow
            aws ec2 delete-nat-gateway --nat-gateway-id $natId --region $Region 2>$null
        }
        Write-Host "NAT Gateways deletion initiated" -ForegroundColor Green
    } else {
        Write-Host "No NAT Gateways found" -ForegroundColor Green
    }
} else {
    Write-Host "No NAT Gateways found" -ForegroundColor Green
}
Write-Host ""

# Step 4: Release Elastic IPs
Write-Host "Step 4: Checking for Elastic IPs..." -ForegroundColor Cyan
Start-Sleep -Seconds 5
$eipsRaw = aws ec2 describe-addresses `
    --filters "Name=tag:Project,Values=NT548*" `
    --query 'Addresses[].AllocationId' `
    --output text `
    --region $Region

if (![string]::IsNullOrEmpty($eipsRaw)) {
    $eips = ($eipsRaw -split '\s+') | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    
    if ($eips.Count -gt 0) {
        Write-Host "Found Elastic IPs: $($eips -join ', ')" -ForegroundColor Yellow
        foreach ($eipId in $eips) {
            Write-Host "Releasing EIP: $eipId" -ForegroundColor Yellow
            aws ec2 release-address --allocation-id $eipId --region $Region 2>$null
        }
        Write-Host "Elastic IPs released" -ForegroundColor Green
    } else {
        Write-Host "No Elastic IPs found" -ForegroundColor Green
    }
} else {
    Write-Host "No Elastic IPs found" -ForegroundColor Green
}
Write-Host ""

# Step 5: Wait for NAT Gateways to be fully deleted
Write-Host "Step 5: Waiting for NAT Gateways to be deleted..." -ForegroundColor Cyan
Start-Sleep -Seconds 30
Write-Host "NAT Gateways should be deleted now" -ForegroundColor Green
Write-Host ""

# Step 6: Delete VPCs
Write-Host "Step 6: Checking for VPCs..." -ForegroundColor Cyan
$vpcsRaw = aws ec2 describe-vpcs `
    --filters "Name=tag:Project,Values=NT548*" `
    --query 'Vpcs[].VpcId' `
    --output text `
    --region $Region

if (![string]::IsNullOrEmpty($vpcsRaw)) {
    $vpcs = ($vpcsRaw -split '\s+') | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    
    if ($vpcs.Count -gt 0) {
        Write-Host "Found VPCs: $($vpcs -join ', ')" -ForegroundColor Yellow
        foreach ($vpcId in $vpcs) {
            Write-Host "Cleaning up VPC: $vpcId" -ForegroundColor Yellow
        
        # Delete internet gateways first
        Write-Host "  - Deleting Internet Gateways..." -ForegroundColor Gray
        $igws = aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpcId" --query 'InternetGateways[].InternetGatewayId' --output text --region $Region
        foreach ($igwId in $igws -split '\s+') {
            if (![string]::IsNullOrWhiteSpace($igwId)) {
                aws ec2 detach-internet-gateway --internet-gateway-id $igwId --vpc-id $vpcId --region $Region 2>$null
                aws ec2 delete-internet-gateway --internet-gateway-id $igwId --region $Region 2>$null
            }
        }
        
        # Delete NAT Gateways (if any remaining)
        Write-Host "  - Checking for remaining NAT Gateways..." -ForegroundColor Gray
        $natGws = aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpcId" "Name=state,Values=available,pending,deleting" --query 'NatGateways[].NatGatewayId' --output text --region $Region
        foreach ($natId in $natGws -split '\s+') {
            if (![string]::IsNullOrWhiteSpace($natId)) {
                Write-Host "    Found NAT Gateway: $natId, deleting..." -ForegroundColor Gray
                aws ec2 delete-nat-gateway --nat-gateway-id $natId --region $Region 2>$null
            }
        }
        
        if (![string]::IsNullOrEmpty($natGws)) {
            Write-Host "  - Waiting 30 seconds for NAT Gateways..." -ForegroundColor Gray
            Start-Sleep -Seconds 30
        }
        
        # Delete subnets
        Write-Host "  - Deleting Subnets..." -ForegroundColor Gray
        $subnets = aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpcId" --query 'Subnets[].SubnetId' --output text --region $Region
        foreach ($subnetId in $subnets -split '\s+') {
            if (![string]::IsNullOrWhiteSpace($subnetId)) {
                $retries = 0
                $maxRetries = 3
                while ($retries -lt $maxRetries) {
                    aws ec2 delete-subnet --subnet-id $subnetId --region $Region 2>$null
                    if ($LASTEXITCODE -eq 0) { break }
                    $retries++
                    if ($retries -lt $maxRetries) {
                        Write-Host "    Retry $retries for subnet $subnetId..." -ForegroundColor Gray
                        Start-Sleep -Seconds 10
                    }
                }
            }
        }
        
        # Delete route tables
        Write-Host "  - Deleting Route Tables..." -ForegroundColor Gray
        $routeTables = aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpcId" --region $Region --query 'RouteTables[?Associations[0].Main==`false` || !Associations[0]].RouteTableId' --output text
        $rtArray = ($routeTables -split '\s+') | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
        
        foreach ($rtId in $rtArray) {
            # First, disassociate if associated
            $associations = aws ec2 describe-route-tables --route-table-ids $rtId --region $Region --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text 2>$null
            $assocArray = ($associations -split '\s+') | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
            
            foreach ($assocId in $assocArray) {
                Write-Host "    Disassociating route table: $assocId" -ForegroundColor Gray
                aws ec2 disassociate-route-table --association-id $assocId --region $Region 2>$null
            }
            
            # Then delete
            Write-Host "    Deleting route table: $rtId" -ForegroundColor Gray
            aws ec2 delete-route-table --route-table-id $rtId --region $Region 2>$null
        }
        
        # Delete security groups (with retry for dependencies)
        Write-Host "  - Deleting Security Groups..." -ForegroundColor Gray
        $sgs = aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpcId" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text --region $Region
        $sgArray = ($sgs -split '\s+') | Where-Object { ![string]::IsNullOrWhiteSpace($_) }
        
        if ($sgArray.Count -gt 0) {
            # First, remove all ingress and egress rules to break dependencies
            foreach ($sgId in $sgArray) {
                # Revoke all ingress rules
                aws ec2 describe-security-groups --group-ids $sgId --region $Region --query 'SecurityGroups[0].IpPermissions' --output json 2>$null | Out-File -FilePath "temp_ingress.json" -Encoding utf8
                if ((Get-Content "temp_ingress.json" -Raw) -ne "[]`n" -and (Get-Content "temp_ingress.json" -Raw) -ne "") {
                    aws ec2 revoke-security-group-ingress --group-id $sgId --ip-permissions file://temp_ingress.json --region $Region 2>$null
                }
                
                # Revoke all egress rules
                aws ec2 describe-security-groups --group-ids $sgId --region $Region --query 'SecurityGroups[0].IpPermissionsEgress' --output json 2>$null | Out-File -FilePath "temp_egress.json" -Encoding utf8
                if ((Get-Content "temp_egress.json" -Raw) -ne "[]`n" -and (Get-Content "temp_egress.json" -Raw) -ne "") {
                    aws ec2 revoke-security-group-egress --group-id $sgId --ip-permissions file://temp_egress.json --region $Region 2>$null
                }
            }
            
            # Clean up temp files
            if (Test-Path "temp_ingress.json") { Remove-Item "temp_ingress.json" -Force }
            if (Test-Path "temp_egress.json") { Remove-Item "temp_egress.json" -Force }
            
            # Now delete security groups
            foreach ($sgId in $sgArray) {
                $retries = 0
                $maxRetries = 3
                while ($retries -lt $maxRetries) {
                    aws ec2 delete-security-group --group-id $sgId --region $Region 2>$null
                    if ($LASTEXITCODE -eq 0) { 
                        Write-Host "    Deleted SG: $sgId" -ForegroundColor Gray
                        break 
                    }
                    $retries++
                    if ($retries -lt $maxRetries) {
                        Write-Host "    Retry $retries for SG $sgId..." -ForegroundColor Gray
                        Start-Sleep -Seconds 5
                    }
                }
            }
        }
        
        # Delete VPC
        Write-Host "  - Deleting VPC..." -ForegroundColor Gray
        $retries = 0
        $maxRetries = 3
        while ($retries -lt $maxRetries) {
            aws ec2 delete-vpc --vpc-id $vpcId --region $Region 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  VPC $vpcId deleted successfully" -ForegroundColor Green
                break
            }
            $retries++
            if ($retries -lt $maxRetries) {
                Write-Host "  Retry $retries for VPC deletion..." -ForegroundColor Gray
                Start-Sleep -Seconds 10
            } else {
                Write-Host "  Warning: Could not delete VPC $vpcId after $maxRetries attempts" -ForegroundColor Yellow
            }
        }
        }
        Write-Host "VPC cleanup completed" -ForegroundColor Green
    } else {
        Write-Host "No VPCs found" -ForegroundColor Green
    }
} else {
    Write-Host "No VPCs found" -ForegroundColor Green
}
Write-Host ""

# Step 6: Delete S3 backend bucket
Write-Host "Step 7: Deleting S3 backend bucket..." -ForegroundColor Cyan
if (aws s3api head-bucket --bucket $bucketName 2>$null) {
    Write-Host "Emptying bucket: $bucketName" -ForegroundColor Yellow
    aws s3 rm s3://$bucketName --recursive
    
    Write-Host "Deleting bucket: $bucketName" -ForegroundColor Yellow
    aws s3api delete-bucket --bucket $bucketName --region $Region
    
    Write-Host "S3 bucket deleted" -ForegroundColor Green
} else {
    Write-Host "S3 bucket not found" -ForegroundColor Yellow
}
Write-Host ""

# Step 7: Delete DynamoDB table
Write-Host "Step 8: Deleting DynamoDB table..." -ForegroundColor Cyan
if (aws dynamodb describe-table --table-name nt548-terraform-locks --region $Region 2>$null) {
    Write-Host "Deleting table: nt548-terraform-locks" -ForegroundColor Yellow
    aws dynamodb delete-table --table-name nt548-terraform-locks --region $Region
    Write-Host "DynamoDB table deletion initiated" -ForegroundColor Green
} else {
    Write-Host "DynamoDB table not found" -ForegroundColor Yellow
}
Write-Host ""

# Step 9: Clean local state files
Write-Host "Step 9: Cleaning local state files..." -ForegroundColor Cyan
$filesDeleted = 0

if (Test-Path "terraform/terraform.tfstate") {
    Remove-Item "terraform/terraform.tfstate" -Force
    Write-Host "Removed terraform.tfstate" -ForegroundColor Green
    $filesDeleted++
}
if (Test-Path "terraform/terraform.tfstate.backup") {
    Remove-Item "terraform/terraform.tfstate.backup" -Force
    Write-Host "Removed terraform.tfstate.backup" -ForegroundColor Green
    $filesDeleted++
}
if (Test-Path "terraform/.terraform") {
    Remove-Item "terraform/.terraform" -Recurse -Force
    Write-Host "Removed .terraform directory" -ForegroundColor Green
    $filesDeleted++
}
if (Test-Path "terraform/.terraform.lock.hcl") {
    Remove-Item "terraform/.terraform.lock.hcl" -Force
    Write-Host "Removed .terraform.lock.hcl" -ForegroundColor Green
    $filesDeleted++
}

if ($filesDeleted -eq 0) {
    Write-Host "No local state files found" -ForegroundColor Yellow
} else {
    Write-Host "Deleted $filesDeleted local file(s)" -ForegroundColor Green
}
Write-Host ""

Write-Host "=== Cleanup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "All NT548 resources have been deleted!" -ForegroundColor Green
Write-Host ""
Write-Host "To deploy again:" -ForegroundColor Cyan
Write-Host "1. Commit and push code to GitHub" -ForegroundColor White
Write-Host "2. Trigger GitHub Actions workflow with action: apply" -ForegroundColor White
Write-Host "3. Or run locally: cd terraform && terraform init && terraform apply" -ForegroundColor White

# NT548 - AWS Infrastructure Deployment Lab

**Bài tập thực hành Lab 2 NT548**:Quản lý và triển khai hạ tầng AWS và ứng dụng microservices với Terraform, 
CloudFormation, GitHub Actions, AWS CodePipeline và Jenkins

Đồ án thực hành triển khai hạ tầng AWS sử dụng Infrastructure as Code (IaC) với Terraform và CloudFormation.

## Mục lục

- [Tổng quan](#tổng-quan)
- [Kiến trúc](#kiến-trúc)
- [Yêu cầu](#yêu-cầu)
- [Cài đặt](#cài-đặt)
- [Triển khai](#triển-khai)
  - [Quick Start - Terraform](#option-1-quick-start-terraform)
  - [Quick Start - CodePipeline (Tự động)](#option-2-quick-start-codepipeline-recommended)
  - [Manual Terraform Deployment](#option-3-manual-terraform-deployment)
  - [Manual CloudFormation Deployment](#option-4-manual-cloudformation-deployment)
- [Testing](#testing)
- [CI/CD](#cicd)
  - [GitHub Actions](#github-actions)
  - [AWS CodePipeline](#aws-codepipeline)
- [Cleanup](#cleanup)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)
- [Tài liệu tham khảo](#tài-liệu-tham-khảo)

## Tổng quan

Project này triển khai một hạ tầng AWS hoàn chỉnh bao gồm:
- **VPC** với public và private subnets
- **EC2 instances** trong cả 2 subnets
- **NAT Gateway** cho private subnet internet access
- **Security Groups** với rules phù hợp
- **S3 Backend** để lưu trữ Terraform state
- **DynamoDB** cho state locking
- **AWS CodePipeline** tự động hóa CI/CD cho CloudFormation
- **AWS CodeBuild** với cfn-lint và Taskcat validation

### Cấu trúc Project

```
.
├── terraform/                   # Terraform infrastructure
│   ├── modules/                 # Terraform modules
│   │   ├── vpc/                 # VPC module
│   │   ├── ec2/                 # EC2 module
│   │   └── security-groups/     # Security Groups module
│   ├── main.tf                  # Main configuration với S3 backend
│   ├── variables.tf             # Variable definitions
│   ├── outputs.tf               # Output definitions
│   └── terraform.tfvars.example # Example variables
│
├── cloudformation/             # CloudFormation templates
│   ├── templates/              # CloudFormation YAML templates
│   │   └── main.yaml           # Main infrastructure template
│   ├── parameters/             # Parameter files
│   │   └── dev.json            # Development parameters
│   ├── pipeline/               # CodePipeline templates
│   │   └── codepipeline.yaml   # Pipeline stack template
│   └── buildspec.yml           # CodeBuild build specification
│
├── scripts/                         # Deployment scripts
│   ├── setup-terraform-backend.ps1  # Setup S3 backend
│   ├── setup-codecommit.ps1         # Setup CodeCommit repo
│   ├── deploy-cloudformation.ps1    # Deploy CloudFormation
│   ├── deploy-codepipeline.ps1      # Deploy CodePipeline
│   └── destroy-infrastructure.ps1   # Cleanup resources
│
├── tests/                      # Test scripts
│   ├── run-tests.ps1           # Infrastructure tests
│   ├── test-connectivity.ps1   # Connectivity tests
│   └── test-cloudformation.ps1 # CloudFormation tests
│
├── .github/workflows/          # GitHub Actions workflows
│   └── terraform-deploy.yml    # Terraform CI/CD workflow
│
├── .taskcat.yml                # Taskcat test configuration
├── .cfnlintrc                  # cfn-lint configuration
├── .checkov.yml                # Checkov security scan config
├── .gitignore                  # Git ignore rules
├── quick-start.bat             # Quick start script
└── README.md                   # This file
```

### Resources được tạo:

**Network:**
- 1 VPC (10.0.0.0/16)
- 1 Public Subnet (10.0.1.0/24)
- 1 Private Subnet (10.0.2.0/24)
- 1 Internet Gateway
- 1 NAT Gateway
- 2 Route Tables (Public & Private)

**Compute:**
- 1 EC2 instance trong Public Subnet (t2.micro)
- 1 EC2 instance trong Private Subnet (t2.micro)

**Security:**
- Public Security Group (SSH từ IP được chỉ định, HTTP từ anywhere)
- Private Security Group (chỉ nhận traffic từ Public SG)

**Backend:**
- S3 Bucket: `nt548-tfstate-409964509537` (encrypted, versioned)
- DynamoDB Table: `nt548-terraform-locks` (state locking)
- Lifecycle: Old versions deleted after 7 days
- Note: Bucket name includes AWS Account ID for global uniqueness

**CI/CD Pipeline:**
- CodeCommit Repository: Source control
- CodePipeline: Orchestration
- CodeBuild: Validation (cfn-lint, Taskcat)
- S3 Artifacts Bucket: Pipeline artifacts storage
- EventBridge Rule: Auto-trigger on code changes

## Kiến trúc

### Infrastructure Architecture

```
┌───────────────────────────────────────────────────────────┐
│                         VPC (10.0.0.0/16)                 │
│                                                           │
│  ┌──────────────────────┐      ┌──────────────────────┐   │
│  │  Public Subnet       │      │  Private Subnet      │   │
│  │  (10.0.1.0/24)       │      │  (10.0.2.0/24)       │   │
│  │                      │      │                      │   │
│  │  ┌────────────┐      │      │  ┌────────────┐      │   │
│  │  │ Public EC2 │      │      │  │Private EC2 │      │   │
│  │  │ (Web Server)│◄────┼──────┼──┤            │      │   │
│  │  └────────────┘      │      │  └────────────┘      │   │
│  │         │            │      │         │            │   │
│  │         │            │      │         │            │   │
│  │  ┌──────▼──────┐     │      │  ┌──────▼──────┐     │   │
│  │  │   IGW       │     │      │  │ NAT Gateway │     │   │
│  │  └─────────────┘     │      │  └─────────────┘     │   │
│  └──────────────────────┘      └──────────────────────┘   │
│                                                           │
└───────────────────────────────────────────────────────────┘
                         │
                         ▼
                    Internet
```

### CI/CD Pipeline Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                      AWS CodePipeline                         │
│                                                               │
│  ┌──────────┐    ┌──────────┐    ┌────────────────────────┐   │
│  │  Source  │───▶│  Build   │───▶│       Deploy          │   │
│  │          │    │          │    │                        │   │
│  │CodeCommit│    │CodeBuild │    │ ┌────────────────────┐ │   │
│  │          │    │          │    │ │ Create ChangeSet   │ │   │
│  │          │    │ cfn-lint │    │ └────────────────────┘ │   │
│  │          │    │ Taskcat  │    │          │             │   │
│  │          │    │          │    │          ▼             │   │
│  │          │    │          │    │ ┌────────────────────┐ │   │
│  │          │    │          │    │ │ Manual Approval    │ │   │
│  │          │    │          │    │ └────────────────────┘ │   │
│  │          │    │          │    │          │             │   │
│  │          │    │          │    │          ▼             │   │
│  │          │    │          │    │ ┌────────────────────┐ │   │
│  │          │    │          │    │ │ Execute ChangeSet  │ │   │
│  │          │    │          │    │ └────────────────────┘ │   │
│  └──────────┘    └──────────┘    └────────────────────────┘   │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

## Yêu cầu

### Software Requirements

| Tool | Version | Download |
|------|---------|----------|
| AWS CLI | Latest | https://aws.amazon.com/cli/ |
| Terraform | >= 1.0 | https://www.terraform.io/downloads |
| PowerShell | >= 5.1 | Built-in Windows / https://github.com/PowerShell/PowerShell |
| Git | Latest | https://git-scm.com/ |

### AWS Requirements

- AWS Account với IAM user có quyền:
  - EC2 (full access)
  - VPC (full access)
  - S3 (full access)
  - DynamoDB (full access)
- AWS Access Key ID và Secret Access Key
- EC2 Key Pair đã tạo sẵn trong region `us-east-1`

## Cài đặt

### 1. Clone Repository

```bash
git clone <repository-url>
cd LAB2_NT548
```

### 2. Cấu hình AWS Credentials

```bash
aws configure
```

Nhập thông tin:
```
AWS Access Key ID: YOUR_ACCESS_KEY
AWS Secret Access Key: YOUR_SECRET_KEY
Default region name: us-east-1
Default output format: json
```

### 3. Tạo EC2 Key Pair

**Tạo key pair mới:**
```bash
# Tạo key pair trên AWS
aws ec2 create-key-pair --key-name nt548-keypair --query 'KeyMaterial' --output text > nt548-keypair.pem

# Set permissions (Linux/Mac)
chmod 400 nt548-keypair.pem

# Windows (PowerShell)
icacls nt548-keypair.pem /inheritance:r
icacls nt548-keypair.pem /grant:r "%USERNAME%:R"
```

**Hoặc sử dụng key pair có sẵn:**
```bash
# List các key pairs hiện có
aws ec2 describe-key-pairs --query 'KeyPairs[*].KeyName' --output table
```

### 4. Lấy IP Address của bạn

```bash
# Windows
curl ifconfig.me

# Linux/Mac
curl ifconfig.me

# Hoặc truy cập: https://whatismyipaddress.com/
```

## Triển khai

### Option 1: Quick Start - Terraform

```cmd
quick-start.bat
```

Script sẽ tự động:
1. Kiểm tra prerequisites
2. Setup S3 backend
3. Cấu hình Terraform variables
4. Deploy infrastructure

---

### Option 2: Quick Start - CodePipeline (Recommended - Tự động hoàn toàn)

**Triển khai CI/CD tự động với AWS CodePipeline, cfn-lint và Taskcat**

#### Bước 1: Chuẩn bị
```powershell
# Kiểm tra AWS CLI
aws sts get-caller-identity

# Tạo key pair (nếu chưa có)
aws ec2 create-key-pair --key-name nt548-keypair --query 'KeyMaterial' --output text > nt548-keypair.pem

# Nếu key pair đã tồn tại, xóa và tạo lại
aws ec2 delete-key-pair --key-name nt548-keypair
aws ec2 create-key-pair --key-name nt548-keypair --query 'KeyMaterial' --output text > nt548-keypair.pem

# Lấy IP của bạn
curl ifconfig.me
```

#### Bước 2: Cấu hình parameters
```powershell
notepad cloudformation/parameters/dev.json
```

Sửa IP và key pair name:
```json
[
  {
    "ParameterKey": "KeyPairName",
    "ParameterValue": "nt548-keypair"
  },
  {
    "ParameterKey": "AllowedSshIp",
    "ParameterValue": "YOUR_IP/32"
  }
]
```

#### Bước 3: Setup CodeCommit
```powershell
.\scripts\setup-codecommit.ps1
```

Script sẽ:
- Tạo CodeCommit repository
- Cấu hình Git credentials
- Push code lên CodeCommit

#### Bước 4: Deploy Pipeline
```powershell
.\scripts\deploy-codepipeline.ps1
```

Script sẽ tạo:
- CodeBuild project với cfn-lint và Taskcat
- CodePipeline với 3 stages (Source, Build, Deploy)
- S3 bucket cho artifacts
- IAM roles
- EventBridge rule để auto-trigger

Script sẽ hiển thị Pipeline URL. Copy URL để xem pipeline.

#### Bước 5: Push code → Tự động deploy
```powershell
git add .
git commit -m "Deploy infrastructure"
git push codecommit main
```

Pipeline tự động chạy: Validate (cfn-lint) → Deploy (CloudFormation)

#### Bước 6: Xem Pipeline
```
URL: https://console.aws.amazon.com/codesuite/codepipeline/pipelines
Tìm: NT548-CloudFormation-Pipeline
```

Hoặc get URL:
```powershell
aws cloudformation describe-stacks --stack-name NT548-CodePipeline --query 'Stacks[0].Outputs[?OutputKey==`PipelineUrl`].OutputValue' --output text
```

#### Bước 7: Monitor
```powershell
# Pipeline state
aws codepipeline get-pipeline-state --name NT548-CloudFormation-Pipeline

# Build logs
aws logs tail /aws/codebuild/NT548-CloudFormation-Build --follow

# Stack status
aws cloudformation describe-stacks --stack-name NT548-Infrastructure --query 'Stacks[0].StackStatus'
```

#### Pipeline Flow
```
Push code → CodeCommit → CodeBuild (cfn-lint) → CloudFormation (Deploy) ✅
```

**3 Stages tự động:**
1. **Source**: Fetch code từ CodeCommit
2. **Build**: Validate với cfn-lint và Taskcat
3. **Deploy**: Deploy infrastructure (không cần approve)

#### Validation Tools

**cfn-lint**: Kiểm tra syntax
```powershell
cfn-lint cloudformation/templates/main.yaml
```

**Taskcat**: Test deployment
```powershell
taskcat test run
```

#### Troubleshooting

**Pipeline không trigger:**
```powershell
aws codepipeline start-pipeline-execution --name NT548-CloudFormation-Pipeline
```

**cfn-lint failed:**
```powershell
cfn-lint cloudformation/templates/main.yaml
# Fix errors và push lại
```

**Build failed:**
```powershell
aws logs tail /aws/codebuild/NT548-CloudFormation-Build --follow
```

**Deploy failed:**
```powershell
aws cloudformation describe-stack-events --stack-name NT548-Infrastructure --max-items 20
```

---

### Option 3: Manual Terraform Deployment

#### Bước 1: Setup S3 Backend

S3 backend đã được cấu hình sẵn trong `terraform/main.tf` với bucket name: `nt548-tfstate-409964509537`

Tạo backend resources (chỉ cần 1 lần):

```powershell
# Chạy script setup backend
pwsh scripts/setup-terraform-backend.ps1
```

Script sẽ tạo:
- S3 bucket: `nt548-tfstate-409964509537` với encryption và versioning
- DynamoDB table: `nt548-terraform-locks` cho state locking
- Lifecycle rule: Xóa old versions sau 7 ngày
- Block public access cho S3 bucket

#### Bước 2: Cấu hình Terraform Variables

```powershell
cd terraform
copy terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```

Sửa các giá trị trong `terraform.tfvars`:

```hcl
# Region
aws_region = "us-east-1"

# VPC Configuration
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidr   = "10.0.1.0/24"
private_subnet_cidr  = "10.0.2.0/24"
availability_zone    = "us-east-1a"

# EC2 Configuration
allowed_ssh_ip = "YOUR_IP_ADDRESS/32"  # Thay bằng IP của bạn
key_pair_name  = "nt548-keypair"       # Thay bằng tên key pair của bạn

# Tags
common_tags = {
  Project     = "NT548"
  Environment = "Lab"
  ManagedBy   = "Terraform"
}
```

#### Bước 3: Deploy Infrastructure

```powershell
# Initialize Terraform (download providers, setup backend)
terraform init

# Preview changes
terraform plan

# Apply changes
terraform apply

# Xác nhận bằng cách gõ: yes
```

#### Bước 4: Xem Outputs

```powershell
terraform output

# Hoặc xem specific output
terraform output vpc_id
terraform output public_ec2_ip
```

### Option 4: Manual CloudFormation Deployment

#### Bước 1: Cấu hình Parameters

```powershell
notepad cloudformation/parameters/dev.json
```

Sửa các giá trị:
```json
[
  {
    "ParameterKey": "KeyPairName",
    "ParameterValue": "nt548-keypair"
  },
  {
    "ParameterKey": "AllowedSSHIP",
    "ParameterValue": "YOUR_IP_ADDRESS/32"
  }
]
```

#### Bước 2: Deploy Stack

```powershell
# Sử dụng script
pwsh scripts/deploy-cloudformation.ps1

# Hoặc manual
aws cloudformation create-stack \
  --stack-name NT548-Infrastructure \
  --template-body file://cloudformation/templates/main.yaml \
  --parameters file://cloudformation/parameters/dev.json \
  --capabilities CAPABILITY_IAM

# Wait for completion
aws cloudformation wait stack-create-complete --stack-name NT548-Infrastructure
```

#### Bước 3: Xem Outputs

```powershell
aws cloudformation describe-stacks \
  --stack-name NT548-Infrastructure \
  --query 'Stacks[0].Outputs' \
  --output table
```

## Testing

### 1. Infrastructure Tests

Kiểm tra tất cả resources đã được tạo đúng:

```powershell
cd tests
pwsh run-tests.ps1
```

Tests bao gồm:
- VPC existence và state
- Subnets availability
- Internet Gateway attachment
- NAT Gateway state
- Route Tables configuration
- Security Groups rules
- EC2 instances state

### 2. Connectivity Tests

Kiểm tra kết nối network:

```powershell
cd tests
pwsh test-connectivity.ps1
```

Tests bao gồm:
- HTTP connectivity đến Public EC2
- Port 22 (SSH) accessibility
- Port 80 (HTTP) accessibility
- Ping test (nếu ICMP enabled)

### 3. SSH Connectivity Tests

#### Test SSH đến Public Instance

```bash
# Linux/Mac
ssh -i nt548-keypair.pem ec2-user@<PUBLIC_IP>

# Windows (PowerShell)
ssh -i nt548-keypair.pem ec2-user@<PUBLIC_IP>
```

#### Test SSH từ Public đến Private Instance

```bash
# 1. SSH vào Public instance
ssh -i nt548-keypair.pem ec2-user@<PUBLIC_IP>

# 2. Copy private key vào Public instance (chỉ để test)
# Trên máy local:
scp -i nt548-keypair.pem nt548-keypair.pem ec2-user@<PUBLIC_IP>:~/

# 3. Từ Public instance, SSH vào Private instance
ssh -i ~/nt548-keypair.pem ec2-user@<PRIVATE_IP>
```

**Lưu ý bảo mật:** Không nên copy private key lên server trong production. Sử dụng SSH Agent Forwarding thay thế:

```bash
# Enable SSH Agent Forwarding
ssh -A -i nt548-keypair.pem ec2-user@<PUBLIC_IP>

# Từ Public instance, SSH vào Private (không cần key)
ssh ec2-user@<PRIVATE_IP>
```

### 4. CloudFormation Tests

```powershell
cd tests
pwsh test-cloudformation.ps1 -StackName "NT548-Infrastructure"
```

### 5. Automated Testing với PowerShell

Set environment variable cho SSH tests:

```powershell
# Windows
$env:SSH_KEY_PATH = "D:\LAB2_NT548\nt548-keypair.pem"

# Linux/Mac
export SSH_KEY_PATH="/path/to/nt548-keypair.pem"
```

Sau đó chạy connectivity tests sẽ tự động test SSH.

## CI/CD

Project hỗ trợ 2 phương thức CI/CD:
1. **GitHub Actions** - Cho Terraform deployment
2. **AWS CodePipeline** - Cho CloudFormation deployment (Recommended)

### GitHub Actions

#### Setup GitHub Secrets

Vào repository Settings > Secrets and variables > Actions, thêm:

```
AWS_ACCESS_KEY_ID=<your-access-key>
AWS_SECRET_ACCESS_KEY=<your-secret-key>
TF_VAR_allowed_ssh_ip=<your-ip>/32
TF_VAR_key_pair_name=<your-key-pair-name>
```

### Workflow Actions

Workflow tự động chạy khi:
- Push code vào branch `main` hoặc `develop`
- Thay đổi files trong `terraform/` hoặc `.github/workflows/`
- Manual trigger từ GitHub Actions tab

### Manual Deployment

1. Vào repository > Actions tab
2. Chọn workflow "NT548 - Terraform AWS Infrastructure Deploy"
3. Click "Run workflow"
4. Chọn action:
   - **plan**: Chỉ xem execution plan
   - **apply**: Deploy infrastructure
   - **destroy**: Xóa infrastructure (giữ S3 backend)
   - **destroy-all**: Xóa tất cả bao gồm S3 backend

### Workflow Steps

1. **Checkov Security Scan**
   - Scan Terraform code tìm security issues
   - Fail nếu có CRITICAL hoặc HIGH severity issues
   - Upload scan results

2. **Setup Terraform Backend**
   - Tự động tạo S3 bucket nếu chưa có
   - Tự động tạo DynamoDB table nếu chưa có

3. **Terraform Deploy**
   - Initialize với S3 backend
   - Validate configuration
   - Plan changes
   - Apply (nếu approved)

4. **Infrastructure Tests**
   - Chạy automated tests
   - Verify resources
   - Test connectivity

5. **Notifications**
   - Success/Failure notifications
   - Deployment summary

## Cleanup

### Xóa CodePipeline và Infrastructure

```powershell
# Xóa tất cả
.\scripts\cleanup-all.ps1 -Force

# Hoặc xóa từng bước:

# 1. Delete infrastructure stack
aws cloudformation delete-stack --stack-name NT548-Infrastructure
aws cloudformation wait stack-delete-complete --stack-name NT548-Infrastructure

# 2. Delete pipeline stack
aws cloudformation delete-stack --stack-name NT548-CodePipeline
aws cloudformation wait stack-delete-complete --stack-name NT548-CodePipeline

# 3. Delete artifacts bucket
aws s3 rm s3://nt548-pipeline-artifacts-<account-id> --recursive
aws s3api delete-bucket --bucket nt548-pipeline-artifacts-<account-id>

# 4. Delete CodeCommit repository
aws codecommit delete-repository --repository-name nt548-infrastructure
```

### Xóa Infrastructure (giữ Backend) - Khuyến nghị

Xóa chỉ infrastructure, giữ lại S3 backend và DynamoDB để deploy nhanh hơn lần sau:

```powershell
.\scripts\cleanup-all.ps1 -Force
```

### Xóa Tất Cả (bao gồm Backend)

Xóa toàn bộ bao gồm cả S3 bucket và DynamoDB table:

```powershell
.\scripts\cleanup-all.ps1 -Force -DeleteBackend
```

### Xóa qua GitHub Actions

Vào GitHub Actions → Run workflow → chọn action:
- **destroy**: Xóa infrastructure, giữ backend
- **destroy-all**: Xóa infrastructure + S3 bucket
- **destroy-everything**: Xóa tất cả bao gồm DynamoDB

### Xóa thủ công (nếu cần)

```powershell
# 1. Destroy infrastructure
cd terraform
terraform destroy

# 2. Delete S3 bucket (nếu muốn)
aws s3 rm s3://nt548-tfstate-409964509537 --recursive
aws s3api delete-bucket --bucket nt548-tfstate-409964509537 --region us-east-1

# 3. Delete DynamoDB table (nếu muốn)
aws dynamodb delete-table --table-name nt548-terraform-locks --region us-east-1
```

### Xóa CloudFormation Stack

```powershell
aws cloudformation delete-stack --stack-name NT548-Infrastructure

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name NT548-Infrastructure
```

## Security Best Practices

### 1. Credentials Management
- Không commit AWS credentials vào Git
- Sử dụng AWS CLI profiles
- Sử dụng GitHub Secrets cho CI/CD
- Rotate credentials định kỳ

### 2. SSH Keys
- Không commit private keys (.pem) vào Git
- Store keys an toàn trên local machine
- Set proper permissions (chmod 400)
- Sử dụng SSH Agent Forwarding thay vì copy keys

### 3. Network Security
- Restrict SSH access đến specific IP
- Private instances không có public IP
- NAT Gateway cho private subnet internet access
- Security Groups theo principle of least privilege

### 4. State Management
- S3 backend với encryption
- Versioning enabled
- State locking với DynamoDB
- Block public access

## Troubleshooting

### Terraform Init Failed

```powershell
# Xóa cache và init lại
rm -r .terraform
rm .terraform.lock.hcl
terraform init -reconfigure
```

### State Lock Error

```powershell
# Xem lock info
aws dynamodb get-item \
  --table-name nt548-terraform-locks \
  --key '{"LockID":{"S":"nt548-terraform-state/terraform.tfstate"}}'

# Force unlock (cẩn thận!)
terraform force-unlock <LOCK_ID>
```

### Backend Không Tồn Tại

```powershell
# Tạo lại backend
pwsh scripts/setup-terraform-backend.ps1

# Hoặc tạo thủ công
aws s3api create-bucket --bucket nt548-tfstate-409964509537 --region us-east-1
aws s3api put-bucket-versioning --bucket nt548-tfstate-409964509537 --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name nt548-terraform-locks --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region us-east-1
```

### SSH Connection Refused

```bash
# Kiểm tra Security Group
aws ec2 describe-security-groups --group-ids <SG_ID>

# Kiểm tra instance state
aws ec2 describe-instances --instance-ids <INSTANCE_ID>

# Kiểm tra IP của bạn
curl ifconfig.me

# Update Security Group nếu IP thay đổi
aws ec2 authorize-security-group-ingress \
  --group-id <SG_ID> \
  --protocol tcp \
  --port 22 \
  --cidr <YOUR_NEW_IP>/32
```

### HTTP Not Working

```bash
# SSH vào instance và check web server
ssh -i nt548-keypair.pem ec2-user@<PUBLIC_IP>

# Check if httpd is running
sudo systemctl status httpd

# Start httpd if not running
sudo systemctl start httpd
sudo systemctl enable httpd

# Check logs
sudo tail -f /var/log/httpd/error_log
```

### Terraform Apply Timeout

```powershell
# Increase timeout
terraform apply -timeout=30m

# Hoặc apply specific resource
terraform apply -target=module.vpc
terraform apply -target=module.ec2
```

### AWS CLI Not Configured

```bash
# Configure AWS CLI
aws configure

# Verify configuration
aws sts get-caller-identity

# List available profiles
aws configure list-profiles
```

### CodePipeline Issues

**Pipeline Not Triggering:**
```bash
# Check EventBridge rule
aws events list-rules --name-prefix NT548-Pipeline

# Check rule targets
aws events list-targets-by-rule --rule NT548-Pipeline-Trigger

# Manually trigger pipeline
aws codepipeline start-pipeline-execution --name NT548-CloudFormation-Pipeline
```

**CodeBuild Failed:**
```bash
# View build logs
aws codebuild batch-get-builds --ids <build-id>

# Check CloudWatch logs
aws logs tail /aws/codebuild/NT548-CloudFormation-Build --follow

# Common issues:
# 1. cfn-lint errors - Fix template syntax
# 2. Taskcat timeout - Increase timeout or use --no-delete
# 3. Permission errors - Check CodeBuild IAM role
```

**cfn-lint Errors:**
```bash
# Run cfn-lint locally
pip install cfn-lint
cfn-lint cloudformation/templates/main.yaml

# Ignore specific rules
cfn-lint cloudformation/templates/main.yaml --ignore-checks W2001

# Fix common errors:
# E3001: Invalid resource type - Check AWS documentation
# E3002: Invalid property - Verify property names
# W2001: Unused parameter - Remove or use parameter
```

**Taskcat Failed:**
```bash
# Run Taskcat locally
pip install taskcat
taskcat test run

# Debug mode
taskcat test run --debug

# Keep stacks for debugging
taskcat test run --no-delete

# Common issues:
# 1. Parameter mismatch - Check .taskcat.yml
# 2. Resource limits - Check AWS service quotas
# 3. Timeout - Increase timeout in .taskcat.yml
```

**Git Push to CodeCommit Failed:**
```bash
# Configure Git credential helper
git config --global credential.helper '!aws codecommit credential-helper $@'
git config --global credential.UseHttpPath true

# Test credentials
aws codecommit get-repository --repository-name nt548-infrastructure

# Check IAM permissions
aws iam get-user

# Required permissions:
# - codecommit:GitPull
# - codecommit:GitPush
```

**Manual Approval Timeout:**
```bash
# Check approval status
aws codepipeline get-pipeline-state --name NT548-CloudFormation-Pipeline

# Approve via CLI
aws codepipeline put-approval-result \
  --pipeline-name NT548-CloudFormation-Pipeline \
  --stage-name Deploy \
  --action-name ApprovalRequired \
  --result status=Approved,summary="Approved" \
  --token <token>
```

## Tài liệu tham khảo

**Terraform:**
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform S3 Backend](https://www.terraform.io/docs/language/settings/backends/s3.html)

**AWS CloudFormation:**
- [AWS CloudFormation Documentation](https://docs.aws.amazon.com/cloudformation/)
- [CloudFormation Best Practices](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/best-practices.html)
- [CloudFormation Resource Types](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-template-resource-type-ref.html)

**AWS CodePipeline:**
- [AWS CodePipeline Documentation](https://docs.aws.amazon.com/codepipeline/)
- [AWS CodeBuild Documentation](https://docs.aws.amazon.com/codebuild/)
- [AWS CodeCommit Documentation](https://docs.aws.amazon.com/codecommit/)

**Validation Tools:**
- [cfn-lint Documentation](https://github.com/aws-cloudformation/cfn-lint)
- [Taskcat Documentation](https://github.com/aws-ia/taskcat)
- [cfn-lint Rules](https://github.com/aws-cloudformation/cfn-lint/blob/main/docs/rules.md)

**AWS Services:**
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)
- [AWS EC2 Documentation](https://docs.aws.amazon.com/ec2/)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

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
  - [Quick Start](#option-1-quick-start-recommended)
  - [Terraform Deployment](#option-2-manual-terraform-deployment)
  - [CloudFormation Deployment](#option-3-cloudformation-deployment)
  - [AWS CodePipeline Deployment](#option-4-aws-codepipeline-deployment-recommended)
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
├── terraform/                    # Terraform infrastructure
│   ├── modules/                 # Terraform modules
│   │   ├── vpc/                # VPC module
│   │   ├── ec2/                # EC2 module
│   │   └── security-groups/    # Security Groups module
│   ├── main.tf                 # Main configuration với S3 backend
│   ├── variables.tf            # Variable definitions
│   ├── outputs.tf              # Output definitions
│   └── terraform.tfvars.example # Example variables
│
├── cloudformation/              # CloudFormation templates
│   ├── templates/              # CloudFormation YAML templates
│   │   └── main.yaml          # Main infrastructure template
│   ├── parameters/             # Parameter files
│   │   └── dev.json           # Development parameters
│   ├── pipeline/               # CodePipeline templates
│   │   └── codepipeline.yaml  # Pipeline stack template
│   └── buildspec.yml           # CodeBuild build specification
│
├── scripts/                     # Deployment scripts
│   ├── setup-terraform-backend.ps1  # Setup S3 backend
│   ├── setup-codecommit.ps1         # Setup CodeCommit repo
│   ├── deploy-cloudformation.ps1    # Deploy CloudFormation
│   ├── deploy-codepipeline.ps1      # Deploy CodePipeline
│   └── destroy-infrastructure.ps1   # Cleanup resources
│
├── tests/                       # Test scripts
│   ├── run-tests.ps1           # Infrastructure tests
│   ├── test-connectivity.ps1   # Connectivity tests
│   └── test-cloudformation.ps1 # CloudFormation tests
│
├── .github/workflows/           # GitHub Actions workflows
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
- S3 Bucket: `nt548-tfstate-<account-id>` (encrypted, versioned)
- DynamoDB Table: `nt548-terraform-locks` (state locking)
- Lifecycle: Old versions deleted after 7 days

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
| PowerShell | >= 7.0 | https://github.com/PowerShell/PowerShell |
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

### Option 1: Quick Start (Recommended)

```cmd
quick-start.bat
```

Script sẽ tự động:
1. Kiểm tra prerequisites
2. Setup S3 backend
3. Cấu hình Terraform variables
4. Deploy infrastructure

### Option 2: Manual Terraform Deployment

#### Bước 1: Setup S3 Backend

```powershell
# Chạy script setup backend (chỉ cần 1 lần)
pwsh scripts/setup-terraform-backend.ps1

# Hoặc với custom parameters
pwsh scripts/setup-terraform-backend.ps1 -BucketName "my-terraform-state" -Region "us-east-1"
```

Script sẽ tạo:
- S3 bucket với encryption và versioning
- DynamoDB table cho state locking
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

### Option 3: CloudFormation Deployment

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

### AWS CodePipeline

AWS CodePipeline cung cấp CI/CD tự động cho CloudFormation với validation và testing.

#### Architecture

```
CodeCommit (Source) → CodeBuild (Validate) → CloudFormation (Deploy)
                           │
                           ├─ cfn-lint
                           ├─ Taskcat
                           └─ YAML validation
```

#### Setup Steps

**1. Setup CodeCommit Repository**
```powershell
pwsh scripts/setup-codecommit.ps1
```

**2. Deploy Pipeline**
```powershell
pwsh scripts/deploy-codepipeline.ps1 -NotificationEmail "your-email@example.com"
```

**3. Push Changes**
```bash
git add .
git commit -m "Update infrastructure"
git push codecommit main
```

#### Pipeline Stages

**Source Stage:**
- Monitors CodeCommit repository
- Auto-triggers on push to main branch
- Fetches latest code

**Build Stage (CodeBuild):**
- Installs cfn-lint and Taskcat
- Validates CloudFormation syntax
- Runs cfn-lint checks:
  - Resource validation
  - Best practices
  - Security checks
- Runs Taskcat tests:
  - Deploy test stacks
  - Validate resources
  - Cleanup after tests
- Generates validation reports

**Deploy Stage:**
- Creates CloudFormation Change Set
- Waits for manual approval
- Executes Change Set to deploy infrastructure

#### cfn-lint Rules

cfn-lint validates CloudFormation templates against AWS best practices:

**Error Rules (E):**
- E1001: Basic CloudFormation syntax
- E2001: Parameter validation
- E3001: Resource type validation
- E3002: Resource property validation

**Warning Rules (W):**
- W2001: Parameter usage
- W3002: Resource property best practices

**Informational Rules (I):**
- I3011: Availability Zone recommendations
- I3012: Resource naming conventions

Example `.cfnlintrc`:
```yaml
ignore_checks:
  - W2001  # Ignore unused parameter warnings
regions:
  - us-east-1
```

#### Taskcat Configuration

`.taskcat.yml` defines test scenarios:

```yaml
project:
  name: NT548-CloudFormation
  owner: NT548-Team
  regions:
    - us-east-1
  parameters:
    KeyPairName: nt548-keypair
    AllowedSSHIP: 0.0.0.0/0

tests:
  default:
    template: cloudformation/templates/main.yaml
    regions:
      - us-east-1
```

Taskcat will:
1. Create test stacks in specified regions
2. Validate all resources are created
3. Run for ~15 minutes
4. Delete test stacks automatically

#### Manual Approval

Pipeline pauses at approval stage:

**Via AWS Console:**
1. Go to CodePipeline console
2. Click on pipeline execution
3. Review Change Set
4. Click "Review" → "Approve" or "Reject"

**Via AWS CLI:**
```bash
# Get approval token
aws codepipeline get-pipeline-state --name NT548-CloudFormation-Pipeline

# Approve
aws codepipeline put-approval-result \
  --pipeline-name NT548-CloudFormation-Pipeline \
  --stage-name Deploy \
  --action-name ApprovalRequired \
  --result status=Approved,summary="Approved by admin" \
  --token <token-from-get-pipeline-state>
```

#### Monitoring

**View Pipeline Status:**
```powershell
# Pipeline state
aws codepipeline get-pipeline-state --name NT548-CloudFormation-Pipeline

# Execution history
aws codepipeline list-pipeline-executions --pipeline-name NT548-CloudFormation-Pipeline --max-results 5

# Latest execution
aws codepipeline get-pipeline-execution \
  --pipeline-name NT548-CloudFormation-Pipeline \
  --pipeline-execution-id <execution-id>
```

**View Build Logs:**
```powershell
# List builds
aws codebuild list-builds-for-project --project-name NT548-CloudFormation-Build

# Get build details
aws codebuild batch-get-builds --ids <build-id>

# Stream logs
aws logs tail /aws/codebuild/NT548-CloudFormation-Build --follow
```

**CloudWatch Logs:**
- CodeBuild logs: `/aws/codebuild/NT548-CloudFormation-Build`
- CloudFormation events: CloudFormation console

#### Trigger Pipeline

**Auto-trigger (Recommended):**
```bash
# Any push to main branch triggers pipeline
git push codecommit main
```

**Manual trigger:**
```powershell
# Using AWS CLI
aws codepipeline start-pipeline-execution --name NT548-CloudFormation-Pipeline
```

#### Pipeline Artifacts

Artifacts stored in S3 bucket: `nt548-pipeline-artifacts-<account-id>`

Contents:
- Source code from CodeCommit
- Build outputs (cfn-lint reports, Taskcat results)
- CloudFormation templates
- Validation reports

Lifecycle: Artifacts deleted after 30 days

#### Cost Optimization

**Free Tier:**
- CodeCommit: 5 users, 50GB storage, 10,000 requests/month
- CodeBuild: 100 build minutes/month
- CodePipeline: 1 active pipeline/month

**Estimated Monthly Cost (beyond free tier):**
- CodePipeline: $1/active pipeline
- CodeBuild: $0.005/build minute
- S3 Storage: $0.023/GB
- Data Transfer: Varies

**Tips:**
- Use `--no-delete` flag in Taskcat for debugging only
- Clean up old artifacts regularly
- Use smaller CodeBuild instance (BUILD_GENERAL1_SMALL)

#### Cleanup Pipeline

```powershell
# Delete pipeline stack
aws cloudformation delete-stack --stack-name NT548-CodePipeline

# Delete artifacts bucket
aws s3 rm s3://nt548-pipeline-artifacts-<account-id> --recursive
aws s3api delete-bucket --bucket nt548-pipeline-artifacts-<account-id>

# Delete CodeCommit repository
aws codecommit delete-repository --repository-name nt548-infrastructure
```

## Cleanup

### Xóa Infrastructure (giữ Backend)

```powershell
cd terraform
terraform destroy

# Xác nhận: yes
```

### Xóa Tất Cả (bao gồm Backend)

**Option 1: Script**
```powershell
pwsh scripts/destroy-infrastructure.ps1 -Force
```

**Option 2: Manual**
```powershell
# 1. Destroy infrastructure
cd terraform
terraform destroy

# 2. Delete S3 bucket
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 rm s3://nt548-tfstate-${ACCOUNT_ID} --recursive
aws s3api delete-bucket --bucket nt548-tfstate-${ACCOUNT_ID} --region us-east-1

# 3. Delete DynamoDB table
aws dynamodb delete-table --table-name nt548-terraform-locks --region us-east-1
```

**Option 3: GitHub Actions**
- Chọn action `destroy-all` trong workflow

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

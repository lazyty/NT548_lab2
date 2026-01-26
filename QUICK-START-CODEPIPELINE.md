# Quick Start: AWS CodePipeline (Tự động hoàn toàn)

## 🚀 Chạy Pipeline

### Bước 1: Chuẩn bị
```powershell
# Kiểm tra AWS CLI
aws sts get-caller-identity

# Tạo key pair
aws ec2 create-key-pair --key-name nt548-keypair --query 'KeyMaterial' --output text > nt548-keypair.pem

# Lấy IP của bạn
curl ifconfig.me
```

### Bước 2: Cấu hình parameters
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

### Bước 3: Setup CodeCommit
```powershell
.\scripts\setup-codecommit.ps1
```

### Bước 4: Deploy Pipeline
```powershell
.\scripts\deploy-codepipeline.ps1
```

Script sẽ hiển thị Pipeline URL. Copy URL đó để xem pipeline.

### Bước 5: Push code → Tự động deploy
```powershell
git add .
git commit -m "Deploy infrastructure"
git push codecommit main
```

Pipeline tự động chạy: Validate (cfn-lint) → Deploy (CloudFormation)

### Bước 6: Xem Pipeline
```
URL: https://console.aws.amazon.com/codesuite/codepipeline/pipelines
Tìm: NT548-CloudFormation-Pipeline
```

Hoặc get URL:
```powershell
aws cloudformation describe-stacks --stack-name NT548-CodePipeline --query 'Stacks[0].Outputs[?OutputKey==`PipelineUrl`].OutputValue' --output text
```

### Bước 7: Monitor
```powershell
# Pipeline state
aws codepipeline get-pipeline-state --name NT548-CloudFormation-Pipeline

# Build logs
aws logs tail /aws/codebuild/NT548-CloudFormation-Build --follow

# Stack status
aws cloudformation describe-stacks --stack-name NT548-Infrastructure --query 'Stacks[0].StackStatus'
```

---

## 🧹 Hủy Pipeline

### Xóa tất cả
```powershell
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

### Hoặc dùng script
```powershell
.\scripts\cleanup-all.ps1 -Force
```

---

## 📋 Pipeline Flow

```
Push code → CodeCommit → CodeBuild (cfn-lint) → CloudFormation (Deploy) ✅
```

**3 Stages tự động:**
1. Source: Fetch code
2. Build: Validate với cfn-lint và Taskcat
3. Deploy: Deploy infrastructure (không cần approve)

---

## 🔍 Validation Tools

**cfn-lint**: Kiểm tra syntax
```powershell
cfn-lint cloudformation/templates/main.yaml
```

**Taskcat**: Test deployment
```powershell
taskcat test run
```

---

## 🐛 Troubleshooting

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

## 📚 Files quan trọng

- `cloudformation/templates/main.yaml` - Template chính
- `cloudformation/parameters/dev.json` - Parameters
- `cloudformation/pipeline/codepipeline.yaml` - Pipeline config
- `cloudformation/buildspec.yml` - CodeBuild config
- `.cfnlintrc` - cfn-lint rules
- `.taskcat.yml` - Taskcat config

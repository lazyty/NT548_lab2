@echo off
echo ===================================
echo NT548 - Quick Start Script
echo ===================================
echo.

echo Checking prerequisites...
echo.

REM Check AWS CLI
aws --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] AWS CLI not found!
    echo Please install AWS CLI from: https://aws.amazon.com/cli/
    pause
    exit /b 1
)
echo [OK] AWS CLI found

REM Check Terraform
terraform --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Terraform not found!
    echo Please install Terraform from: https://www.terraform.io/downloads.html
    pause
    exit /b 1
)
echo [OK] Terraform found

REM Check AWS credentials
aws sts get-caller-identity >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] AWS credentials not configured!
    echo Please run: aws configure
    pause
    exit /b 1
)
echo [OK] AWS credentials configured

echo.
echo Prerequisites check passed!
echo.

echo Choose deployment method:
echo 1. Terraform
echo 2. CloudFormation
echo 3. Exit
echo.
set /p choice="Enter your choice (1-3): "

if "%choice%"=="1" goto terraform
if "%choice%"=="2" goto cloudformation
if "%choice%"=="3" goto end
echo Invalid choice!
pause
exit /b 1

:terraform
echo.
echo Starting Terraform deployment...
echo.

REM Setup S3 backend first
echo Setting up Terraform backend (S3 + DynamoDB)...
pwsh -File scripts\setup-terraform-backend.ps1
if %errorlevel% neq 0 (
    echo Backend setup failed!
    pause
    exit /b 1
)
echo.

cd terraform
if not exist terraform.tfvars (
    if exist terraform.tfvars.example (
        copy terraform.tfvars.example terraform.tfvars
        echo terraform.tfvars created from example
        echo.
        echo IMPORTANT: Please edit terraform.tfvars with your values:
        echo 1. Set allowed_ssh_ip to your IP address
        echo 2. Set key_pair_name to your AWS key pair name
        echo.
        notepad terraform.tfvars
        echo.
        pause
    ) else (
        echo terraform.tfvars.example not found!
        pause
        exit /b 1
    )
)

echo Running Terraform...
terraform init
if %errorlevel% neq 0 (
    echo Terraform init failed!
    pause
    exit /b 1
)

terraform plan
if %errorlevel% neq 0 (
    echo Terraform plan failed!
    pause
    exit /b 1
)

echo.
set /p confirm="Do you want to apply the changes? (y/N): "
if /i not "%confirm%"=="y" (
    echo Deployment cancelled
    pause
    exit /b 0
)

terraform apply -auto-approve
if %errorlevel% neq 0 (
    echo Terraform apply failed!
    pause
    exit /b 1
)

echo.
echo Terraform deployment completed!
echo.
echo Outputs:
terraform output
echo.
echo Next steps:
echo 1. Run tests: cd tests ^&^& .\run-tests.ps1
echo 2. Test connectivity: cd tests ^&^& .\test-connectivity.ps1
echo.
goto end

:cloudformation
echo.
echo Starting CloudFormation deployment...
echo.
cd cloudformation
if not exist parameters\dev.json (
    echo parameters\dev.json not found!
    pause
    exit /b 1
)

echo Please make sure parameters\dev.json is configured with your values
echo Opening parameters file...
notepad parameters\dev.json
echo.
pause

echo Validating template...
aws cloudformation validate-template --template-body file://templates/main.yaml
if %errorlevel% neq 0 (
    echo Template validation failed!
    pause
    exit /b 1
)

echo.
set /p confirm="Do you want to create the CloudFormation stack? (y/N): "
if /i not "%confirm%"=="y" (
    echo Deployment cancelled
    pause
    exit /b 0
)

echo Creating CloudFormation stack...
aws cloudformation create-stack --stack-name nt548-infrastructure --template-body file://templates/main.yaml --parameters file://parameters/dev.json --capabilities CAPABILITY_IAM
if %errorlevel% neq 0 (
    echo Stack creation failed!
    pause
    exit /b 1
)

echo Waiting for stack creation to complete...
aws cloudformation wait stack-create-complete --stack-name nt548-infrastructure
if %errorlevel% neq 0 (
    echo Stack creation failed or timed out!
    pause
    exit /b 1
)

echo.
echo CloudFormation deployment completed!
echo.
echo Stack outputs:
aws cloudformation describe-stacks --stack-name nt548-infrastructure --query "Stacks[0].Outputs[*].[OutputKey,OutputValue]" --output table
echo.

:end
echo.
echo Deployment completed successfully!
echo.
echo Useful commands:
echo - Test infrastructure: cd tests ^&^& .\run-tests.ps1
echo - Test connectivity: cd tests ^&^& .\test-connectivity.ps1
echo - Destroy Terraform: cd terraform ^&^& terraform destroy
echo - Delete CloudFormation: aws cloudformation delete-stack --stack-name nt548-infrastructure
echo.
pause
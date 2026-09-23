# ============================================================
# bootstrap-backend.ps1
#
# Run this ONCE, before "terraform init" in the terraform/ folder.
# It creates (or confirms) the two things Terraform's remote
# state depends on:
#   1. S3 bucket   - stores terraform.tfstate
#   2. DynamoDB table - locks the state during apply/plan
#
# Safe to re-run: it checks before creating, so it will not
# error out if the bucket/table already exist.
#
# Usage:
#   cd enterprise-cloud-security-platform
#   .\bootstrap-backend.ps1
# ============================================================

$ErrorActionPreference = "Continue"
$PSNativeCommandUseErrorActionPreference = $false

$Profile      = "nitesh-terraform"
$Region       = "ap-south-1"
$ProjectName  = "enterprise-cloud-security-platform"

$AccountId = aws sts get-caller-identity --profile $Profile --query "Account" --output text
if (-not $AccountId) {
    Write-Error "Could not resolve AWS account ID. Check that the '$Profile' AWS CLI profile is configured (aws configure --profile $Profile)."
    exit 1
}

$BucketName = "$ProjectName-terraform-state-$AccountId"
$TableName  = "$ProjectName-terraform-locks"

Write-Host "Account ID   : $AccountId"
Write-Host "State bucket : $BucketName"
Write-Host "Lock table   : $TableName"
Write-Host ""

# ------------------------------------------------------------------
# 1. S3 state bucket
# ------------------------------------------------------------------
$bucketExists = aws s3api head-bucket --bucket $BucketName --profile $Profile 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] Bucket '$BucketName' already exists - reusing it."
} else {
    Write-Host "[..] Creating bucket '$BucketName'..."
    aws s3api create-bucket `
        --bucket $BucketName `
        --region $Region `
        --create-bucket-configuration LocationConstraint=$Region `
        --profile $Profile

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Bucket creation failed - see the AWS CLI error above. Stopping."
        exit 1
    }

    aws s3api put-bucket-versioning `
        --bucket $BucketName `
        --versioning-configuration Status=Enabled `
        --profile $Profile

    aws s3api put-bucket-encryption `
        --bucket $BucketName `
        --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' `
        --profile $Profile

    aws s3api put-public-access-block `
        --bucket $BucketName `
        --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true `
        --profile $Profile

    Write-Host "[OK] Bucket created, versioned, encrypted, and locked down from public access."
}

# ------------------------------------------------------------------
# 2. DynamoDB lock table
# ------------------------------------------------------------------
$tableStatus = aws dynamodb describe-table --table-name $TableName --profile $Profile --region $Region 2>$null
if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] DynamoDB table '$TableName' already exists - reusing it."
} else {
    Write-Host "[..] Creating DynamoDB table '$TableName'..."
    aws dynamodb create-table `
        --table-name $TableName `
        --attribute-definitions AttributeName=LockID,AttributeType=S `
        --key-schema AttributeName=LockID,KeyType=HASH `
        --billing-mode PAY_PER_REQUEST `
        --region $Region `
        --profile $Profile

    if ($LASTEXITCODE -ne 0) {
        Write-Error "DynamoDB table creation failed - see the AWS CLI error above. Stopping."
        exit 1
    }

    Write-Host "[..] Waiting for table to become ACTIVE..."
    aws dynamodb wait table-exists --table-name $TableName --profile $Profile --region $Region
    Write-Host "[OK] Table created and active."
}

Write-Host ""
Write-Host "Backend ready. bucket and dynamodb_table below already match terraform/backend.tf - no edits needed unless account ID differs:"
Write-Host "  bucket         = `"$BucketName`""
Write-Host "  dynamodb_table = `"$TableName`""
Write-Host ""
Write-Host "Next: cd terraform && terraform init"

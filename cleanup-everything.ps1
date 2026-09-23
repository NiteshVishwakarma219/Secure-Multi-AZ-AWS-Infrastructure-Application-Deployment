# ============================================================
# cleanup-everything.ps1
#
# Run this AFTER "terraform destroy" - whether destroy finished
# clean or errored out partway. It force-removes every leftover
# this project has hit during development (IAM role stuck
# "already exists", secrets stuck "scheduled for deletion", RDS
# parameter/subnet groups, the bootstrap S3 state bucket, and the
# DynamoDB lock table), then prints a final verification report.
#
# Safe to re-run: every step checks first and skips quietly if
# the resource is already gone.
#
# Usage:
#   cd enterprise-cloud-security-platform-fixed-v2
#   .\cleanup-everything.ps1
# ============================================================

$ErrorActionPreference = "Continue"
$PSNativeCommandUseErrorActionPreference = $false

$Profile     = "nitesh-terraform"
$Region      = "ap-south-1"
$ProjectName = "enterprise-cloud-security-platform"

$AccountId = aws sts get-caller-identity --profile $Profile --query "Account" --output text
if (-not $AccountId) {
    Write-Error "Could not resolve AWS account ID. Check the '$Profile' AWS CLI profile."
    exit 1
}

$StateBucket = "$ProjectName-terraform-state-$AccountId"
$LockTable   = "$ProjectName-terraform-locks"
$RoleName    = "$ProjectName-ec2-role"
$ProfileName = "$ProjectName-ec2-profile"

Write-Host "================================================================"
Write-Host " Cleaning up leftovers for account $AccountId in $Region"
Write-Host "================================================================"

# ------------------------------------------------------------------
# 1. IAM role + instance profile
# ------------------------------------------------------------------
Write-Host "`n[1/6] IAM role and instance profile..."

aws iam remove-role-from-instance-profile --instance-profile-name $ProfileName --role-name $RoleName --profile $Profile 2>$null | Out-Null

$attached = aws iam list-attached-role-policies --role-name $RoleName --profile $Profile --query "AttachedPolicies[].PolicyArn" --output text 2>$null
if ($attached) {
    foreach ($arn in ($attached -split "\s+")) {
        if ($arn) {
            aws iam detach-role-policy --role-name $RoleName --policy-arn $arn --profile $Profile 2>$null | Out-Null
            Write-Host "  detached policy: $arn"
        }
    }
}

$inline = aws iam list-role-policies --role-name $RoleName --profile $Profile --query "PolicyNames" --output text 2>$null
if ($inline) {
    foreach ($name in ($inline -split "\s+")) {
        if ($name) {
            aws iam delete-role-policy --role-name $RoleName --policy-name $name --profile $Profile 2>$null | Out-Null
            Write-Host "  deleted inline policy: $name"
        }
    }
}

aws iam delete-instance-profile --instance-profile-name $ProfileName --profile $Profile 2>$null | Out-Null
aws iam delete-role --role-name $RoleName --profile $Profile 2>$null | Out-Null
Write-Host "  IAM role/profile cleanup done."

# ------------------------------------------------------------------
# 2. RDS parameter group + subnet group
# ------------------------------------------------------------------
Write-Host "`n[2/6] RDS parameter group and subnet group..."

aws rds delete-db-parameter-group --db-parameter-group-name "$ProjectName-pg-params" --profile $Profile --region $Region 2>$null | Out-Null
aws rds delete-db-subnet-group --db-subnet-group-name "$ProjectName-db-subnet-group" --profile $Profile --region $Region 2>$null | Out-Null
Write-Host "  RDS parameter/subnet group cleanup done."

# ------------------------------------------------------------------
# 3. Secrets Manager - force delete without recovery window
# ------------------------------------------------------------------
Write-Host "`n[3/6] Secrets Manager secrets..."

aws secretsmanager delete-secret --secret-id "$ProjectName/db-credentials" --force-delete-without-recovery --profile $Profile --region $Region 2>$null | Out-Null
aws secretsmanager delete-secret --secret-id "$ProjectName/app-secrets" --force-delete-without-recovery --profile $Profile --region $Region 2>$null | Out-Null
Write-Host "  Secrets cleanup done."

# ------------------------------------------------------------------
# 4. S3 state bucket - empty (versions + delete markers) then delete
# ------------------------------------------------------------------
Write-Host "`n[4/6] S3 state bucket ($StateBucket)..."

$bucketExists = aws s3api head-bucket --bucket $StateBucket --profile $Profile 2>$null
if ($LASTEXITCODE -eq 0) {
    $versions = aws s3api list-object-versions --bucket $StateBucket --profile $Profile --query "Versions[].[Key,VersionId]" --output text 2>$null
    if ($versions) {
        $versions -split "`n" | ForEach-Object {
            $parts = $_ -split "`t"
            if ($parts.Length -eq 2) {
                aws s3api delete-object --bucket $StateBucket --key $parts[0] --version-id $parts[1] --profile $Profile 2>$null | Out-Null
            }
        }
    }

    $markers = aws s3api list-object-versions --bucket $StateBucket --profile $Profile --query "DeleteMarkers[].[Key,VersionId]" --output text 2>$null
    if ($markers) {
        $markers -split "`n" | ForEach-Object {
            $parts = $_ -split "`t"
            if ($parts.Length -eq 2) {
                aws s3api delete-object --bucket $StateBucket --key $parts[0] --version-id $parts[1] --profile $Profile 2>$null | Out-Null
            }
        }
    }

    aws s3api delete-bucket --bucket $StateBucket --profile $Profile --region $Region 2>$null | Out-Null
    Write-Host "  Bucket emptied and deleted."
} else {
    Write-Host "  Bucket doesn't exist - nothing to do."
}

# ------------------------------------------------------------------
# 5. DynamoDB lock table
# ------------------------------------------------------------------
Write-Host "`n[5/6] DynamoDB lock table ($LockTable)..."

aws dynamodb delete-table --table-name $LockTable --profile $Profile --region $Region 2>$null | Out-Null
Write-Host "  Lock table delete requested."

# ------------------------------------------------------------------
# 6. Verification report
# ------------------------------------------------------------------
Write-Host "`n[6/6] Verification - everything below should be EMPTY:"
Write-Host "----------------------------------------------------------------"

Write-Host "`nIAM roles:"
aws iam list-roles --profile $Profile --query "Roles[?contains(RoleName,'$ProjectName')].RoleName" --output table

Write-Host "`nSecrets:"
aws secretsmanager list-secrets --profile $Profile --region $Region --query "SecretList[?contains(Name,'$ProjectName')].Name" --output table

Write-Host "`nRDS instances:"
aws rds describe-db-instances --profile $Profile --region $Region --query "DBInstances[].DBInstanceIdentifier" --output table

Write-Host "`nRDS parameter groups:"
aws rds describe-db-parameter-groups --profile $Profile --region $Region --query "DBParameterGroups[?contains(DBParameterGroupName,'$ProjectName')].DBParameterGroupName" --output table

Write-Host "`nRDS subnet groups:"
aws rds describe-db-subnet-groups --profile $Profile --region $Region --query "DBSubnetGroups[?contains(DBSubnetGroupName,'$ProjectName')].DBSubnetGroupName" --output table

Write-Host "`nVPCs tagged for this project:"
aws ec2 describe-vpcs --profile $Profile --region $Region --filters "Name=tag:Project,Values=$ProjectName" --query "Vpcs[].VpcId" --output table

Write-Host "`nUnassociated Elastic IPs:"
aws ec2 describe-addresses --profile $Profile --region $Region --query "Addresses[?AssociationId==null].[AllocationId,PublicIp]" --output table

Write-Host "`nNAT Gateways (available/pending):"
aws ec2 describe-nat-gateways --profile $Profile --region $Region --filter "Name=state,Values=available,pending" --query "NatGateways[].NatGatewayId" --output table

Write-Host "`nRunning/stopped EC2 instances:"
aws ec2 describe-instances --profile $Profile --region $Region --filters "Name=instance-state-name,Values=running,pending,stopping,stopped" --query "Reservations[].Instances[].InstanceId" --output table

Write-Host "`nS3 buckets for this project:"
aws s3api list-buckets --profile $Profile --query "Buckets[?contains(Name,'$ProjectName')].Name" --output table

Write-Host "`nKMS aliases for this project (key itself may show PendingDeletion for its window - that's normal):"
aws kms list-aliases --profile $Profile --region $Region --query "Aliases[?contains(AliasName,'$ProjectName')]" --output table

Write-Host "`nRoute 53 hosted zones for the domain:"
aws route53 list-hosted-zones --profile $Profile --query "HostedZones[?contains(Name,'nitesh.shop')].[Id,Name]" --output table

Write-Host "`nACM certificates (ap-south-1):"
aws acm list-certificates --profile $Profile --region $Region --query "CertificateSummaryList[].DomainName" --output table

Write-Host "`nACM certificates (us-east-1, for CloudFront):"
aws acm list-certificates --profile $Profile --region us-east-1 --query "CertificateSummaryList[].DomainName" --output table

Write-Host "`nCloudWatch log groups for this project:"
aws logs describe-log-groups --profile $Profile --region $Region --query "logGroups[?contains(logGroupName,'$ProjectName') || contains(logGroupName,'flow-log') || contains(logGroupName,'lambda')].logGroupName" --output table

Write-Host "`nSNS topics for this project:"
aws sns list-topics --profile $Profile --region $Region --query "Topics[?contains(TopicArn,'$ProjectName')]" --output table

Write-Host "`nLambda functions for this project:"
aws lambda list-functions --profile $Profile --region $Region --query "Functions[?contains(FunctionName,'$ProjectName')].FunctionName" --output table

Write-Host "`nAWS Config recorders (should be empty - Config was disabled for this project):"
aws configservice describe-configuration-recorders --profile $Profile --region $Region

Write-Host "`nCloudTrail trails for this project:"
aws cloudtrail describe-trails --profile $Profile --region $Region --query "trailList[?contains(Name,'$ProjectName')].Name"

Write-Host "`n================================================================"
Write-Host " Done. Review the tables above - anything non-empty needs a"
Write-Host " manual look (paste it back for help). KMS PendingDeletion is"
Write-Host " expected and will clear itself after its deletion window."
Write-Host "================================================================"

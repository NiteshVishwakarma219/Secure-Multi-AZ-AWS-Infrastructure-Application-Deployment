# Deploy from zero — exact order, no skipping

You destroyed everything, so this account is currently blank. Follow this
exact order. Do not run `terraform apply` before step 4 passes.

## Step 0 — one-time tool check
```powershell
aws --version
terraform --version
aws sts get-caller-identity --profile nitesh-terraform
```
If the last command errors, your AWS CLI profile isn't configured — run
`aws configure --profile nitesh-terraform` first and stop here.

## Step 1 — check for leftover account-level resources
`terraform destroy` only removes what was in *that* state file. A few
services are account/region-wide singletons and can silently survive a
destroy if they errored out before. Check now, before creating anything:
```powershell
aws configservice describe-configuration-recorders --profile nitesh-terraform --region ap-south-1
aws guardduty list-detectors --profile nitesh-terraform --region ap-south-1
aws securityhub describe-hub --profile nitesh-terraform --region ap-south-1 2>$null
```
- First command: if it returns a recorder, delete it (`aws configservice
  delete-configuration-recorder --configuration-recorder-name <name>
  --profile nitesh-terraform`) — AWS allows only one per region, and a
  leftover one will make the new `aws_config_configuration_recorder`
  fail with `MaxNumberOfConfigurationRecordersExceededException`.
- GuardDuty/SecurityHub are disabled in `terraform.tfvars`
  (`enable_guardduty = false`, `enable_security_hub = false`), so these
  are just sanity checks, not blockers.

## Step 2 — bootstrap the state backend (S3 bucket + DynamoDB table)
```powershell
cd enterprise-cloud-security-platform-fixed-v2
.\bootstrap-backend.ps1
```
This creates the S3 bucket and DynamoDB lock table if they don't already
exist (safe to re-run). Confirm the printed bucket/table names match
`terraform/backend.tf` exactly — they will unless your AWS account ID
changed.

## Step 3 — review terraform.tfvars before touching anything
```powershell
cd terraform
notepad terraform.tvars   # or your editor of choice
```
Things worth changing before a fresh deploy:
- `db_password` is currently a plaintext value in this file. Change it to
  something you haven't used elsewhere before you apply — anyone with
  read access to this file or the state bucket can see it.
- `alarm_phone_number` — set it (E.164 format, e.g. `+919876543210`) if
  you want SMS alerts too. Leave `""` to skip. (India numbers need TRAI
  DLT sender-ID registration for SNS SMS to actually deliver — email
  alerts will work regardless.)
- `enable_cloudfront = false` is intentional — flip it to `true` only
  after AWS Support has verified this account for CloudFront (see
  bottom of this file).

## Step 4 — init, validate, plan
```powershell
terraform init
terraform validate
terraform fmt -recursive
terraform plan -out=tfplan
terraform show -no-color tfplan | Select-String "^  #"
```
Since the account is blank, this plan should show **only creates** —
no updates, no destroys. If you see anything with `will be destroyed`
or an error at `init`/`validate`, stop and paste it here before
proceeding.

## Step 5 — apply
```powershell
terraform apply tfplan
```
This will take 10-15 minutes (NAT gateway, RDS, ASG capacity wait are
the slow parts). Do not Ctrl+C on a timeout — if the ASG wait fails,
send the exact error, not a screenshot description.

## Step 6 — confirm the SNS email subscription
Check `niteshv811@gmail.com` (or whatever `alarm_email` you set) for an
AWS SNS "Subscription Confirmation" email and click **Confirm
subscription**. Alarms will not reach you until this is done.

## Step 7 — verify the app is actually up
```powershell
terraform output alb_dns_name
```
Open `http://<that-value>` in a browser. Then check target health:
```powershell
aws elbv2 describe-target-health --target-group-arn (terraform output -raw backend_target_group_arn) --profile nitesh-terraform
aws elbv2 describe-target-health --target-group-arn (terraform output -raw frontend_target_group_arn) --profile nitesh-terraform
```
Both should show `"State": "healthy"` within ~5 minutes of instances
going `InService`. If not, this is the same SSM/NAT check flow we did
before — check instance launch time and NAT Gateway state before
assuming it's a new bug.

## Step 8 — point the domain at Route 53 (new nameservers!)
Because the old hosted zone was destroyed, the new one has **different**
NS records. Get them and update at your domain registrar:
```powershell
terraform output route53_zone_id
aws route53 get-hosted-zone --id (terraform output -raw route53_zone_id) --profile nitesh-terraform --query "DelegationSet.NameServers"
```
Until this propagates, use the ALB DNS name to test, not the domain.

## Step 9 — CloudFront (later, once AWS verifies the account)
File an AWS Support case: "account verification for CloudFront". Once
approved, set `enable_cloudfront = true` in `terraform.tfvars`, then:
```powershell
terraform plan -out=tfplan
terraform show -no-color tfplan | Select-String "^  #"
terraform apply tfplan
```

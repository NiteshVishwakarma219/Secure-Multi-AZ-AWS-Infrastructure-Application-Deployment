# Runbooks

## Failure testing (§35)

### Test 1 — EC2 failure
1. `aws ec2 terminate-instances --instance-ids <one-instance-id-from-the-ASG>`
2. Watch the ASG activity history: `aws autoscaling describe-scaling-activities --auto-scaling-group-name <asg-name>`
3. Confirm a replacement instance launches and registers as healthy in both
   target groups.
4. Record: time to detect, time to replace, time to healthy-in-ALB.

### Test 2 — ALB unhealthy target
1. Temporarily stop the container on one instance via SSM:
   `docker stop eems-backend` (over an SSM session, not SSH).
2. Watch `aws elbv2 describe-target-health --target-group-arn <backend-tg-arn>`.
3. Confirm the ALB stops routing to that target and traffic continues to the
   healthy target.
4. Restart the container and confirm it's re-registered as healthy.

### Test 3 — Database failure (only meaningful with `db_multi_az = true`)
1. `aws rds reboot-db-instance --db-instance-identifier <id> --force-failover`
2. Watch RDS events: `aws rds describe-events --source-identifier <id> --source-type db-instance`
3. Record the failover duration and any application-level errors observed
   during the switch.

### Test 4 — Security-group mistake
1. Temporarily add an overly broad rule, e.g. `0.0.0.0/0 -> 5432` on the DB
   security group.
2. Detect it: AWS Config rule evaluation, or manually via
   `aws ec2 describe-security-groups`.
3. Investigate: who/what changed it (CloudTrail).
4. Fix: remove the rule via Terraform (`terraform apply` after reverting the
   change) — not manually in the console, to keep state consistent.
5. Verify: re-run the Config rule evaluation / re-check the security group.

### Test 5 — DNS problem
1. Temporarily point the Route53 `A` record for `api.<domain>` at the wrong
   target (or delete it).
2. Diagnose using `dig api.<domain>` / `nslookup` and the Route 53 console.
3. Restore via `terraform apply`.

### Test 6 — NAT problem
1. Temporarily disassociate/delete a NAT Gateway (or its route) in one AZ.
2. From an SSM session on an instance in that AZ, confirm outbound internet
   calls fail (e.g. `curl https://example.com` times out).
3. Confirm the ALB can still route traffic **to** the instance — this is an
   egress-only failure, not a full outage.
4. Restore via `terraform apply` and re-verify outbound connectivity.

## Security testing (§36)

### S3 accidentally public
1. Temporarily loosen `aws_s3_bucket_public_access_block` on one bucket (in a
   scratch/test bucket, not the real state or log bucket, if possible).
2. Detect via AWS Config (`S3_BUCKET_PUBLIC_READ_PROHIBITED`) or Security Hub.
3. Fix by reverting via Terraform.
4. Verify the Config rule now evaluates as COMPLIANT.

### SSH exposed to the world
1. Temporarily add `0.0.0.0/0 -> 22` to the App security group.
2. Detect via AWS Config (`INCOMING_SSH_DISABLED`) or manual review.
3. Remove the rule via Terraform. Note that SSM access is completely
   unaffected by this, since SSM never depended on port 22 being open.

### Over-permissioned IAM
1. Temporarily attach a broad policy (e.g. `AmazonS3FullAccess`) to the EC2
   role in a test copy of the stack.
2. Identify the excess via IAM Access Analyzer or manual policy review.
3. Remove the broad policy, confirm the app still functions using only the
   scoped policies already defined in `modules/iam`.

## Incident response — general shape

```
Detect  (CloudWatch alarm / GuardDuty finding / Security Hub / Config)
   ↓
Notify  (SNS email, or EventBridge -> Lambda -> SNS for GuardDuty)
   ↓
Investigate (CloudTrail for "who", Flow Logs for "what traffic", Config for "what changed")
   ↓
Contain / Fix (via Terraform, not manual console changes, so state stays authoritative)
   ↓
Verify (re-check the alarm/finding/rule is now clear)
   ↓
Document (add to docs/testing-evidence.md)
```

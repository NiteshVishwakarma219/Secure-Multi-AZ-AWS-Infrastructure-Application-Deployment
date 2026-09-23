# Troubleshooting Runbook

Every error below was actually hit during development of this project.
Find your exact error message (Ctrl+F), follow the fix. Most fixes are
already baked into this repo's code — for those, this doc explains
**why**, so you recognize the symptom if it ever resurfaces on a fresh
account. A few are one-off operational issues that need a manual step
every time (network drops, stale locks) — those get exact commands.

---

## Quick index

| If you see... | Jump to |
|---|---|
| `dial tcp: lookup ...amazonaws.com: no such host` | [1](#1-dial-tcp-lookup-no-such-host) |
| `Error acquiring the state lock` | [2](#2-error-acquiring-the-state-lock) |
| `Saved plan is stale` | [3](#3-saved-plan-is-stale) |
| `EntityAlreadyExists` (IAM role) | [4](#4-entityalreadyexists--already-exists-on-re-apply) |
| `DBParameterGroupAlreadyExists` / `DBSubnetGroupAlreadyExists` | [4](#4-entityalreadyexists--already-exists-on-re-apply) |
| `ResourceExistsException` (Secrets Manager) | [4](#4-entityalreadyexists--already-exists-on-re-apply) |
| `BucketAlreadyOwnedByYou` | [4](#4-entityalreadyexists--already-exists-on-re-apply) |
| `already scheduled for deletion` (Secrets Manager) | [5](#5-secret-already-scheduled-for-deletion) |
| `BucketNotEmpty` when deleting the state bucket | [6](#6-bucketnotempty-when-deleting-the-state-bucket) |
| AWS Backup `ResourceId does not match the expected format` | [7](#7-aws-backup-resourceid-does-not-match-the-expected-format) |
| ASG stuck "0 healthy instances", times out | [8](#8-asg-stuck-at-0-healthy-instances) |
| `CreateDistributionWithTags: AccessDenied` (CloudFront) | [9](#9-cloudfront-accessdenied-account-must-be-verified) |
| CloudWatch dashboard shows "No data" | [10](#10-cloudwatch-dashboard-shows-no-data) |
| ALB 502 Bad Gateway / targets "Unhealthy" | [11](#11-alb-502-bad-gateway--targets-unhealthy) |
| `nginx: [emerg] host not found in upstream "nexops-backend"` | [12](#12-nginx-host-not-found-in-upstream-nexops-backend) |
| Prisma `Environment variable not found: DIRECT_URL` | [13](#13-prisma-environment-variable-not-found-direct_url) |
| Target unhealthy with health-check code `404` | [14](#14-target-unhealthy-with-http-404) |
| Launch template changes don't roll out to running instances | [15](#15-launch-template-changes-dont-roll-out) |
| SSM Session Manager shows "Not connected" | [16](#16-ssm-session-manager-not-connected) |
| Domain resolves NS but `nslookup <domain>` gives no IP | [17](#17-domain-resolves-ns-but-no-a-record) |
| PowerShell: `'charmap' codec can't encode character` | [18](#18-powershell-charmap-codec-cant-encode-character) |
| PowerShell: `NativeCommandError` from a script that checks `$LASTEXITCODE` | [19](#19-powershell-nativecommanderror-from-a-normal-cli-check) |
| PowerShell: `Invalid JSON` passing `--delete` to `aws s3api delete-objects` | [20](#20-powershell-invalid-json-passing---delete-to-aws-cli) |
| `terraform destroy` errors out partway / leftovers after destroy | [21](#21-terraform-destroy-errors-out--leftovers-remain) |

---

### 1. `dial tcp: lookup ...amazonaws.com: no such host`

**What it means:** your computer's own internet/DNS dropped for a moment
mid-`apply` — not an AWS problem, not a code problem. You'll usually see
several unrelated AWS services (S3, IAM, RDS, Route53, SNS, EC2) all fail
with this exact message at the same timestamp — that pattern confirms it.

**Fix:**
1. Confirm: `ping 8.8.8.8` and `nslookup amazonaws.com` — if these fail too, that's the proof.
2. Reconnect / stabilize your network. Disable Wi-Fi adapter power-saving if this keeps happening (Control Panel → Network Connections → adapter Properties → Power Management → uncheck "allow the computer to turn off this device").
3. Re-run: `terraform plan -out=tfplan`, review it (see [§3](#3-saved-plan-is-stale) if the old plan file complains), then `terraform apply tfplan`.
4. If it left resources "tainted" or "deposed" (visible as `is tainted, so must be replaced` or `(deposed object ...) will be destroyed` in the plan) — that's Terraform safely cleaning up after itself. Let it proceed unless the plan also shows something unexpected being destroyed.

---

### 2. `Error acquiring the state lock`

**What it means:** a previous `plan`/`apply` didn't release its DynamoDB lock (usually because it was interrupted — see #1).

**Fix:** the error message includes a Lock ID. Run:
```powershell
terraform force-unlock <LOCK_ID>
```
Type `yes` to confirm. Then re-run your command.

---

### 3. `Saved plan is stale`

**What it means:** the `.tfplan` file you're trying to apply was generated before the state changed underneath it (commonly right after a force-unlock, or after any command that touched state in between).

**Fix:** just regenerate it — no data is lost:
```powershell
terraform plan -out=tfplan
terraform show -no-color tfplan | Select-String "^  #"
terraform apply tfplan
```

---

### 4. `EntityAlreadyExists` / `... already exists` on re-apply

Seen for: IAM roles, IAM instance profiles, RDS parameter groups, RDS
subnet groups, Secrets Manager secrets, S3 buckets.

**What it means:** these specific resources were actually created on AWS
during an earlier apply that got interrupted (see #1) or partially failed,
but Terraform's state file doesn't know about them (the interruption
happened before Terraform recorded them). Terraform tries to create them
fresh; AWS correctly refuses because they're already there.

**Fix — the fast way:** run the sweep script once, then re-plan:
```powershell
cd enterprise-cloud-security-platform-fixed-v2
.\cleanup-everything.ps1
cd terraform
terraform plan -out=tfplan
```
This force-removes every leftover this project has hit (IAM role +
profile, RDS parameter/subnet groups, both secrets) and prints a
verification report so you can see it's actually clean before re-planning.

**Fix — the manual way** (if you want to remove just one specific thing):
```powershell
# IAM role stuck existing
$RoleName = "enterprise-cloud-security-platform-ec2-role"
aws iam remove-role-from-instance-profile --instance-profile-name "enterprise-cloud-security-platform-ec2-profile" --role-name $RoleName --profile <profile>
aws iam list-attached-role-policies --role-name $RoleName --profile <profile> --query "AttachedPolicies[].PolicyArn" --output text
# detach each ARN returned above:
aws iam detach-role-policy --role-name $RoleName --policy-arn <arn> --profile <profile>
aws iam delete-role --role-name $RoleName --profile <profile>

# RDS parameter/subnet group stuck existing
aws rds delete-db-parameter-group --db-parameter-group-name enterprise-cloud-security-platform-pg-params --profile <profile> --region <region>
aws rds delete-db-subnet-group --db-subnet-group-name enterprise-cloud-security-platform-db-subnet-group --profile <profile> --region <region>
```

---

### 5. Secret `already scheduled for deletion`

**What it means:** a Secrets Manager secret from an earlier interrupted
run is sitting in its recovery window (soft-deleted, not gone) and won't
let you create a new one with the same name.

**Note:** this repo's `modules/secrets/main.tf` already sets
`recovery_window_in_days = 0` so future destroys skip this window
entirely — you should only see this on secrets created before that fix,
or if you changed it back for a "real" production deployment.

**Fix:**
```powershell
aws secretsmanager delete-secret --secret-id "enterprise-cloud-security-platform/db-credentials" --force-delete-without-recovery --profile <profile> --region <region>
aws secretsmanager delete-secret --secret-id "enterprise-cloud-security-platform/app-secrets" --force-delete-without-recovery --profile <profile> --region <region>
```
(`cleanup-everything.ps1` does this automatically too.)

---

### 6. `BucketNotEmpty` when deleting the state bucket

**What it means:** the bucket has versioning enabled, so a normal delete
leaves old object versions and delete-markers behind — you have to purge
those before AWS lets you delete the bucket itself.

**Fix:** `cleanup-everything.ps1` handles this automatically. To do it
manually:
```powershell
$Bucket = "enterprise-cloud-security-platform-terraform-state-<account-id>"

$versions = aws s3api list-object-versions --bucket $Bucket --profile <profile> --query "Versions[].[Key,VersionId]" --output text
$versions -split "`n" | ForEach-Object {
    $parts = $_ -split "`t"
    if ($parts.Length -eq 2) { aws s3api delete-object --bucket $Bucket --key $parts[0] --version-id $parts[1] --profile <profile> | Out-Null }
}

$markers = aws s3api list-object-versions --bucket $Bucket --profile <profile> --query "DeleteMarkers[].[Key,VersionId]" --output text
$markers -split "`n" | ForEach-Object {
    $parts = $_ -split "`t"
    if ($parts.Length -eq 2) { aws s3api delete-object --bucket $Bucket --key $parts[0] --version-id $parts[1] --profile <profile> | Out-Null }
}

aws s3api delete-bucket --bucket $Bucket --profile <profile> --region <region>
```

---

### 7. AWS Backup `ResourceId does not match the expected format`

**What it means:** a wildcard/malformed RDS ARN was passed directly into
`aws_backup_selection.resources`.

**Status:** already fixed in this repo. `modules/backup/main.tf` uses
tag-based selection instead:
```hcl
resource "aws_backup_selection" "main" {
  resources = ["*"]
  condition {
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.backup_tag_value
    }
  }
}
```
Note the block is singular `condition`, not `conditions` — the plural
name is a real Terraform validation error (`Unsupported block type`) if
you ever hand-edit this.

---

### 8. ASG stuck at "0 healthy instances"

```
timeout while waiting for state to become 'ok' (last state: 'want at
least 2 healthy instance(s) in Auto Scaling Group, have 0'
```

**What it means:** the launch template encrypts the root EBS volume with
a customer-managed KMS key. Creating an *encrypted* volume via an Auto
Scaling launch template is done by AWS's **Auto Scaling service-linked
role** (`AWSServiceRoleForAutoScaling`), not the instance's own IAM role.
If the KMS key policy doesn't grant that service-linked role permission,
instances can never actually launch.

**Status:** already fixed in this repo. `modules/storage/main.tf`'s KMS
key policy includes an explicit statement for
`arn:aws:iam::<account>:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling`
granting `kms:CreateGrant`, `kms:Decrypt`, `kms:DescribeKey`,
`kms:GenerateDataKeyWithoutPlaintext`, `kms:ReEncrypt*`.

If you see this on a brand-new key/account, verify that statement is
still present before assuming it's a different bug.

---

### 9. CloudFront `AccessDenied: account must be verified`

**What it means:** brand-new AWS accounts are blocked from creating
CloudFront distributions until AWS Support manually verifies the account.
This is an AWS account-level restriction — nothing in the Terraform code
can work around it.

**Fix:**
1. Leave `enable_cloudfront = false` in `terraform.tfvars` (the default). Route 53 will alias the domain directly at the ALB instead — see `apex_alb`/`www_alb` in `modules/edge/main.tf`.
2. File an AWS Support case: "account verification for CloudFront".
3. Once approved, set `enable_cloudfront = true` and re-apply. This removes the ALB-alias fallback records and switches to a CloudFront distribution + WAF Web ACL.

---

### 10. CloudWatch dashboard shows "No data"

**What it means:** the dashboard widgets were querying metrics from the
wrong AWS region (hardcoded `us-east-1` regardless of where you actually
deployed).

**Status:** already fixed — `modules/monitoring/main.tf` widgets use
`region = var.aws_region`. If you still see this, confirm `aws_region` is
being passed correctly from root `main.tf` into the monitoring module.

---

### 11. ALB 502 Bad Gateway / targets "Unhealthy"

This is the single most common thing you'll hit, and it can have several
different underlying causes. **Don't guess — follow this exact diagnostic
order:**

**Step 1 — check target health (which tier, which port, what reason):**
```powershell
aws elbv2 describe-target-health --target-group-arn <backend-tg-arn> --profile <profile>
aws elbv2 describe-target-health --target-group-arn <frontend-tg-arn> --profile <profile>
```
- Both tiers unhealthy on both ports → something is broken at the container/boot level (go to Step 2).
- Only backend unhealthy with a specific HTTP code (e.g. `404`) → the container is running fine, the health check path is wrong (see [§14](#14-target-unhealthy-with-http-404)).

**Step 2 — get the instance's boot console log (works even without SSM):**
```powershell
$env:PYTHONUTF8="1"
aws ec2 get-console-output --instance-id <instance-id> --profile <profile> --query Output --output text | Out-File -FilePath console.txt -Encoding utf8
Get-Content console.txt | Select-String -Pattern "SSM agent status|nexops-backend|eems-frontend" -Context 0,40
```
If the file comes back empty, see [§18](#18-powershell-charmap-codec-cant-encode-character).

This repo's `user-data.sh` includes a diagnostic block that prints
`docker ps` and `docker logs` for both containers straight into this
console output ~25 seconds after boot — no SSM needed to see why a
container is crash-looping.

**Step 3 — read what the diagnostic block shows:**
- Repeated `veth...entered blocking/forwarding/disabled` cycles with growing gaps = a container is crash-looping (Docker's restart backoff). Look at the `docker logs` output right above/below it for the actual application error.
- `nginx: [emerg] host not found in upstream` → see [§12](#12-nginx-host-not-found-in-upstream-nexops-backend).
- `Environment variable not found: DIRECT_URL` → see [§13](#13-prisma-environment-variable-not-found-direct_url).
- Containers show `Up X seconds` (not `Restarting`) and the app logs show it actually started (e.g. `NexOps API running on http://localhost:8000`) → the container is fine, the problem is the ALB health check path/port — go to [§14](#14-target-unhealthy-with-http-404).

**Step 4 — if you need to poke around live** (once SSM is connected — see [§16](#16-ssm-session-manager-not-connected)):
```powershell
aws ssm start-session --target <instance-id> --profile <profile>
# inside the session:
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/api/health
docker logs nexops-backend --tail 100
docker logs eems-frontend --tail 100
```

---

### 12. `nginx: [emerg] host not found in upstream "nexops-backend"`

**What it means:** the frontend's baked-in nginx config has a hardcoded
upstream server name (`nexops-backend`) that it expects to resolve via
Docker's embedded DNS on the shared bridge network. If the actual backend
container has a different `--name`, nginx can never start and crash-loops
forever.

**Status:** already fixed — `modules/compute/user-data.sh` names the
backend container `nexops-backend` to match. If you ever change the
Docker image and it expects a different upstream name, update the
`--name` in the `docker run` command for the backend to match whatever
the frontend's nginx config expects (check the image's own
`nginx.conf`/`default.conf` if unsure).

---

### 13. Prisma `Environment variable not found: DIRECT_URL`

**What it means:** this backend uses Prisma ORM, which reads its
database connection from `DATABASE_URL` and (for its migration/introspection
commands) `DIRECT_URL` — not individual `DB_HOST`/`DB_USERNAME`/etc.
vars. Since this RDS instance has no connection pooler in front of it,
both values are identical.

**Status:** already fixed — `modules/compute/user-data.sh` builds:
```bash
DATABASE_URL="postgresql://$DB_USERNAME:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME_VAL?schema=public"
DIRECT_URL="$DATABASE_URL"
```
and passes both into the container's environment. If you swap in a
different backend image, check what connection-string env vars **it**
actually expects (verify via SSM + `curl`/`docker logs` — don't assume).

---

### 14. Target unhealthy with HTTP `404`

**What it means:** the container is healthy and responding, but the ALB
health check is hitting a path the app doesn't serve.

**Fix — find the real path** (via SSM, once connected):
```powershell
aws ssm start-session --target <instance-id> --profile <profile>
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/health
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/api/health
curl -s http://localhost:8000/
```
Whichever path returns `200`, use that. This repo's backend uses
`/api/health` — already set in `modules/load-balancer/main.tf`'s
`health_check` block for the backend target group.

---

### 15. Launch template changes don't roll out

**Symptom:** you change `user-data.sh` or another launch-template
setting, `terraform apply` succeeds, but the running instances never
actually update — only brand-new instances (from a scaling event) pick up
the change.

**What it means:** `version = "$Latest"` on the ASG's `launch_template`
block is a literal string that never numerically "changes" from
Terraform's point of view, so an `instance_refresh` with
`triggers = ["launch_template"]` never actually fires.

**Status:** already fixed — `modules/compute/main.tf` uses
`version = aws_launch_template.app.latest_version` instead, which
genuinely increments and correctly triggers the refresh.

**If you need to force a refresh right now** without waiting for a new
apply cycle:
```powershell
aws autoscaling start-instance-refresh --auto-scaling-group-name enterprise-cloud-security-platform-asg --profile <profile> --region <region>
aws autoscaling describe-instance-refreshes --auto-scaling-group-name enterprise-cloud-security-platform-asg --profile <profile> --region <region> --query "InstanceRefreshes[0].{Status:Status,Percentage:PercentageComplete}"
```

---

### 16. SSM Session Manager "Not connected"

**What it means:** on some AMI variants, `amazon-ssm-agent` isn't
pre-installed even though IAM permissions (`AmazonSSMManagedInstanceCore`)
are correctly attached.

**Status:** already fixed — `modules/compute/user-data.sh` explicitly
installs it: `dnf install -y amazon-ssm-agent` and
`systemctl enable amazon-ssm-agent --now`.

**If it's still not connecting:**
1. Check the instance's `SSM agent status` in the boot console log (the diagnostic block prints `systemctl status amazon-ssm-agent`).
2. Confirm the instance actually has internet egress: general connectivity (e.g. successful `docker pull` earlier in the same log) proves the NAT Gateway/route table are fine, so if SSM still fails, it's specifically the agent, not the network.
3. Give it a few minutes after boot — first-time registration isn't instant.

---

### 17. Domain resolves NS but no A record

**Symptom:** `nslookup -type=NS <domain>` correctly shows the Route 53
nameservers (so GoDaddy delegation worked), but `nslookup <domain>` (no
`-type=NS`) returns no IP at all.

**What it means:** when `enable_cloudfront = false`, the CloudFront-aliased
DNS records are correctly skipped — but nothing was ever created to
replace them, so the domain has **no A record whatsoever**.

**Status:** already fixed — `modules/edge/main.tf` includes `apex_alb`
and `www_alb` records that alias the domain straight to the ALB whenever
`enable_cloudfront` is `false`.

**If you still see this:** confirm those two resources are actually in
your plan/state (`terraform state list | Select-String "alb\b"`), and
check `aws route53 list-resource-record-sets --hosted-zone-id <zone-id>
--profile <profile> --query "ResourceRecordSets[?Type=='A']"` — if the
record genuinely exists there but the browser/`nslookup` still doesn't
see it, it's DNS-resolver caching, not a real problem; wait a few minutes
and re-check.

---

### 18. PowerShell: `'charmap' codec can't encode character`

**What it means:** `aws ec2 get-console-output` returned a Unicode
character (commonly an arrow `→` from a systemd log line) that
PowerShell's default console encoding can't display, crashing the
command before it finishes.

**Fix:** force UTF-8 and redirect to a file instead of printing directly:
```powershell
$env:PYTHONUTF8="1"
aws ec2 get-console-output --instance-id <id> --profile <profile> --query Output --output text | Out-File -FilePath console.txt -Encoding utf8
Get-Content console.txt
```
If the file still comes back empty, try the raw JSON form instead (bypasses `--query`/`--output text` entirely):
```powershell
aws ec2 get-console-output --instance-id <id> --profile <profile> --output json | Out-File console_raw.json -Encoding utf8
Get-Content console_raw.json -Tail 5
```

---

### 19. PowerShell: `NativeCommandError` from a normal CLI check

**Symptom:** a script that runs something like
`aws s3api head-bucket --bucket ...` to check if a bucket exists crashes
with a `NativeCommandError`, even though the AWS CLI call itself is
working correctly (a 404 "not found" is an *expected*, normal outcome for
that check).

**What it means:** with `$ErrorActionPreference = "Stop"` set,
PowerShell 7.3+ converts a native command's ordinary stderr output (which
`head-bucket` writes when the bucket doesn't exist) into a **terminating**
exception, crashing the script before it can even look at `$LASTEXITCODE`.

**Status:** already fixed in `bootstrap-backend.ps1` and
`cleanup-everything.ps1` — both set
`$ErrorActionPreference = "Continue"` and
`$PSNativeCommandUseErrorActionPreference = $false` at the top, then
check `$LASTEXITCODE` explicitly after each AWS CLI call instead of
relying on PowerShell's automatic error handling.

If you write your own check-then-act script, follow the same pattern —
never leave `$ErrorActionPreference = "Stop"` active around a native CLI
call whose failure is an expected, normal outcome.

---

### 20. PowerShell: `Invalid JSON` passing `--delete` to AWS CLI

**Symptom:**
```
Invalid JSON: Expecting property name enclosed in double quotes
```
when trying to embed a `list-object-versions` query result directly into
`aws s3api delete-objects --delete "$(...)"`.

**What it means:** PowerShell's command substitution mangles the double
quotes AWS CLI needs around JSON keys — this is a PowerShell quoting
limitation, not an AWS CLI bug.

**Fix:** don't build the JSON via substitution — loop over each key/version
individually with `delete-object` instead (avoids the JSON-quoting problem
entirely):
```powershell
$versions = aws s3api list-object-versions --bucket <bucket> --profile <profile> --query "Versions[].[Key,VersionId]" --output text
$versions -split "`n" | ForEach-Object {
    $parts = $_ -split "`t"
    if ($parts.Length -eq 2) {
        aws s3api delete-object --bucket <bucket> --key $parts[0] --version-id $parts[1] --profile <profile>
    }
}
```
This is exactly what `cleanup-everything.ps1` does for you.

---

### 21. `terraform destroy` errors out / leftovers remain

**What it means:** the same interruption/partial-failure pattern as #1
and #4, just happening during `destroy` instead of `apply` — some
resources get removed from state before AWS finishes deleting them, or a
dependency ordering issue leaves something behind.

**Fix:**
```powershell
cd terraform
terraform destroy
```
Then, whether it finished clean or errored partway, run the sweep +
verification script:
```powershell
cd ..
.\cleanup-everything.ps1
```
Read the verification report at the end — every table should be empty
except a KMS key correctly sitting in `PendingDeletion` (expected AWS
behavior for its deletion window, not a leftover — see the script's own
output note). Anything else non-empty needs a manual look; paste the
specific output for help.

**Remember:** re-deploying after a full teardown creates a **new** Route
53 hosted zone with new nameservers — update GoDaddy again with the
fresh values before expecting the domain to resolve.

<div align="center">

# 🏢 Enterprise Cloud Security Platform

### A production-grade, defense-in-depth AWS infrastructure provisioned entirely with Terraform

Live Demo :  https://www.nitesh.shop

Deploys and runs **NexOps EEMS** — a containerized React + Node.js/Prisma + PostgreSQL application — on a self-healing, auto-scaling, multi-layer-secured AWS backbone, with remote state, encrypted secrets, automated backups, and full audit/compliance tooling wired in from day one.

[![Terraform](https://img.shields.io/badge/Terraform-1.6+-844FBA?style=for-the-badge&logo=terraform&logoColor=white)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Cloud-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/)
[![Docker](https://img.shields.io/badge/Docker-Containers-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://www.docker.com/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-RDS-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![Prisma](https://img.shields.io/badge/Prisma-ORM-2D3748?style=for-the-badge&logo=prisma&logoColor=white)](https://www.prisma.io/)
[![Nginx](https://img.shields.io/badge/Nginx-Reverse_Proxy-009639?style=for-the-badge&logo=nginx&logoColor=white)](https://nginx.org/)
[![Amazon Linux](https://img.shields.io/badge/Amazon_Linux-2023-FF9900?style=for-the-badge&logo=linux&logoColor=white)](https://aws.amazon.com/amazon-linux-2023/)
[![PowerShell](https://img.shields.io/badge/PowerShell-Automation-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](https://learn.microsoft.com/powershell/)

</div>

---

## 📋 Table of Contents

- [Tech Stack](#-tech-stack)
- [Architecture](#-architecture)
- [Security & Compliance Layer](#-security--compliance-layer)
- [Project Structure](#-project-structure)
- [Prerequisites](#-prerequisites)
- [Step-by-Step: Deploy](#-step-by-step-deploy)
- [Custom Domain and HTTPS](#-custom-domain-and-https)
- [Verify It's Actually Live](#-verify-its-actually-live)
- [Monitoring & Alerts](#-monitoring--alerts)
- [Incident History — Real Bugs, Real Fixes](#-incident-history--real-bugs-real-fixes)
- [Tear Down](#-tear-down)
- [What This Demonstrates](#-what-this-demonstrates)

---

## 🛠 Tech Stack

| Layer | Technology |
|---|---|
| **Infrastructure as Code** | Terraform, 12 independent modules, remote state |
| **Compute** | EC2 (Amazon Linux 2023), Auto Scaling Group with automatic rolling instance refresh, Launch Template |
| **Networking** | VPC across 2 AZs, public/private-app/private-db subnet tiers, NAT Gateway, Internet Gateway, S3 + DynamoDB VPC Gateway Endpoints |
| **Load Balancing** | Application Load Balancer, path-based routing (`/api/*` → backend), HTTP→HTTPS redirect, target-group health checks |
| **Database** | RDS PostgreSQL (private subnet, KMS-encrypted storage), Prisma ORM |
| **Storage** | S3 (encrypted, versioned, public-access-blocked) for documents/artifacts/logs |
| **Secrets** | AWS Secrets Manager — DB credentials and JWT signing key, fetched at boot, never baked into the AMI |
| **Containers** | Docker, Docker Hub images, custom bridge network for container-to-container DNS |
| **Reverse Proxy** | Nginx |
| **Security & Audit** | AWS Config (managed compliance rules), CloudTrail, VPC Flow Logs, EventBridge → Lambda automated security response |
| **Monitoring** | CloudWatch Dashboard + Alarms (EC2 CPU, RDS CPU/storage, ALB 5xx, unhealthy targets), SNS → email + SMS |
| **Backup / DR** | AWS Backup — tag-based selection, daily schedule, dedicated vault |
| **IAM** | Least-privilege scoped policies per role, zero SSH — SSM Session Manager only |
| **DNS / TLS** | Route 53 (GoDaddy-delegated), ACM DNS-validated certificates, CloudFront-ready (toggleable) |
| **State Management** | S3 (versioned, encrypted) + DynamoDB (locking), bootstrapped independently of the main stack |

---

## 🏗 Architecture

```
                                   GoDaddy (registrar)
                                          │
                                   nameservers delegated
                                          ▼
                                  Route 53 Hosted Zone ──── ACM DNS validation
                                          │                        │
                                          ▼                        ▼
                              ┌───────────────────── HTTPS/HTTP Application Load Balancer ─────────────────────┐
                              │              (public subnets, 2 AZs)                                            │
                              └──────────────┬───────────────────────────────────┬──────────────────────────────┘
                                       /api/* │                                   │ everything else
                                              ▼                                   ▼
                              ┌────────────────────────── Auto Scaling Group (private app subnets) ─────────────┐
                              │   EC2 (Amazon Linux 2023) × min 2, across 2 AZs, rolling instance refresh        │
                              │   ┌─────────────────┐        ┌──────────────────┐                                │
                              │   │  nginx-frontend │───────▶│  nexops-backend  │                                │
                              │   │  (React build)  │  proxy │  (Node + Prisma) │                                │
                              │   └─────────────────┘        └────────┬─────────┘                                │
                              └────────────────────────────────────────┼──────────────────────────────────────────┘
                                                                        │
                              ┌─────────────────────────────────────────┼───────────────────────────────────────┐
                              │  NAT Gateway (outbound only)             ▼                                        │
                              │                                RDS PostgreSQL (private db subnets, KMS-encrypted)│
                              └───────────────────────────────────────────────────────────────────────────────────┘

  Secrets Manager ──▶ fetched at instance boot (DB credentials, JWT secret)
  S3 (KMS-encrypted) ──▶ documents / artifacts / access logs
  CloudTrail + Config + VPC Flow Logs ──▶ centralized audit trail
  CloudWatch Alarms ──▶ SNS ──▶ email + SMS
  AWS Backup ──▶ tag-based daily RDS snapshots
```

<p align="center">
  <img src="screenshots/03-vpc-diagram.png" alt="VPC diagram showing subnet tiers across Availability Zones" width="800">
  <br><em>VPC — public / private-app / private-db subnet tiers across 2 Availability Zones</em>
</p>

<p align="center">
  <img src="screenshots/02-aws-resource-map.png" alt="AWS VPC resource map" width="800">
  <br><em>AWS Console resource map — every networking piece wired together by Terraform</em>
</p>

---

## 🔐 Security & Compliance Layer

This isn't just "an app on EC2" — it ships with the controls a real platform team would ask for:

- **No SSH, anywhere.** Every EC2 role uses `AmazonSSMManagedInstanceCore`; access is exclusively via SSM Session Manager, fully audit-logged.
- **KMS-encrypted at rest** — EBS volumes, RDS storage, and S3 buckets all use a customer-managed KMS key, with an explicit key-policy grant for the Auto Scaling service-linked role (a commonly-missed requirement — see [Incident History](#-incident-history--real-bugs-real-fixes)).
- **Least-privilege IAM** — the EC2 role can only read the two specific secrets it needs and write to the specific S3 buckets it owns; no wildcard `*` resource policies.
- **AWS Config** — managed rules for `INCOMING_SSH_DISABLED` and `S3_BUCKET_PUBLIC_READ_PROHIBITED`, continuously evaluated.
- **CloudTrail + VPC Flow Logs** — every API call and every network flow is logged to a dedicated, encrypted S3 bucket.
- **Automated response** — an EventBridge rule triggers a Lambda function on selected security findings.
- **Secrets never touch disk in plaintext** — pulled from Secrets Manager at boot time via the instance's IAM role, injected directly into the container environment.
- **Backups** — AWS Backup takes daily snapshots via tag-based selection (`Environment=production`), independent of manual RDS snapshot habits.

<p align="center">
  <img src="screenshots/11-secrets-manage.png" alt="AWS Secrets Manager showing DB credentials and app secrets" width="700">
  <br><em>Secrets Manager — DB credentials and JWT key, never hardcoded</em>
</p>

<p align="center">
  <img src="screenshots/12-kms-key.png" alt="KMS customer-managed key used for encryption at rest" width="700">
  <br><em>Customer-managed KMS key encrypting EBS, RDS, and S3</em>
</p>

<p align="center">
  <img src="screenshots/14-aws-config-rules.png" alt="AWS Config compliance rules showing SSH restricted and S3 public-read prohibited" width="700">
  <br><em>AWS Config — continuously-evaluated compliance rules</em>
</p>

<p align="center">
  <img src="screenshots/13-cloudtrail-guardrail.png" alt="CloudTrail trail actively logging account activity" width="700">
  <br><em>CloudTrail — full account activity audit trail</em>
</p>

<p align="center">
  <img src="screenshots/15-backup-plan.png" alt="AWS Backup plan and vault with tag-based selection" width="700">
  <br><em>AWS Backup — automated daily RDS backups via tag-based selection</em>
</p>

---

## 📁 Project Structure

```
enterprise-cloud-security-platform/
│
├── bootstrap-backend.ps1        # one-time: creates the S3 state bucket + DynamoDB lock table
├── cleanup-everything.ps1       # full account teardown + leftover-resource sweep + verification report
├── DEPLOY-STEPS.md              # condensed step-by-step deploy runbook
│
└── terraform/
    ├── main.tf                  # wires all 12 modules together
    ├── variables.tf / terraform.tfvars
    ├── backend.tf                # S3 + DynamoDB remote state config
    ├── providers.tf               # us-east-1 aliased provider for CloudFront/ACM
    ├── outputs.tf
    └── modules/
        ├── networking/            # VPC, 3-tier subnets, NAT, IGW, route tables, VPC endpoints
        ├── security-groups/       # ALB / app / db tier security groups
        ├── iam/                    # EC2 role, Lambda role, scoped inline policies
        ├── storage/                # S3 buckets + KMS key (with ASG service-linked-role grant)
        ├── secrets/                # Secrets Manager: DB credentials, JWT secret
        ├── database/               # RDS PostgreSQL, parameter group, subnet group
        ├── compute/                # Launch Template, Auto Scaling Group, user-data bootstrap script
        ├── load-balancer/          # ALB, target groups, listeners, path-based routing
        ├── edge/                   # Route 53 zone, ACM certs, CloudFront (toggleable), DNS records
        ├── backup/                 # AWS Backup vault, plan, tag-based selection
        ├── monitoring/             # CloudWatch dashboard, alarms, SNS (email + SMS)
        └── security-monitoring/    # CloudTrail, Config, VPC Flow Logs, Lambda auto-response
```

---

## ✅ Prerequisites

- **Terraform** ≥ 1.6.0 — verify with `terraform version`
- **AWS CLI v2**, configured with a named profile — verify with `aws sts get-caller-identity --profile <your-profile>`
- **PowerShell** (Windows) — the bootstrap/cleanup scripts are written for it; adapt to bash if deploying from Linux/macOS
- An **AWS account** with sufficient service quotas (VPC, EIP, NAT Gateway, RDS)
- **Docker Hub account** with the application images already pushed
- *(Optional)* A registered domain — this project was built and tested against a GoDaddy-registered domain delegated to Route 53

---

## 🚀 Step-by-Step: Deploy

### 1. Bootstrap the remote state backend *(one-time, per AWS account)*

```powershell
cd enterprise-cloud-security-platform
Unblock-File .\bootstrap-backend.ps1
.\bootstrap-backend.ps1
```

This creates (or safely reuses, if already present) the versioned/encrypted S3 state bucket and the DynamoDB lock table, using naming that already matches `terraform/backend.tf` — no manual editing needed unless your AWS account ID differs from the one baked into the bucket name.

<p align="center">
  <img src="screenshots/17-s3-state-bucket-versioning.png" alt="S3 state bucket with versioning enabled" width="700">
  <br><em>Remote state bucket — versioned and encrypted, so every apply is recoverable</em>
</p>

<p align="center">
  <img src="screenshots/18-dynamodb-lock-table.png" alt="DynamoDB table used for Terraform state locking" width="700">
  <br><em>DynamoDB lock table — prevents two people (or two terminals) applying at once</em>
</p>

### 2. Configure your variables

```powershell
cd terraform
notepad terraform.tfvars
```

Set (at minimum): `db_password` (change this — don't ship the sample value), `alarm_email`, `alarm_phone_number` *(optional, for SMS)*, `domain_name`, `frontend_image`, `backend_image`. Leave `enable_cloudfront = false` until your AWS account has been verified by AWS Support for CloudFront (new accounts are blocked by default — see Incident History).

### 3. Init, validate, plan

```powershell
terraform init
terraform validate
terraform fmt -recursive
terraform plan -out=tfplan
```

**Always review the plan before applying.** On a blank account this should show only `will be created` — no updates, no destroys:

```powershell
terraform show -no-color tfplan | Select-String "^  #"
```

### 4. Apply

```powershell
terraform apply tfplan
```

Expect 15–20 minutes — the NAT Gateway, RDS instance, and ASG capacity wait are the slow parts. **Do not interrupt the network connection mid-apply** (see the very first entry in [Incident History](#-incident-history--real-bugs-real-fixes)) — an unstable Wi-Fi/VPN connection during apply is the single most common cause of a messy, hard-to-diagnose partial state.

<p align="center">
  <img src="screenshots/01-terraform-apply-success.png" alt="Terraform apply complete with resource count" width="700">
  <br><em>Clean apply — every module created with zero manual AWS Console steps</em>
</p>

### 5. Point the domain at Route 53

```powershell
terraform output route53_zone_id
aws route53 get-hosted-zone --id <zone-id> --profile <your-profile> --query "DelegationSet.NameServers"
```

Copy those four `ns-xxxx.awsdns-xx.___` values into GoDaddy → your domain → DNS → Nameservers → **Custom**. Propagation can take anywhere from 15 minutes to a day; verify before assuming anything is broken:

```powershell
nslookup -type=NS <your-domain>
```

<p align="center">
  <img src="screenshots/20-godaddy-nameservers.png" alt="GoDaddy nameserver settings pointed at Route 53" width="600">
  <br><em>GoDaddy registrar delegated to the Route 53 nameservers</em>
</p>

---

## 🌐 Custom Domain and HTTPS

```text
GoDaddy registrar
      │  nameservers delegated
      ▼
Route 53 Hosted Zone
      │
      ├── A/ALIAS → ALB   (direct fallback when CloudFront is disabled)
      └── ACM DNS validation → HTTPS ALB listener
```

When `enable_cloudfront = false` (the default, until your account is verified), Route 53 aliases the apex and `www` records **directly to the ALB** — this is a deliberate fallback path, not a missing feature; without it the domain would have no A record at all and would never resolve to anything. Once AWS Support verifies your account for CloudFront, flip `enable_cloudfront = true` and re-apply to switch to the CDN-fronted path with its own WAF Web ACL.

<p align="center">
  <img src="screenshots/19-route53-hosted-zone.png" alt="Route 53 hosted zone with A record aliased to the ALB" width="700">
  <br><em>Route 53 hosted zone — custom domain resolving straight to the ALB</em>
</p>

---

## 🔍 Verify It's Actually Live

```powershell
terraform output alb_dns_name
```

Open `http://<that-value>` first — confirms the app works before DNS is even in the picture.

```powershell
aws elbv2 describe-target-health --target-group-arn (terraform output -raw backend_target_group_arn) --profile <your-profile>
aws elbv2 describe-target-health --target-group-arn (terraform output -raw frontend_target_group_arn) --profile <your-profile>
```

Both target groups should report `healthy` targets.

<p align="center">
  <img src="screenshots/04-asg-instances-healthy.png" alt="Auto Scaling Group showing 2 healthy running instances" width="700">
  <br><em>Auto Scaling Group — 2 instances, InService, across both Availability Zones</em>
</p>

<p align="center">
  <img src="screenshots/05-alb-target-groups-healthy.png" alt="ALB target groups showing both frontend and backend targets healthy" width="700">
  <br><em>Both target groups healthy — this took 15 root-caused bugs to get right (see Incident History)</em>
</p>

<p align="center">
  <img src="screenshots/06-ec2-instance-details.png" alt="EC2 instance detail page with SSM connected" width="700">
  <br><em>EC2 instance — SSM Session Manager connected, no SSH key required</em>
</p>

Then, once DNS has propagated, open it in a browser:

<p align="center">
  <img src="screenshots/07-app-live-domain.png" alt="NexOps EEMS application running live in the browser on the custom domain" width="800">
  <br><em>Application live on the custom domain</em>
</p>

<p align="center">
  <img src="screenshots/08-app-api-response.png" alt="Backend API health check responding" width="600">
  <br><em>Backend API responding at <code>/api/health</code></em>
</p>

<p align="center">
  <img src="screenshots/16-rds-instance.png" alt="RDS PostgreSQL instance running, encrypted, in a private subnet" width="700">
  <br><em>RDS PostgreSQL — private subnet, KMS-encrypted storage, automated backups</em>
</p>

**To inspect the database directly** (it's in a private subnet — SSM Session Manager is the way in, not a public DB client):

```powershell
aws ssm start-session --target <instance-id> --profile <your-profile>
# inside the session:
docker exec nexops-backend env | grep DATABASE_URL
psql "<paste the DATABASE_URL value>"
```

---

## 📈 Monitoring & Alerts

CloudWatch alarms (EC2 CPU, RDS CPU, RDS free storage, ALB 5xx rate, target-group unhealthy-host count) publish to an SNS topic with both an email and (optionally) an SMS subscription. **Confirm the SNS email subscription** the first time you deploy — alarms are silent until that's done:

> Check the inbox for `alarm_email` → click "Confirm subscription" in the AWS SNS email.

> **India numbers:** SNS SMS to Indian mobile numbers requires TRAI DLT sender-ID registration; without it, SMS delivery silently fails while email continues to work normally.

<p align="center">
  <img src="screenshots/09-cloudwatch-dashboard.png" alt="CloudWatch dashboard showing EC2 and RDS CPU metrics" width="700">
  <br><em>Custom CloudWatch dashboard — EC2 and RDS metrics at a glance</em>
</p>

<p align="center">
  <img src="screenshots/10-cloudwatch-alarms.png" alt="CloudWatch alarms list, all in OK state" width="700">
  <br><em>CloudWatch alarms — CPU, storage, 5xx rate, and unhealthy-host thresholds, all watched continuously</em>
</p>

---

## 🩹 Incident History — Real Bugs, Real Fixes

This project was hardened through an actual multi-day deployment, not written once and assumed correct. Every one of these was hit, diagnosed, and fixed for real:

| # | Symptom | Root Cause | Fix |
|---|---|---|---|
| 1 | `dial tcp: lookup ...amazonaws.com: no such host` on random services mid-apply | Local machine's Wi-Fi/VPN dropped for a moment during a long apply | Not a code bug — stabilize the network, then re-plan/re-apply; Terraform safely resumes from state |
| 2 | `Error acquiring the state lock` | A previous apply was interrupted and never released its DynamoDB lock | `terraform force-unlock <LOCK_ID>` |
| 3 | `creating Secrets Manager Secret: ... already scheduled for deletion` | A secret from an earlier interrupted run was sitting in its 30-day recovery window | Set `recovery_window_in_days = 0` on both secrets (this is a dev/iterate-fast project); force-delete the stuck ones once with the AWS CLI |
| 4 | `EntityAlreadyExists` / `DBParameterGroupAlreadyExists` / `BucketNotEmpty` on re-apply after a partial failure | Resources created on AWS during a partial/interrupted apply weren't yet tracked in Terraform state | `cleanup-everything.ps1` force-removes every one of these leftovers and re-verifies the account is clean |
| 5 | AWS Backup `InvalidParameterValueException: ResourceId does not match the expected format` | Wildcard RDS ARN passed directly into `resources` | Switched to tag-based selection (`condition` block + `resources = ["*"]`); note the provider's block is singular `condition`, not `conditions` |
| 6 | ASG stuck at "0 healthy instances" until timeout | Customer-managed KMS key policy didn't grant the Auto Scaling **service-linked role** permission to create grants for encrypted EBS volumes — only the instance role had access | Added an explicit KMS key-policy statement for `AWSServiceRoleForAutoScaling` |
| 7 | `CreateDistributionWithTags: AccessDenied — account must be verified` | New AWS accounts are blocked from CloudFront until AWS Support verifies them | Added an `enable_cloudfront` toggle (default `false`); Route 53 falls back to aliasing the domain directly at the ALB until verification completes |
| 8 | CloudWatch dashboard always showed "No data" | Dashboard widgets hardcoded `region: "us-east-1"` regardless of actual deployment region | Use `var.aws_region` in every widget |
| 9 | `BucketAlreadyOwnedByYou` on the state bucket | The `storage` module's bucket-naming logic happened to produce the **exact same name** as the externally-bootstrapped Terraform state bucket | Removed the redundant `terraform_state` bucket key from the module entirely |
| 10 | ALB targets permanently unhealthy, backend container stuck in a restart loop | Missing `DATABASE_URL` / `DIRECT_URL` — the backend uses Prisma ORM, which needs a full connection string, not individual `DB_HOST`/`DB_USER` vars | Constructed `postgresql://user:pass@host:port/db?schema=public` in the boot script and passed it as both `DATABASE_URL` and `DIRECT_URL` |
| 11 | Frontend container crash-looping: `nginx: [emerg] host not found in upstream "nexops-backend"` | The frontend's baked-in nginx config expects a container literally named `nexops-backend`; the boot script had named it `eems-backend` | Renamed the container to match |
| 12 | Launch template changes never triggered an instance refresh | `version = "$Latest"` is a literal string that never "changes" from Terraform's point of view, so the `instance_refresh` trigger never fired | Reference `aws_launch_template.app.latest_version` instead — a genuinely incrementing value |
| 13 | SSM Session Manager permanently shows "Not connected" | This AMI variant doesn't ship `amazon-ssm-agent` pre-installed | Explicitly `dnf install -y amazon-ssm-agent` and enable it in the boot script |
| 14 | Backend target healthy internally but ALB health check returns `404` | Health check path was `/health`; the app actually exposes `/api/health` | Verified the real path via SSM (`curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/api/health`) and corrected the target group |
| 15 | Domain resolves via `nslookup -type=NS` but never gets an IP | `enable_cloudfront=false` disabled the CloudFront-aliased DNS records but never created a replacement — the domain had **no A record at all** | Added `apex_alb`/`www_alb` fallback records aliasing straight to the ALB whenever CloudFront is off |

Full context for each of these — the diagnostic commands used and why — is preserved as design commentary directly in the relevant `.tf` files and `user-data.sh`.

---

## 🧹 Tear Down

```powershell
cd terraform
terraform destroy
```

If `destroy` errors out partway (leftover IAM roles, secrets stuck in their recovery window, an RDS parameter group that survived, etc.), don't clean up by hand — run the sweep script:

```powershell
cd ..
Unblock-File .\cleanup-everything.ps1
.\cleanup-everything.ps1
```

It force-removes every leftover this project has hit in practice (IAM role/instance profile, RDS parameter/subnet groups, Secrets Manager secrets, the bootstrap S3 state bucket, the DynamoDB lock table), then prints a full verification report across every AWS service this stack touches. Anything it reports as non-empty (aside from a KMS key correctly sitting in its `PendingDeletion` window, which is expected AWS behavior, not a leftover) needs a manual look.

**Re-deploying after a full teardown:** the Route 53 hosted zone gets recreated with **new** nameservers — you'll need to update GoDaddy again with the fresh values from `terraform output route53_zone_id`.

---

## 💡 What This Demonstrates

- Infrastructure as Code with 12 independent, composable Terraform modules — networking, security, IAM, storage, secrets, database, compute, load balancing, edge/DNS, backup, monitoring, and security/compliance as separate concerns
- Remote state with S3 (versioned + encrypted) and DynamoDB locking, bootstrapped independently of the main stack
- High availability: multi-AZ Auto Scaling Group behind an Application Load Balancer, with **automatic** zero-downtime rolling deploys via a correctly-wired instance refresh
- Defense-in-depth security: KMS encryption everywhere, least-privilege IAM, zero SSH (SSM only), private subnets for app and database tiers, AWS Config compliance rules, CloudTrail + VPC Flow Logs, and an automated Lambda security response
- Secrets management via AWS Secrets Manager — nothing hardcoded, nothing baked into the AMI
- Proactive monitoring: CloudWatch alarms → SNS → email/SMS, before a user ever reports a problem
- Automated backup/DR posture via AWS Backup, independent of manual snapshot discipline
- **Real incident response, not a sanitized success story** — see [Incident History](#-incident-history--real-bugs-real-fixes) for 15 genuine bugs hit, diagnosed with production debugging techniques (SSM exec, EC2 console output, target-health inspection, CloudWatch), and fixed at the root cause

---

<div align="center">

Built by **Nitesh** — Enterprise Cloud Security Platform, an end-to-end AWS infrastructure project.

</div>

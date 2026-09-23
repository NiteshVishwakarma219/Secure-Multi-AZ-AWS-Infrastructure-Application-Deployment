# Security Architecture

## Layered defense

```
Internet
   │
   ▼
CloudFront  (TLS termination at edge, caching)
   │
   ▼
WAF          (managed rule groups + rate limiting, scope=CLOUDFRONT)
   │
   ▼
ALB          (TLS 1.2+ only, security group allows 443/80 from 0.0.0.0/0 only)
   │
   ▼
EC2 (Docker) (security group allows 80/8000 from ALB SG only — never from 0.0.0.0/0)
   │
   ▼
RDS          (security group allows 5432 from App SG only; also has no internet route)
```

## Security groups (least-exposure model)

| SG | Inbound | From |
|---|---|---|
| ALB SG | 443, 80 | `0.0.0.0/0` (80 exists only to redirect to 443 at the listener) |
| App SG | 80, 8000 | ALB SG only |
| DB SG | 5432 | App SG only |

No security group in this project allows `0.0.0.0/0 -> 22` (SSH). There is no
SSH inbound rule anywhere in the app or DB security groups at all.

## Administration without SSH

```
Administrator -> AWS Systems Manager (Session Manager) -> Private EC2
```

The EC2 instance role includes `AmazonSSMManagedInstanceCore` and nothing
resembling `AdministratorAccess`. There is no key pair (`key_name`) configured
on the launch template, so there is no SSH private key to leak, rotate, or
lose in the first place.

## IAM least privilege

The EC2 role can:
- Register with SSM and send CloudWatch metrics/logs (AWS managed policies
  scoped to those specific services)
- `secretsmanager:GetSecretValue` on exactly two secret ARNs
- `s3:GetObject`/`PutObject`/`ListBucket` on exactly two bucket ARNs (and
  their `/*` objects)
- `kms:Decrypt`/`DescribeKey` on exactly one KMS key ARN

The EC2 role **cannot**: create/delete other AWS resources, read other
secrets, read other buckets, or use other KMS keys.

## Encryption inventory

| Layer | Mechanism |
|---|---|
| RDS | Storage encrypted at rest via the project KMS key |
| S3 | SSE-KMS on all four buckets, bucket-key enabled |
| EBS | Root volume encrypted via the project KMS key |
| Secrets Manager | Encrypted via the project KMS key |
| In transit (edge) | CloudFront viewer TLS (`TLSv1.2_2021` minimum) |
| In transit (ALB) | ACM certificate, `ELBSecurityPolicy-TLS13-1-2-2021-06` |

## Detection & audit

| Question | Answered by |
|---|---|
| "Who did what in AWS?" | CloudTrail (multi-region, log file validation enabled) |
| "What traffic flowed where in the VPC?" | VPC Flow Logs -> CloudWatch Logs |
| "Is anything behaving suspiciously?" | GuardDuty |
| "Is this resource configured securely (right now, historically)?" | AWS Config + managed rules (`S3_BUCKET_PUBLIC_READ_PROHIBITED`, `INCOMING_SSH_DISABLED`) |
| "What's our overall security posture?" | Security Hub (aggregates GuardDuty + Config + CIS benchmark) |
| "Can we react automatically to a finding?" | EventBridge (GuardDuty Finding) -> Lambda -> SNS |

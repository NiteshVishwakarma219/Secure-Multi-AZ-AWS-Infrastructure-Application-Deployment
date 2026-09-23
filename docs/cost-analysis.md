# Cost Analysis & Strategy

The AWS Free Tier has ended for this account, so cost is a first-class
design constraint, not an afterthought (§39).

## Two configurations, one codebase

| Component | Learning/dev config (defaults) | Production-style config |
|---|---|---|
| NAT Gateway | 1 shared (`single_nat_gateway = true`) | 1 per AZ (`single_nat_gateway = false`) |
| RDS | Single-AZ (`db_multi_az = false`) | Multi-AZ (`db_multi_az = true`) |
| ASG size | min 2 / desired 2 / max 4 | same, or higher depending on load testing |
| CloudFront/WAF | Always on (both are pay-per-use, low idle cost) | same |
| GuardDuty/Config/Security Hub | Always on for the demo window, then disabled/destroyed | Always on continuously |

## "Deploy → test → capture evidence → destroy" services

Some services exist purely to demonstrate a capability for the report and
don't need to run 24/7 for a student project:

- GuardDuty, Security Hub, and AWS Config can be enabled, given time to
  generate findings/evaluations, screenshotted for `docs/testing-evidence.md`,
  and then disabled between work sessions.
- The full stack (`terraform apply`) can be brought up for a testing
  session and `terraform destroy`-ed afterward — remote state means nothing
  is lost by doing this repeatedly.

## Rough monthly cost shape (us-east-1, illustrative — always verify against
current AWS pricing)

| Item | Approx. driver |
|---|---|
| NAT Gateway(s) | Hourly charge x count, + data processed per GB |
| ALB | Hourly charge + LCU usage |
| EC2 (t3.small x2, ASG) | Hourly charge x instance-hours |
| RDS (db.t3.micro) | Hourly charge, x2 if Multi-AZ |
| CloudFront | Pay-per-request/GB, generally low for a small demo app |
| GuardDuty/Config/Security Hub | Pay-per-event-analyzed; low but non-zero |
| S3/CloudWatch Logs | Storage + request cost, kept small via lifecycle rules (30-day IA transition, 365-day expiration on logs) |

The single biggest lever for a student budget is **NAT Gateway count** and
**RDS Multi-AZ** — both are explicit toggles in `terraform.tfvars`, not
hardcoded choices.

# Architecture

## High-level flow

```
Internet -> Route53 -> CloudFront -> WAF -> ALB (public subnets, 2 AZs)
   -> EC2/ASG running Docker (private app subnets, 2 AZs)
      - nexops-frontend:1.0.0 (port 80)
      - nexops-backend:1.0.0  (port 8000)
   -> RDS PostgreSQL (private DB subnets, Multi-AZ optional)
```

## Why this shape

- **CloudFront + WAF in front of the ALB**: TLS termination at the edge,
  caching for static frontend assets, and managed WAF rule groups
  (`AWSManagedRulesCommonRuleSet`, `AWSManagedRulesKnownBadInputsRuleSet`)
  plus a rate-based rule, before traffic ever reaches the VPC.
- **ALB in public subnets, everything else private**: the only thing with a
  public IP that actually needs one is the load balancer (and NAT gateways,
  which only send traffic *out*).
- **App tier in an Auto Scaling Group across 2 AZs**: no single point of
  compute failure; the ASG replaces unhealthy instances automatically.
- **RDS in an isolated DB subnet group with no internet route at all**: even
  if the DB security group were misconfigured, there is no route out of that
  subnet to the internet — defense in depth, not just security groups.

## Service selection reasoning (§17, §18, §42)

| Service | Used? | Why / why not |
|---|---|---|
| RDS PostgreSQL | Yes | EEMS data is relational (users, employees, departments, leave, roles, audit) with foreign keys and transactions — a relational engine is the right tool. |
| DynamoDB | Not by default | No current workload needs single-digit-ms key-value access or has no natural relational shape. If Lambda automation grows (idempotency keys, automation run state), that's the natural DynamoDB use case — add it then, not before. |
| EFS | No | No component needs a POSIX filesystem shared by multiple EC2 instances concurrently. Application state lives in RDS; file uploads belong in S3, not on a shared instance disk. |
| SQS | Not by default | Email notifications and other background work are currently synchronous inside the backend. If that starts blocking request latency, introduce SQS + a worker/Lambda then, with the trade-off documented (added latency-hiding vs. added moving parts). |
| SNS | Yes | Used for exactly one thing: fanning CloudWatch alarms out to email. Simple, matches the actual need. |
| Lambda | Yes | Event-driven only (GuardDuty finding -> notify/remediate). Not used to run the EEMS backend itself — that's what the ASG is for. |

## NAT Gateway trade-off (§7)

| Config | Cost | Behavior |
|---|---|---|
| `single_nat_gateway = true` (default here) | 1x NAT Gateway cost | Both AZs share one NAT. If that NAT's AZ has an outage, **both** AZs' app instances lose outbound internet access (they can still serve traffic already routed to them via the ALB — this only affects *outbound* calls, e.g. pulling package updates or calling external APIs). |
| `single_nat_gateway = false` | 2x NAT Gateway cost | One NAT per AZ. An AZ outage only affects that AZ's outbound path; the other AZ is fully independent. This is the production-recommended configuration. |

This project intentionally documents the trade-off rather than always paying
for the expensive option — see `docs/cost-analysis.md`.

## Data flow: secrets

```
Terraform creates:
  Secrets Manager: eems/db-credentials  (username + generated password)
  Secrets Manager: eems/app-secrets     (JWT signing key, SMTP creds)

EC2 boot (user_data):
  aws secretsmanager get-secret-value --secret-id eems/db-credentials
  aws secretsmanager get-secret-value --secret-id eems/app-secrets
      -> injected as environment variables into the Docker containers
      -> never written to Terraform state as a literal, never committed to git
```

The EC2 instance role can only `secretsmanager:GetSecretValue` on these two
specific secret ARNs — not `*`.

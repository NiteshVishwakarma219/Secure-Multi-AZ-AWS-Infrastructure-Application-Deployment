# Threat Model (lightweight STRIDE-style pass)

| Threat | Mitigation in this design |
|---|---|
| **Spoofing** — attacker impersonates a legitimate client or the ALB origin | TLS everywhere in the request path (viewer<->CloudFront, CloudFront<->ALB, ALB<->CloudFront cert validated); CloudFront restricted origin (custom origin over HTTPS only) |
| **Tampering** — request/response modified in transit | TLS 1.2+ enforced at both the CloudFront viewer and ALB listener; WAF blocks known malicious payload patterns |
| **Repudiation** — "I didn't do that" / can't reconstruct what happened | CloudTrail (API-level, log file validation), VPC Flow Logs (network-level), RDS `postgresql`/`upgrade` logs exported to CloudWatch |
| **Information disclosure** — credentials or data exposed | No hardcoded secrets anywhere (Secrets Manager only); S3 buckets fully private with Block Public Access enabled; RDS not publicly accessible and has no internet route; IAM scoped to specific ARNs, not `*` |
| **Denial of service** | WAF rate-based rule (2000 req / 5 min per IP); ASG + ALB health checks replace failed capacity automatically; CloudFront absorbs/caches at the edge |
| **Elevation of privilege** — a compromised EC2 instance is used to pivot | EC2 role cannot touch IAM, cannot assume other roles, cannot reach other secrets/buckets/keys; SSM (not SSH) means no long-lived credential material sits on the box; IMDSv2 enforced (`http_tokens = required`) to blunt SSRF-to-credential-theft |

## Assumptions and residual risk

- Application-layer input validation (SQLi/XSS beyond what WAF's managed
  rule groups catch) is the responsibility of the EEMS codebase itself —
  infrastructure controls are a second layer, not a substitute for secure
  coding.
- Container image provenance (`cloudwithnitesh/nexops-*`) is trusted as
  given by the project brief; a production rollout would add image
  scanning (e.g., ECR + Inspector) before pulling from a public registry.
- This model covers the platform in `main.tf`. It does not cover physical
  security, AWS's own infrastructure (covered by the AWS shared
  responsibility model), or supply-chain risk in the Terraform providers
  themselves.

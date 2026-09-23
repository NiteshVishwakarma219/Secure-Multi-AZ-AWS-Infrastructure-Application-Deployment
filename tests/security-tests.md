# Security Tests

- Confirm port 22 is not open to the internet.
- Confirm RDS has `publicly_accessible = false`.
- Confirm S3 public access block is enabled.
- Confirm EC2 uses IMDSv2.
- Confirm secrets are stored in Secrets Manager.
- Confirm CloudTrail, GuardDuty, Security Hub and Config are enabled when their variables are true.

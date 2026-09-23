# Infrastructure Tests

- VPC CIDR is 10.0.0.0/16.
- Two public, two private app and two private DB subnets exist.
- ALB is internet-facing.
- EC2 instances are in private app subnets.
- RDS is private and not publicly accessible.
- App security group accepts application traffic only from the ALB security group.
- DB security group accepts PostgreSQL only from the app security group.
- SSM is used instead of public SSH.

# Network Diagram

## VPC: 10.0.0.0/16, 2 Availability Zones, 6 subnets

```
                                   10.0.0.0/16 (VPC)
   ┌─────────────────────────────────────────────────────────────────┐
   │                     AZ-A                     AZ-B                │
   │  ┌───────────────────────┐   ┌───────────────────────┐          │
   │  │  Public-A 10.0.1.0/24  │   │  Public-B 10.0.2.0/24  │          │
   │  │  - ALB ENI             │   │  - ALB ENI             │          │
   │  │  - NAT Gateway A       │   │  - NAT Gateway B*      │          │
   │  └───────────┬────────────┘   └───────────┬────────────┘          │
   │              │  IGW                          │  IGW               │
   │  ┌───────────▼────────────┐   ┌───────────▼────────────┐          │
   │  │ Private-App-A 10.0.11.0/24│  │ Private-App-B 10.0.12.0/24│      │
   │  │  - EC2 (Docker/EEMS)     │   │  - EC2 (Docker/EEMS)     │       │
   │  │  - part of the ASG       │   │  - part of the ASG       │       │
   │  └───────────┬────────────┘   └───────────┬────────────┘          │
   │              │ 5432                         │ 5432                │
   │  ┌───────────▼────────────┐   ┌───────────▼────────────┐          │
   │  │ Private-DB-A 10.0.21.0/24│  │ Private-DB-B 10.0.22.0/24│        │
   │  │  - RDS PostgreSQL (primary/standby, Multi-AZ)          │        │
   │  │  - NO internet route at all                            │       │
   │  └─────────────────────────┘   └─────────────────────────┘        │
   └─────────────────────────────────────────────────────────────────┘

   * NAT Gateway B only exists when single_nat_gateway = false
```

## Route tables

| Subnet tier | Default route | Notes |
|---|---|---|
| Public | `0.0.0.0/0` -> Internet Gateway | ALB and NAT Gateways live here |
| Private-App | `0.0.0.0/0` -> NAT Gateway (same-AZ NAT, or the single shared NAT) | Outbound only — nothing can initiate inbound from the internet |
| Private-DB | *(none)* | No default route at all. RDS cannot reach, or be reached from, the internet under any security-group misconfiguration |

## Why six subnets instead of fewer

Each tier is a distinct security boundary:

- **Public** → load balancer / NAT only, never application code or data
- **Private-App** → compute that has business logic but no data at rest
- **Private-DB** → the only tier holding persistent employee data, isolated
  two layers deep (security group *and* routing) from the internet

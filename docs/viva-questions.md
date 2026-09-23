# Viva Questions + Answers (starter set)

**Q: Why six subnets instead of a simpler two-subnet (public/private) design?**
A: Each tier is a distinct security boundary. Separating "private app" from
"private db" means the database isn't reachable even by compute that gets
compromised, unless that compute is explicitly the app tier — and even then
only on port 5432 via the security group. It also lets me apply different
routing (the DB tier has no internet route at all, not even via NAT).

**Q: Why not just give the EC2 instance AdministratorAccess and move on?**
A: Least privilege — if that instance is ever compromised, the blast radius
is limited to exactly what it was scoped to do (read two secrets, one KMS
key, two S3 buckets, plus SSM/CloudWatch). AdministratorAccess would turn a
single compromised instance into a full account compromise.

**Q: How do you administer the EC2 instances without SSH?**
A: AWS Systems Manager Session Manager. The instance role includes the SSM
core policy; there's no key pair on the launch template, so there's no SSH
private key to manage or leak, and no port 22 rule anywhere in the security
groups.

**Q: What's the difference between CloudTrail, VPC Flow Logs, and AWS Config?**
A: CloudTrail answers "who called which AWS API and when." VPC Flow Logs
answer "what network traffic flowed between which IPs/ports." AWS Config
answers "what is this resource's configuration right now, and was it ever
non-compliant with a rule" — a snapshot/history of *state*, not activity.

**Q: Why did you choose RDS over DynamoDB for this application?**
A: The data is genuinely relational — employees, departments, leave
requests, and roles have foreign-key relationships and need transactional
consistency. DynamoDB is a better fit for high-throughput key-value or
document access patterns, which this application doesn't have. I didn't add
DynamoDB just to have another AWS service in scope.

**Q: What happens if a NAT Gateway fails?**
A: With `single_nat_gateway = true`, both AZs' app instances lose *outbound*
internet access (things like OS package updates or outbound API calls) —
but the ALB can still route inbound traffic to those instances normally,
since that path doesn't go through NAT. With `single_nat_gateway = false`,
only the affected AZ loses outbound access; the other AZ is unaffected. I
chose the cheaper single-NAT option as the default for a learning
environment and documented the trade-off explicitly rather than hiding it.

**Q: How do secrets get to the application without being hardcoded?**
A: Terraform generates a random DB password and stores it, along with
app secrets like the JWT signing key, in Secrets Manager. At boot, the EC2
instance's user-data script calls `secretsmanager:get-secret-value` (allowed
by its scoped IAM role) and injects the values as environment variables into
the Docker containers. Nothing is written into the AMI, the Docker image, or
committed to Git.

**Q: How would you scale this for higher traffic?**
A: The ASG target-tracking policy already scales EC2 capacity on CPU. For
the database, I'd look at read replicas before vertically scaling the
writer, and for the application layer, CloudFront already offloads static
asset delivery. I'd also revisit whether SQS-based decoupling is now
justified for any newly-added slow background work.

**Q: What did you deliberately choose NOT to deploy, and why?**
A: DynamoDB, SQS, and EFS. None of them have a genuine current use case in
this application — I document the reasoning in `docs/architecture.md` rather
than deploying them just to list more AWS services on a README.

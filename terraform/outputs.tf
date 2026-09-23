output "project_name" {
  description = "Project name"
  value       = var.project_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.networking.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.networking.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private application subnet IDs"
  value       = module.networking.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "Private database subnet IDs"
  value       = module.networking.private_db_subnet_ids
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs"
  value       = module.networking.nat_gateway_ids
}

output "alb_dns_name" {
  description = "Application Load Balancer DNS name"
  value       = module.load_balancer.alb_dns_name
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = module.edge.cloudfront_domain_name
}

output "route53_zone_id" {
  description = "Route 53 hosted zone ID (get its NS records to update at your registrar)"
  value       = module.edge.route53_zone_id
}

output "frontend_target_group_arn" {
  description = "ALB target group ARN for the frontend service"
  value       = module.load_balancer.frontend_tg_arn
}

output "backend_target_group_arn" {
  description = "ALB target group ARN for the backend service"
  value       = module.load_balancer.backend_tg_arn
}

output "db_endpoint" {
  description = "RDS endpoint"
  value       = module.database.db_endpoint
  sensitive   = true
}

output "cloudwatch_dashboard" {
  description = "CloudWatch dashboard name"
  value       = module.monitoring.dashboard_name
}

output "terraform_state_bucket" {
  description = "Terraform state bucket name (managed outside this stack by bootstrap-backend.ps1, shown here for reference only)"
  value       = "${var.project_name}-terraform-state-${data.aws_caller_identity.current.account_id}"
}

output "ec2_instance_profile_name" {
  description = "EC2 instance profile name"
  value       = module.iam.ec2_instance_profile_name
}

output "ec2_role_arn" {
  description = "EC2 IAM role ARN"
  value       = module.iam.ec2_role_arn
}

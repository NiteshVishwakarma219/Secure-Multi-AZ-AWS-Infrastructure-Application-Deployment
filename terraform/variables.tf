variable "aws_region" {
  description = "AWS region for the main infrastructure"
  type        = string
  default     = "ap-south-1"
}

variable "aws_profile" {
  description = "AWS CLI profile used by Terraform. Do not use the root account."
  type        = string
  default     = "nitesh-terraform"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "enterprise-cloud-security-platform"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "azs" {
  description = "Availability Zones used by the project"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "single_nat_gateway" {
  description = "true for lower cost; false creates one NAT Gateway per AZ"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Root domain used for Route 53 and CloudFront"
  type        = string
  default     = "nitesh.shop"
}

variable "create_route53_zone" {
  description = "Set true only when the Route 53 hosted zone does not already exist"
  type        = bool
  default     = true
}

variable "enable_cloudfront" {
  description = "Set false until AWS Support has verified this account for CloudFront. Flip to true and re-apply once verified."
  type        = bool
  default     = false
}

variable "alarm_email" {
  description = "Email for CloudWatch alarm notifications"
  type        = string
  default     = ""
}

variable "alarm_phone_number" {
  description = "E.164 phone number (e.g. +919876543210) for SMS alarm notifications. Leave empty (default) to skip SMS."
  type        = string
  default     = ""
}

variable "db_username" {
  description = "Application database username"
  type        = string
  default     = "eems_admin"
}
variable "db_password" {
  description = "Master password for the PostgreSQL RDS database"
  type        = string
  sensitive   = true

  validation {
    condition = (
      length(var.db_password) >= 8 &&
      !can(regex("[/ @\"]", var.db_password))
    )

    error_message = "db_password must be at least 8 characters and must not contain '/', '@', '\"', or spaces."
  }
}



variable "db_multi_az" {
  description = "Enable RDS Multi-AZ. Use false while learning to reduce cost."
  type        = bool
  default     = false
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "enable_guardduty" {
  type    = bool
  default = true
}

variable "enable_security_hub" {
  type    = bool
  default = true
}

variable "enable_config" {
  type    = bool
  default = true
}

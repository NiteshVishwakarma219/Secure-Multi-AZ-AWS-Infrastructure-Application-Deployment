variable "project_name" {
  type    = string
  default = "eems"
}

variable "ami_id" {
  description = "Amazon Linux 2023 AMI id (region-specific). Leave null to auto-lookup latest."
  type        = string
  default     = null
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "instance_profile_name" {
  type = string
}

variable "app_sg_id" {
  type = string
}

variable "private_app_subnet_ids" {
  type = list(string)
}

variable "target_group_arns" {
  type = list(string)
}

variable "db_credentials_secret_arn" {
  type = string
}

variable "app_secrets_secret_arn" {
  type = string
}

variable "db_endpoint" {
  type = string
}

variable "db_name" {
  description = "Database name the app should connect to"
  type        = string
  default     = "eems"
}

variable "frontend_image" {
  type    = string
  default = "cloudwithnitesh/nexops-frontend:1.0.0"
}

variable "backend_image" {
  type    = string
  default = "cloudwithnitesh/nexops-backend:1.0.0"
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "kms_key_arn" {
  description = "KMS key used to encrypt the root EBS volume"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

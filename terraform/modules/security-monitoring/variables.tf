variable "project_name" {
  type    = string
  default = "eems"
}

variable "vpc_id" {
  type = string
}

variable "logs_bucket_name" {
  type = string
}

variable "logs_bucket_arn" {
  type = string
}

variable "sns_topic_arn" {
  description = "SNS topic to notify on Security Hub / GuardDuty findings"
  type        = string
}

variable "lambda_role_arn" {
  type = string
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

variable "tags" {
  type    = map(string)
  default = {}
}

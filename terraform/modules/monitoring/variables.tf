variable "project_name" {
  type    = string
  default = "eems"
}

variable "aws_region" {
  description = "Region the resources being monitored live in (for dashboard widget metrics)"
  type        = string
}

variable "alarm_phone_number" {
  description = "E.164 phone number (e.g. +919876543210) to receive SMS alerts. Leave empty to skip SMS."
  type        = string
  default     = ""
}

variable "alarm_email" {
  description = "Email address to subscribe to the SNS alarm topic"
  type        = string
}

variable "asg_name" {
  type = string
}

variable "alb_arn_suffix" {
  type = string
}

variable "target_group_arn_suffixes" {
  type = list(string)
}

variable "db_instance_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

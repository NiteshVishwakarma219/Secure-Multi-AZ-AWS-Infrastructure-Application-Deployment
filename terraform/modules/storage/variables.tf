variable "project_name" {
  type    = string
  default = "eems"
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "ec2_role_arn" {
  description = "IAM role ARN allowed to use the platform KMS key"
  type        = string
}
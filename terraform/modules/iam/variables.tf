variable "project_name" {
  type    = string
  default = "eems"
}

variable "secrets_manager_arns" {
  description = "ARNs of Secrets Manager secrets the app tier needs to read"
  type        = list(string)
}

variable "s3_bucket_arns" {
  description = "ARNs of S3 buckets the app tier needs access to (documents, artifacts, logs)"
  type        = list(string)
}

variable "kms_key_arns" {
  description = "ARNs of KMS keys used for secrets/S3/EBS encryption"
  type        = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

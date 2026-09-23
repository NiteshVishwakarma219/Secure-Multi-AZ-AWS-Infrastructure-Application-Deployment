variable "project_name" {
  type    = string
  default = "eems"
}

variable "db_username" {
  type    = string
  default = "eems_admin"
}

variable "kms_key_id" {
  description = "KMS key used to encrypt the secret"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "db_password" {
  description = "Database master password"
  type        = string
  sensitive   = true
}
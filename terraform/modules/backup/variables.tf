variable "project_name" {
  type    = string
  default = "eems"
}

variable "backup_schedule" {
  description = "Cron expression for the backup plan"
  type        = string
  default     = "cron(0 5 * * ? *)" # daily 05:00 UTC
}

variable "retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
variable "backup_tag_value" {
  type    = string
  default = "production"
}
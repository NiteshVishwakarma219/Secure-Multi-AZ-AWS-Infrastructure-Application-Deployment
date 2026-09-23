variable "project_name" {
  type    = string
  default = "eems"
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "backend_port" {
  type    = number
  default = 8000
}

variable "logs_bucket_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
variable "alb_certificate_arn" {
  description = "ACM certificate ARN used by the ALB HTTPS listener"
  type        = string
}
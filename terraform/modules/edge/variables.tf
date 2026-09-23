variable "project_name" {
  type    = string
  default = "eems"
}

variable "domain_name" {
  description = "Root domain, e.g. nitesh.shop"
  type        = string
}

variable "create_route53_zone" {
  description = "Set false if the hosted zone already exists and you just want to look it up"
  type        = bool
  default     = false
}

variable "alb_dns_name" {
  type = string
}

variable "alb_zone_id" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "enable_cloudfront" {
  description = "Set false until AWS Support has verified this account for CloudFront"
  type        = bool
  default     = false
}

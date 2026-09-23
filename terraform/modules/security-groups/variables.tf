variable "project_name" {
  type    = string
  default = "eems"
}

variable "vpc_id" {
  type = string
}

variable "backend_port" {
  description = "Port the EEMS backend container listens on"
  type        = number
  default     = 8000
}

variable "tags" {
  type    = map(string)
  default = {}
}

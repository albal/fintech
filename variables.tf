variable "region" {
  type        = string
  default     = "us-east-1"
  description = "Primary AWS region."
}

variable "name" {
  type        = string
  default     = "fintech"
  description = "Base name used to prefix all resources."
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Environment suffix (dev, stage, prod)."
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "az_count" {
  type        = number
  default     = 2
  description = "Number of AZs to span. The diagram models 2."
}

variable "domain_name" {
  type        = string
  default     = ""
  description = "Optional public domain (e.g. api.example.com). Empty = use AWS-generated endpoints."
}

variable "hosted_zone_id" {
  type        = string
  default     = ""
  description = "Optional Route 53 hosted zone for domain_name above."
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "Primary AWS region."

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.region))
    error_message = "Region must be a valid AWS region identifier like 'us-east-1'."
  }
}

variable "name" {
  type        = string
  default     = "fintech"
  description = "Base name used to prefix all resources."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "Name must be 3-30 chars: lowercase alphanumeric and dashes, starting with a letter."
  }
}

variable "environment" {
  type        = string
  default     = "prod"
  description = "Environment suffix (dev, stage, prod)."

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR (e.g. 10.0.0.0/16)."
  }

  validation {
    condition     = try(tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 24, false)
    error_message = "vpc_cidr prefix must be between /16 and /24 to leave room for subnets."
  }
}

variable "az_count" {
  type        = number
  default     = 2
  description = "Number of AZs to span. The diagram models 2."

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 4
    error_message = "az_count must be between 1 and 4."
  }
}

variable "domain_name" {
  type        = string
  default     = ""
  description = "Optional public domain (e.g. api.example.com). Empty = use AWS-generated endpoints."

  validation {
    condition     = var.domain_name == "" || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.domain_name))
    error_message = "domain_name must be a valid DNS name or empty string."
  }
}

variable "hosted_zone_id" {
  type        = string
  default     = ""
  description = "Optional Route 53 hosted zone for domain_name above."

  validation {
    condition     = var.hosted_zone_id == "" || can(regex("^Z[A-Z0-9]{13,32}$", var.hosted_zone_id))
    error_message = "hosted_zone_id must be a valid Route 53 zone ID (starts with Z) or empty."
  }
}

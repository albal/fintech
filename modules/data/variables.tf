variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "database_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "kms_key_arn" {
  type = string
}

variable "db_master_secret_arn" {
  type = string
}

variable "db_master_secret_version" {
  type        = string
  description = "Forces re-read of the master secret on rotation."
}

variable "tags" {
  type = map(string)
}

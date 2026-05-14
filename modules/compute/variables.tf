variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "kms_key_arn" {
  type = string
}

variable "task_execution_role" {
  type = string
}

variable "task_role" {
  type = string
}

variable "task_role_name" {
  type = string
}

variable "lambda_role_arn" {
  type = string
}

variable "lambda_role_name" {
  type = string
}

variable "db_endpoint" {
  type = string
}

variable "db_secret_arn" {
  type = string
}

variable "redis_endpoint" {
  type = string
}

variable "ledger_table_name" {
  type = string
}

variable "ledger_table_arn" {
  type = string
}

variable "payments_queue_url" {
  type = string
}

variable "payments_queue_arn" {
  type = string
}

variable "aurora_security_group" {
  type = string
}

variable "redis_security_group" {
  type = string
}

variable "tags" {
  type = map(string)
}

variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "kms_key_arn" {
  type = string
}

variable "transfer_role_arn" {
  type = string
}

variable "tags" {
  type = map(string)
}

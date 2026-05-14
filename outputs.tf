output "vpc_id" {
  value = module.network.vpc_id
}

output "alb_dns_name" {
  value       = module.compute.alb_dns_name
  description = "Internal ALB DNS — reachable only via API Gateway VPC link."
}

output "cloudfront_domain" {
  value = module.edge.cloudfront_domain
}

output "api_gateway_endpoint" {
  value = module.edge.api_endpoint
}

output "cognito_user_pool_id" {
  value = module.edge.cognito_user_pool_id
}

output "cognito_client_id" {
  value = module.edge.cognito_client_id
}

output "cognito_hosted_ui_domain" {
  value = module.edge.cognito_domain
}

output "aurora_writer_endpoint" {
  value = module.data.aurora_endpoint
}

output "aurora_reader_endpoint" {
  value = module.data.aurora_reader_endpoint
}

output "redis_endpoint" {
  value = module.data.redis_endpoint
}

output "ledger_table_name" {
  value = module.data.ledger_table_name
}

output "payments_queue_url" {
  value = module.data.payments_queue_url
}

output "payments_dlq_arn" {
  value = module.data.payments_dlq_arn
}

output "audit_log_bucket" {
  value = module.observability.audit_log_bucket_name
}

output "documents_bucket" {
  value = module.observability.documents_bucket_name
}

output "kms_key_arn" {
  value = module.security.kms_key_arn
}

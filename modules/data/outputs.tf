output "aurora_endpoint" {
  value = aws_rds_cluster.aurora.endpoint
}

output "aurora_reader_endpoint" {
  value = aws_rds_cluster.aurora.reader_endpoint
}

output "aurora_security_group_id" {
  value = aws_security_group.aurora.id
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_security_group_id" {
  value = aws_security_group.redis.id
}

output "ledger_table_name" {
  value = aws_dynamodb_table.ledger.name
}

output "ledger_table_arn" {
  value = aws_dynamodb_table.ledger.arn
}

output "idempotency_table_name" {
  value = aws_dynamodb_table.idempotency.name
}

output "payments_queue_url" {
  value = aws_sqs_queue.payments.url
}

output "payments_queue_arn" {
  value = aws_sqs_queue.payments.arn
}

output "payments_dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

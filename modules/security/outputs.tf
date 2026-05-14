output "kms_key_arn" {
  value = aws_kms_key.main.arn
}

output "kms_key_id" {
  value = aws_kms_key.main.id
}

output "db_master_secret_arn" {
  value = aws_secretsmanager_secret.db_master.arn
}

output "db_master_secret_version_id" {
  value = aws_secretsmanager_secret_version.db_master.version_id
}

output "payment_provider_secret_arn" {
  value = aws_secretsmanager_secret.payment_provider.arn
}

output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "ecs_task_role_arn" {
  value = aws_iam_role.ecs_task.arn
}

output "ecs_task_role_name" {
  value = aws_iam_role.ecs_task.name
}

output "lambda_execution_role_arn" {
  value = aws_iam_role.lambda.arn
}

output "lambda_execution_role_name" {
  value = aws_iam_role.lambda.name
}

output "transfer_role_arn" {
  value = aws_iam_role.transfer.arn
}

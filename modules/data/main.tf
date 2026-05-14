terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

data "aws_secretsmanager_secret_version" "db_master" {
  secret_id  = var.db_master_secret_arn
  version_id = var.db_master_secret_version
}

locals {
  db_creds = jsondecode(data.aws_secretsmanager_secret_version.db_master.secret_string)
}

# --- Aurora PostgreSQL ---
resource "aws_security_group" "aurora" {
  name        = "${var.name}-aurora"
  description = "Aurora cluster — ingress is added by compute module"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_db_subnet_group" "aurora" {
  name       = "${var.name}-aurora"
  subnet_ids = var.database_subnet_ids
  tags       = var.tags
}

resource "aws_rds_cluster_parameter_group" "aurora" {
  name   = "${var.name}-aurora-pg15"
  family = "aurora-postgresql15"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = var.tags
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier              = "${var.name}-ledger"
  engine                          = "aurora-postgresql"
  engine_version                  = "15.4"
  database_name                   = "ledger"
  master_username                 = local.db_creds.username
  master_password                 = local.db_creds.password
  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]

  storage_encrypted                   = true
  kms_key_id                          = var.kms_key_arn
  backup_retention_period             = 14
  preferred_backup_window             = "03:00-04:00"
  preferred_maintenance_window        = "Mon:04:00-Mon:05:00"
  deletion_protection                 = true
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.name}-ledger-final"
  copy_tags_to_snapshot               = true

  tags = var.tags

  lifecycle {
    ignore_changes = [master_password]
  }
}

resource "aws_rds_cluster_instance" "aurora" {
  count                           = 2
  identifier                      = "${var.name}-ledger-${count.index}"
  cluster_identifier              = aws_rds_cluster.aurora.id
  instance_class                  = "db.r6g.large"
  engine                          = aws_rds_cluster.aurora.engine
  engine_version                  = aws_rds_cluster.aurora.engine_version
  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  performance_insights_enabled    = true
  performance_insights_kms_key_id = var.kms_key_arn
  monitoring_interval             = 60
  auto_minor_version_upgrade      = true
  tags                            = var.tags
}

# --- ElastiCache Redis ---
resource "aws_security_group" "redis" {
  name        = "${var.name}-redis"
  description = "Redis — ingress is added by compute module"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.name}-redis"
  subnet_ids = var.private_subnet_ids
}

resource "random_password" "redis_auth" {
  length  = 32
  special = false
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${var.name}-redis"
  description                = "Sessions and hot lookups"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = "cache.r6g.large"
  num_cache_clusters         = 2
  parameter_group_name       = "default.redis7"
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis.id]
  automatic_failover_enabled = true
  multi_az_enabled           = true
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth.result
  kms_key_id                 = var.kms_key_arn
  snapshot_retention_limit   = 7
  snapshot_window            = "05:00-06:00"
  apply_immediately          = false
  tags                       = var.tags
}

# --- DynamoDB ---
resource "aws_dynamodb_table" "ledger" {
  name         = "${var.name}-ledger"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "account_id"
  range_key    = "tx_id"

  attribute {
    name = "account_id"
    type = "S"
  }

  attribute {
    name = "tx_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  deletion_protection_enabled = true

  tags = var.tags
}

resource "aws_dynamodb_table" "idempotency" {
  name         = "${var.name}-idempotency"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "key"

  attribute {
    name = "key"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = var.tags
}

# --- SQS ---
resource "aws_sqs_queue" "dlq" {
  name                              = "${var.name}-payments-dlq"
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300
  message_retention_seconds         = 1209600 # 14 days
  tags                              = var.tags
}

resource "aws_sqs_queue" "payments" {
  name                              = "${var.name}-payments"
  kms_master_key_id                 = var.kms_key_arn
  kms_data_key_reuse_period_seconds = 300
  visibility_timeout_seconds        = 60
  message_retention_seconds         = 345600 # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })

  tags = var.tags
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.payments.arn]
  })
}

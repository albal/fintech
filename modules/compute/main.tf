data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# --- Security groups ---
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Internal ALB — ingress from API Gateway VPC link only"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_security_group" "ecs" {
  name        = "${var.name}-ecs"
  description = "ECS Fargate tasks"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_security_group" "lambda" {
  name        = "${var.name}-lambda"
  description = "Lambda payment + fraud services"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_egress_rule" "lambda_all" {
  security_group_id = aws_security_group.lambda.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "ecs_all" {
  security_group_id = aws_security_group.ecs.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.ecs.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "ecs_from_alb" {
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_ecs" {
  security_group_id            = var.aurora_security_group
  referenced_security_group_id = aws_security_group.ecs.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_lambda" {
  security_group_id            = var.aurora_security_group
  referenced_security_group_id = aws_security_group.lambda.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_ecs" {
  security_group_id            = var.redis_security_group
  referenced_security_group_id = aws_security_group.ecs.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_lambda" {
  security_group_id            = var.redis_security_group
  referenced_security_group_id = aws_security_group.lambda.id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
}

# --- Internal ALB ---
resource "aws_lb" "main" {
  name                       = "${var.name}-alb"
  internal                   = true
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.private_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = true
  tags                       = var.tags
}

resource "aws_lb_target_group" "ecs" {
  name        = "${var.name}-ecs-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 30
  tags                 = var.tags
}

# HTTP because TLS terminates at API GW. For end-to-end TLS, attach an ACM cert
# (or an internal PCA cert) and switch to HTTPS on 443.
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs.arn
  }
}

# --- ECS ---
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/aws/ecs/${var.name}"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

resource "aws_ecs_cluster" "main" {
  name = "${var.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  configuration {
    execute_command_configuration {
      kms_key_id = var.kms_key_arn
      logging    = "OVERRIDE"
      log_configuration {
        cloud_watch_log_group_name = aws_cloudwatch_log_group.ecs.name
      }
    }
  }

  tags = var.tags
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.name}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  execution_role_arn       = var.task_execution_role
  task_role_arn            = var.task_role

  container_definitions = jsonencode([{
    name      = "app"
    image     = "public.ecr.aws/nginx/nginx:1.27"
    essential = true
    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
    environment = [
      { name = "DB_HOST", value = var.db_endpoint },
      { name = "REDIS_HOST", value = var.redis_endpoint },
      { name = "LEDGER_TABLE", value = var.ledger_table_name },
      { name = "PAYMENTS_QUEUE", value = var.payments_queue_url },
      { name = "AWS_REGION", value = data.aws_region.current.region },
    ]
    secrets = [
      { name = "DB_CREDENTIALS", valueFrom = var.db_secret_arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = data.aws_region.current.region
        awslogs-stream-prefix = "app"
      }
    }
    readonlyRootFilesystem = true
  }])

  tags = var.tags
}

resource "aws_ecs_service" "app" {
  name            = "${var.name}-app"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "app"
    container_port   = 8080
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_execute_command             = true

  tags       = var.tags
  depends_on = [aws_lb_listener.main]
}

# ECS task runtime perms (DynamoDB, SQS publish, secrets)
data "aws_iam_policy_document" "ecs_task_perms" {
  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
      "dynamodb:DeleteItem",
    ]
    resources = [var.ledger_table_arn, "${var.ledger_table_arn}/index/*"]
  }

  statement {
    actions   = ["sqs:SendMessage", "sqs:GetQueueAttributes"]
    resources = [var.payments_queue_arn]
  }

  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "ecs_task" {
  name   = "${var.name}-ecs-task-perms"
  role   = var.task_role_name
  policy = data.aws_iam_policy_document.ecs_task_perms.json
}

# --- Lambda ---
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/build/lambda.zip"

  source {
    content  = "exports.handler = async (event) => ({ statusCode: 200, body: JSON.stringify({ ok: true, event }) });"
    filename = "index.js"
  }
}

resource "aws_cloudwatch_log_group" "payment_svc" {
  name              = "/aws/lambda/${var.name}-payment-svc"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "fraud_kyc" {
  name              = "/aws/lambda/${var.name}-fraud-kyc"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn
  tags              = var.tags
}

resource "aws_lambda_function" "payment_svc" {
  function_name                  = "${var.name}-payment-svc"
  role                           = var.lambda_role_arn
  filename                       = data.archive_file.lambda_placeholder.output_path
  source_code_hash               = data.archive_file.lambda_placeholder.output_base64sha256
  runtime                        = "nodejs20.x"
  handler                        = "index.handler"
  timeout                        = 30
  memory_size                    = 512
  kms_key_arn                    = var.kms_key_arn
  reserved_concurrent_executions = 100

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      PAYMENTS_QUEUE = var.payments_queue_url
      LEDGER_TABLE   = var.ledger_table_name
      DB_HOST        = var.db_endpoint
      DB_SECRET_ARN  = var.db_secret_arn
    }
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.payment_svc]
  tags       = var.tags
}

resource "aws_lambda_function" "fraud_kyc" {
  function_name    = "${var.name}-fraud-kyc"
  role             = var.lambda_role_arn
  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256
  runtime          = "nodejs20.x"
  handler          = "index.handler"
  timeout          = 60
  memory_size      = 1024
  kms_key_arn      = var.kms_key_arn

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  tracing_config {
    mode = "Active"
  }

  depends_on = [aws_cloudwatch_log_group.fraud_kyc]
  tags       = var.tags
}

resource "aws_lambda_event_source_mapping" "payments" {
  event_source_arn                   = var.payments_queue_arn
  function_name                      = aws_lambda_function.payment_svc.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
}

# Lambda runtime perms
data "aws_iam_policy_document" "lambda_perms" {
  statement {
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [var.payments_queue_arn]
  }

  statement {
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query",
    ]
    resources = [var.ledger_table_arn, "${var.ledger_table_arn}/index/*"]
  }

  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.db_secret_arn]
  }

  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "lambda_perms" {
  name   = "${var.name}-lambda-perms"
  role   = var.lambda_role_name
  policy = data.aws_iam_policy_document.lambda_perms.json
}

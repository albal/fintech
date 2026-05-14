# Cross-module wiring assertions.
# These tests verify that outputs from upstream modules are correctly plumbed
# into downstream modules: security → data/compute/observability, network →
# all data-plane modules, compute → edge.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test"
      user_id    = "AIDAEXAMPLE"
    }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1", description = "US East (N. Virginia)" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", reverse_dns_prefix = "com.amazonaws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"], zone_ids = ["use1-az1", "use1-az2", "use1-az3"] }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"placeholder.amazonaws.com\"}}]}" }
  }
  mock_data "aws_secretsmanager_secret_version" {
    defaults = { secret_string = "{\"username\":\"fintech_app\",\"password\":\"mock-password\"}" }
  }
  mock_resource "aws_kms_key" {
    defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/mock-key-id", id = "mock-key-id", key_id = "mock-key-id" }
  }
  mock_resource "aws_s3_bucket" { defaults = { arn = "arn:aws:s3:::mock-bucket" } }
  mock_resource "aws_cloudtrail" { defaults = { arn = "arn:aws:cloudtrail:us-east-1:123456789012:trail/mock-trail" } }
  mock_resource "aws_cloudwatch_log_group" { defaults = { arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock-lg" } }
  mock_resource "aws_iam_role" { defaults = { arn = "arn:aws:iam::123456789012:role/mock-role" } }
  mock_resource "aws_iam_policy" { defaults = { arn = "arn:aws:iam::123456789012:policy/mock-policy" } }
  mock_resource "aws_sqs_queue" {
    defaults = { arn = "arn:aws:sqs:us-east-1:123456789012:mock-queue", url = "https://sqs.us-east-1.amazonaws.com/123456789012/mock-queue" }
  }
  mock_resource "aws_dynamodb_table" { defaults = { arn = "arn:aws:dynamodb:us-east-1:123456789012:table/mock-table" } }
  mock_resource "aws_lambda_function" { defaults = { arn = "arn:aws:lambda:us-east-1:123456789012:function:mock-fn" } }
  mock_resource "aws_lb" { defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock/abc123" } }
  mock_resource "aws_lb_listener" { defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/mock/abc123/def456" } }
  mock_resource "aws_lb_target_group" { defaults = { arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/mock/abc123" } }
  mock_resource "aws_secretsmanager_secret" { defaults = { arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:mock-secret-AbCdEf" } }
  mock_resource "aws_wafv2_web_acl" { defaults = { arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/mock/abc123" } }
  mock_resource "aws_acm_certificate" { defaults = { arn = "arn:aws:acm:us-east-1:123456789012:certificate/mock-cert-id" } }
}

mock_provider "aws" {
  alias = "us_east_1"
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_region" { defaults = { region = "us-east-1", name = "us-east-1" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_iam_policy_document" { defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" } }
  mock_resource "aws_acm_certificate" { defaults = { arn = "arn:aws:acm:us-east-1:123456789012:certificate/mock-cert-id" } }
  mock_resource "aws_wafv2_web_acl" { defaults = { arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/mock/abc123" } }
}

# ---------------------------------------------------------------------------
# Verify each module in the dependency chain produced a non-empty output.
# A failure here means a module's wiring to its upstream dependencies broke.
# ---------------------------------------------------------------------------

run "full_dependency_chain_intact" {
  command = apply

  # network → all downstream
  assert {
    condition     = output.vpc_id != ""
    error_message = "network module must produce vpc_id (depended on by data, compute, edge, observability)"
  }

  # security → data, compute, observability
  assert {
    condition     = can(regex("^arn:aws:kms:", output.kms_key_arn))
    error_message = "security module must produce a valid KMS ARN (passed to data, compute, observability)"
  }

  # data → compute (via aurora/redis/queue endpoints)
  assert {
    condition     = output.aurora_writer_endpoint != ""
    error_message = "data module must expose aurora_writer_endpoint (depended on by compute)"
  }

  assert {
    condition     = output.payments_queue_url != ""
    error_message = "data module must expose payments_queue_url (depended on by compute)"
  }

  assert {
    condition     = output.payments_dlq_arn != ""
    error_message = "data module must expose payments_dlq_arn (DLQ wiring)"
  }

  # compute → edge (via ALB listener)
  assert {
    condition     = output.alb_dns_name != ""
    error_message = "compute module must expose alb_dns_name (depended on by edge VPC link)"
  }

  # edge outputs: Cognito + API GW + CloudFront
  assert {
    condition     = can(regex("\\.auth\\.us-east-1\\.amazoncognito\\.com$", output.cognito_hosted_ui_domain))
    error_message = "edge module Cognito domain must embed the correct AWS region"
  }

  assert {
    condition     = output.api_gateway_endpoint != ""
    error_message = "edge module must expose api_gateway_endpoint"
  }

  # observability (receives kms_key_arn + vpc_id + transfer_role_arn from security)
  assert {
    condition     = output.audit_log_bucket != ""
    error_message = "observability module must expose audit_log_bucket (requires security + network wiring)"
  }
}

# ---------------------------------------------------------------------------
# Naming flows through: the `name` and `environment` variables must be visible
# in resource names across all layers that interpolate them.
# ---------------------------------------------------------------------------

run "name_and_env_propagate_through_all_modules" {
  command = apply

  variables {
    name        = "payments"
    environment = "staging"
  }

  assert {
    condition     = output.ledger_table_name == "payments-staging-ledger"
    error_message = "name + environment must propagate from root to data module table names"
  }
}

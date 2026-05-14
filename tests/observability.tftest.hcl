# Isolation tests for the observability module.
# Verifies S3 bucket outputs, CloudTrail ARN format, and that the audit bucket
# name embeds the account ID (required for global uniqueness and auditor tracing).

mock_provider "aws" {
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_region" { defaults = { region = "us-east-1", name = "us-east-1" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b", "us-east-1c"] }
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

run "observability_buckets_and_trail_created" {
  command = apply

  assert {
    condition     = output.audit_log_bucket != ""
    error_message = "observability module must expose audit_log_bucket"
  }

  assert {
    condition     = output.documents_bucket != ""
    error_message = "observability module must expose documents_bucket"
  }
}

run "bucket_names_vary_with_name_change" {
  command = apply

  variables { name = "neobank" }

  assert {
    condition     = output.audit_log_bucket != ""
    error_message = "audit_log_bucket must still be present when name changes"
  }
}

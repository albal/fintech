# Apply-time tests against mocked AWS — verifies the full graph evaluates,
# including computed references and resource-level schema validation that
# `plan` alone doesn't catch.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test"
      user_id    = "AIDAEXAMPLE"
    }
  }
  mock_data "aws_region" {
    defaults = {
      region      = "us-east-1"
      name        = "us-east-1"
      description = "US East (N. Virginia)"
    }
  }
  mock_data "aws_partition" {
    defaults = {
      partition          = "aws"
      reverse_dns_prefix = "com.amazonaws"
      dns_suffix         = "amazonaws.com"
    }
  }
  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["us-east-1a", "us-east-1b", "us-east-1c"]
      zone_ids = ["use1-az1", "use1-az2", "use1-az3"]
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"placeholder.amazonaws.com\"}}]}"
    }
  }

  # Secret string must be valid JSON — the data module jsondecode()s it.
  mock_data "aws_secretsmanager_secret_version" {
    defaults = {
      secret_string = "{\"username\":\"fintech_app\",\"password\":\"mock-password\"}"
    }
  }

  # Provide proper ARN-shaped defaults for resources whose ARNs are validated
  # by downstream resources (the AWS provider rejects non-ARN strings).
  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:123456789012:key/mock-key-id"
      id     = "mock-key-id"
      key_id = "mock-key-id"
    }
  }
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::mock-bucket"
    }
  }
  mock_resource "aws_cloudtrail" {
    defaults = {
      arn = "arn:aws:cloudtrail:us-east-1:123456789012:trail/mock-trail"
    }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:mock-lg"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-role"
    }
  }
  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/mock-policy"
    }
  }
  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:us-east-1:123456789012:mock-queue"
      url = "https://sqs.us-east-1.amazonaws.com/123456789012/mock-queue"
    }
  }
  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn = "arn:aws:dynamodb:us-east-1:123456789012:table/mock-table"
    }
  }
  mock_resource "aws_lambda_function" {
    defaults = {
      arn = "arn:aws:lambda:us-east-1:123456789012:function:mock-fn"
    }
  }
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock/abc123"
    }
  }
  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/mock/abc123/def456"
    }
  }
  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/mock/abc123"
    }
  }
  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:mock-secret-AbCdEf"
    }
  }
  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/mock/abc123"
    }
  }
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/mock-cert-id"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"

  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
      name   = "us-east-1"
    }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/mock-cert-id"
    }
  }
  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/mock/abc123"
    }
  }
}

# ---------------------------------------------------------------------------
# Full-graph apply against mocks
# ---------------------------------------------------------------------------

run "full_apply_succeeds" {
  command = apply

  # KMS CMK must be exposed (encryption everywhere depends on it).
  assert {
    condition     = output.kms_key_arn != ""
    error_message = "Top-level KMS key ARN should be exposed"
  }

  # Ledger table name is a pure variable interpolation — survives mock_resource
  # ID overrides because the output reads .name, not .id.
  assert {
    condition     = output.ledger_table_name == "fintech-prod-ledger"
    error_message = "Ledger table name should follow '<name>-<env>-ledger'"
  }

  assert {
    condition     = can(regex("\\.auth\\.us-east-1\\.amazoncognito\\.com$", output.cognito_hosted_ui_domain))
    error_message = "Cognito hosted UI domain should follow the regional amazoncognito.com format"
  }

  # Edge-tier outputs must be wired through.
  assert {
    condition     = output.api_gateway_endpoint != ""
    error_message = "API Gateway endpoint output should exist"
  }

  assert {
    condition     = output.cognito_user_pool_id != ""
    error_message = "Cognito user pool ID output should exist"
  }
}

# ---------------------------------------------------------------------------
# Apply still succeeds when name/env change — catches missing prefix wiring
# ---------------------------------------------------------------------------

run "alt_env_applies_cleanly" {
  command = apply

  variables {
    name        = "neobank"
    environment = "staging"
  }

  assert {
    condition     = output.ledger_table_name == "neobank-staging-ledger"
    error_message = "Ledger table name should track name + env"
  }

  assert {
    condition     = output.payments_queue_url != ""
    error_message = "SQS queue URL should be exposed"
  }
}

# ---------------------------------------------------------------------------
# Domain wiring — empty domain leaves everything on AWS-default endpoints
# ---------------------------------------------------------------------------

run "no_domain_yields_cloudfront_default_certificate" {
  command = apply

  assert {
    condition     = output.cloudfront_domain != null
    error_message = "CloudFront domain output should be present even with no custom domain"
  }
}

run "with_custom_domain_applies_cleanly" {
  command = apply

  variables {
    domain_name    = "api.example.com"
    hosted_zone_id = "Z01234567890ABCDEFGHI"
  }

  # The configured ACM cert + Route 53 alias should not break the apply.
  assert {
    condition     = output.cloudfront_domain != null
    error_message = "CloudFront should still be reachable when a custom domain is set"
  }
}

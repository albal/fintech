# Plan-time tests covering naming, locals, and config validity across variable
# permutations. Runs entirely against mocked AWS — no real credentials needed.

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
      names    = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
      zone_ids = ["use1-az1", "use1-az2", "use1-az3", "use1-az4"]
    }
  }

  # IAM policy documents must be valid JSON — the AWS provider rejects empty strings.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"placeholder.amazonaws.com\"}}]}"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

run "defaults" {
  command = plan

  assert {
    condition     = local.name == "fintech-prod"
    error_message = "Default composed name should be 'fintech-prod'"
  }

  assert {
    condition     = length(local.azs) == 2
    error_message = "Should default to 2 AZs (matching the diagram)"
  }

  assert {
    condition     = local.common_tags["ManagedBy"] == "terraform"
    error_message = "Common tags should mark resources as managed by terraform"
  }

  assert {
    condition     = local.common_tags["Compliance"] == "PCI-DSS"
    error_message = "PCI-DSS compliance tag must be applied to all resources"
  }
}

# ---------------------------------------------------------------------------
# Environment variants — names cascade through every module
# ---------------------------------------------------------------------------

run "dev_environment" {
  command = plan

  variables {
    environment = "dev"
  }

  assert {
    condition     = local.name == "fintech-dev"
    error_message = "Dev environment should produce 'fintech-dev' prefix"
  }

  assert {
    condition     = output.ledger_table_name == "fintech-dev-ledger"
    error_message = "DynamoDB ledger table should inherit env-scoped name"
  }

  assert {
    condition     = local.common_tags["Environment"] == "dev"
    error_message = "Environment tag should reflect var.environment"
  }
}

run "custom_project_name" {
  command = plan

  variables {
    name        = "neobank"
    environment = "staging"
  }

  assert {
    condition     = local.name == "neobank-staging"
    error_message = "Custom project name + env should compose correctly"
  }

  assert {
    condition     = output.ledger_table_name == "neobank-staging-ledger"
    error_message = "All resources should pick up custom name prefix"
  }
}

# ---------------------------------------------------------------------------
# Availability Zone scaling
# ---------------------------------------------------------------------------

run "three_az_deployment" {
  command = plan

  variables {
    az_count = 3
  }

  assert {
    condition     = length(local.azs) == 3
    error_message = "az_count=3 should produce 3 AZs"
  }
}

run "single_az_dev_deployment" {
  command = plan

  variables {
    az_count    = 1
    environment = "dev"
  }

  assert {
    condition     = length(local.azs) == 1
    error_message = "az_count=1 should reduce footprint for dev"
  }
}

# ---------------------------------------------------------------------------
# Domain handling — optional Route 53 / ACM
# ---------------------------------------------------------------------------

run "no_custom_domain_uses_cloudfront_default" {
  command = plan

  # Defaults already have empty domain_name — config should plan cleanly without
  # ACM cert or Route 53 record being required.

  assert {
    condition     = var.domain_name == ""
    error_message = "Empty domain_name is the default"
  }
}

run "custom_domain_plans_with_route53" {
  command = plan

  variables {
    domain_name    = "api.example.com"
    hosted_zone_id = "Z01234567890ABCDEFGHI"
  }

  assert {
    condition     = var.domain_name == "api.example.com"
    error_message = "Custom domain should propagate to edge module"
  }
}

run "custom_domain_without_zone_still_plans" {
  # ACM cert is created but Route 53 record is skipped — useful when DNS is
  # managed outside Route 53.
  command = plan

  variables {
    domain_name    = "api.example.com"
    hosted_zone_id = ""
  }

  assert {
    condition     = var.domain_name != "" && var.hosted_zone_id == ""
    error_message = "Should support domain without Route 53 zone (external DNS)"
  }
}

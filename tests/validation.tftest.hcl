# Negative tests — each `run` block asserts that an invalid input is rejected
# by the variable validation rules before terraform even reaches the providers.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1", name = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d"]
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_region" { defaults = { region = "us-east-1", name = "us-east-1" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
}

# ---------------------------------------------------------------------------
# Negative tests on root variables
# ---------------------------------------------------------------------------

run "rejects_bad_region" {
  command = plan
  variables {
    region = "not-a-region"
  }
  expect_failures = [var.region]
}

run "rejects_empty_name" {
  command = plan
  variables {
    name = ""
  }
  expect_failures = [var.name]
}

run "rejects_name_with_uppercase" {
  command = plan
  variables {
    name = "FinTech"
  }
  expect_failures = [var.name]
}

run "rejects_unknown_environment" {
  command = plan
  variables {
    environment = "production" # not in allow-list
  }
  expect_failures = [var.environment]
}

run "rejects_malformed_cidr" {
  command = plan
  variables {
    vpc_cidr = "10.0.0.0"
  }
  expect_failures = [var.vpc_cidr]
}

run "rejects_too_small_cidr" {
  command = plan
  variables {
    vpc_cidr = "10.0.0.0/28"
  }
  expect_failures = [var.vpc_cidr]
}

run "rejects_too_large_cidr" {
  command = plan
  variables {
    vpc_cidr = "10.0.0.0/8"
  }
  expect_failures = [var.vpc_cidr]
}

run "rejects_zero_azs" {
  command = plan
  variables {
    az_count = 0
  }
  expect_failures = [var.az_count]
}

run "rejects_too_many_azs" {
  command = plan
  variables {
    az_count = 10
  }
  expect_failures = [var.az_count]
}

run "rejects_bad_domain" {
  command = plan
  variables {
    domain_name = "not a valid domain"
  }
  expect_failures = [var.domain_name]
}

run "rejects_bad_hosted_zone_id" {
  command = plan
  variables {
    hosted_zone_id = "z01234567890" # must start with capital Z
  }
  expect_failures = [var.hosted_zone_id]
}

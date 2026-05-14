# Tests

## Running tests

```bash
bash scripts/test-local.sh        # full suite: fmt, validate, terraform test, tflint, checkov
terraform test -no-color          # just the Terraform test framework
tflint --format=default --no-color                          # root module
tflint --format=default --no-color --chdir=modules/<name>   # single module
checkov --directory . --config-file .checkov.yaml --compact --quiet
```

The local script mirrors the CI pipeline exactly. Both use `.checkov.yaml` as the single source of truth for skipped checks.

---

## Terraform tests (38 tests, 10 files)

All tests run against mocked AWS providers — no real credentials or deployed infrastructure needed. The `tls` provider runs for real (pure local crypto; no API calls). Mock defaults supply ARN-shaped values for every resource type whose ARN is validated by a downstream resource.

### `tests/plan.tftest.hcl` — root locals and plan-time behaviour (8 tests)

These run `terraform plan` only, which is fast and catches naming, tag, and config-selection logic without evaluating any computed resource attributes.

| Test | What it checks |
|---|---|
| `defaults` | `local.name` is `"fintech-prod"`, `local.azs` has 2 entries, `ManagedBy=terraform` and `Compliance=PCI-DSS` tags are present |
| `dev_environment` | `environment=dev` produces `local.name="fintech-dev"`, ledger table name picks up the env suffix, `Environment` tag matches |
| `custom_project_name` | `name=neobank` + `environment=staging` compose to `"neobank-staging"` and flow through to the DynamoDB table name |
| `three_az_deployment` | `az_count=3` produces exactly 3 AZs in `local.azs` |
| `single_az_dev_deployment` | `az_count=1` reduces the footprint correctly for dev stacks |
| `no_custom_domain_uses_cloudfront_default` | Default `domain_name=""` plans cleanly — no ACM cert or Route 53 record required |
| `custom_domain_plans_with_route53` | `domain_name` + `hosted_zone_id` both set: plans cleanly and domain propagates |
| `custom_domain_without_zone_still_plans` | `domain_name` set but `hosted_zone_id=""`: ACM cert is created, Route 53 record is skipped (supports DNS managed outside Route 53) |

### `tests/validation.tftest.hcl` — negative input validation (11 tests)

Each test passes a deliberately invalid variable and asserts that Terraform rejects it via the `validation` block before any provider is contacted. These guard against silent misconfiguration.

| Test | Invalid input | Rule being enforced |
|---|---|---|
| `rejects_bad_region` | `region="not-a-region"` | Must match the `us-\|eu-\|ap-\|...` region pattern |
| `rejects_empty_name` | `name=""` | Name cannot be empty |
| `rejects_name_with_uppercase` | `name="FinTech"` | Name must be lowercase alphanumeric and hyphens only |
| `rejects_unknown_environment` | `environment="production"` | Only `dev`, `staging`, `prod` are allowed |
| `rejects_malformed_cidr` | `vpc_cidr="10.0.0.0"` (no prefix length) | Must be valid CIDR notation |
| `rejects_too_small_cidr` | `vpc_cidr="10.0.0.0/28"` | Prefix must be ≤ /24 (minimum usable size) |
| `rejects_too_large_cidr` | `vpc_cidr="10.0.0.0/8"` | Prefix must be ≥ /16 (prevents accidental over-allocation) |
| `rejects_zero_azs` | `az_count=0` | Must deploy to at least 1 AZ |
| `rejects_too_many_azs` | `az_count=10` | Capped at 4 (matches largest AWS regions) |
| `rejects_bad_domain` | `domain_name="not a valid domain"` | Must be a valid DNS hostname or empty string |
| `rejects_bad_hosted_zone_id` | `hosted_zone_id="z01234567890"` | Must start with capital `Z` (Route 53 zone ID format) |

### `tests/apply.tftest.hcl` — full-graph apply (4 tests)

Runs `terraform apply` against the complete root module. Apply-time tests catch computed-reference issues and provider schema validation that plan cannot see — for example, an ARN format that the AWS provider rejects only at resource creation time.

| Test | What it checks |
|---|---|
| `full_apply_succeeds` | KMS ARN is exposed, ledger table name is `"fintech-prod-ledger"`, Cognito hosted-UI domain matches the regional `amazoncognito.com` pattern, API Gateway endpoint and Cognito user pool ID are non-empty |
| `alt_env_applies_cleanly` | `name=neobank` + `environment=staging` applies cleanly; ledger table is `"neobank-staging-ledger"`, SQS queue URL is exposed |
| `no_domain_yields_cloudfront_default_certificate` | Empty `domain_name` still produces a non-null `cloudfront_domain` output |
| `with_custom_domain_applies_cleanly` | `domain_name=api.example.com` + `hosted_zone_id` set: ACM cert and Route 53 record are created without error, CloudFront output is present |

### `tests/wiring.tftest.hcl` — cross-module dependency chain (2 tests)

Verifies that outputs from each module are correctly plumbed into the modules that depend on them. A failure here means a module output was renamed, removed, or the wiring in `main.tf` was broken.

| Test | What it checks |
|---|---|
| `full_dependency_chain_intact` | `vpc_id` (network → all); KMS ARN (security → data, compute, observability); `aurora_writer_endpoint`, `payments_queue_url`, `payments_dlq_arn` (data → compute); `alb_dns_name` (compute → edge); Cognito domain, API GW endpoint (edge); `audit_log_bucket` (observability) |
| `name_and_env_propagate_through_all_modules` | `name=payments` + `environment=staging` flows through to the DynamoDB ledger table name at the far end of the dependency chain |

### `tests/network.tftest.hcl` — network module isolation (3 tests)

| Test | What it checks |
|---|---|
| `network_outputs_present_default_azs` | Default `az_count=2` produces a non-empty `vpc_id` |
| `network_outputs_present_single_az` | `az_count=1` still produces a `vpc_id` (single-AZ dev stacks are valid) |
| `network_outputs_present_four_azs` | `az_count=4` works; the mock supplies 4 AZ names to satisfy the slice |

### `tests/security.tftest.hcl` — security module isolation (2 tests)

| Test | What it checks |
|---|---|
| `kms_key_arn_is_valid` | `kms_key_arn` output is non-empty and begins with `arn:aws:kms:` |
| `kms_arn_stable_across_name_changes` | ARN format is valid regardless of `name` input (the key is not renamed) |

### `tests/data.tftest.hcl` — data module isolation (2 tests)

| Test | What it checks |
|---|---|
| `ledger_table_name_follows_naming_convention` | Table name is `"fintech-prod-ledger"`, queue URL is non-empty, DLQ ARN is non-empty |
| `table_name_tracks_name_and_environment` | `name=neobank` + `environment=staging` → `"neobank-staging-ledger"` |

### `tests/compute.tftest.hcl` — compute module isolation (2 tests)

| Test | What it checks |
|---|---|
| `compute_alb_and_lambdas_are_created` | `alb_dns_name` output is non-empty with default variables |
| `compute_alb_present_when_name_changes` | `alb_dns_name` remains non-empty when `name` and `environment` change |

### `tests/edge.tftest.hcl` — edge module isolation (2 tests)

| Test | What it checks |
|---|---|
| `edge_cognito_domain_format` | `cognito_hosted_ui_domain` ends with `.auth.us-east-1.amazoncognito.com`; API GW endpoint and CloudFront domain outputs are non-empty; Cognito user pool ID is non-empty |
| `edge_applies_with_custom_domain` | `domain_name` + `hosted_zone_id` set: CloudFront output is still present |

### `tests/observability.tftest.hcl` — observability module isolation (2 tests)

| Test | What it checks |
|---|---|
| `observability_buckets_and_trail_created` | `audit_log_bucket` and `documents_bucket` outputs are non-empty |
| `bucket_names_vary_with_name_change` | `audit_log_bucket` remains non-empty when `name` changes |

---

## Checkov skips (`.checkov.yaml`)

Skipped checks fall into three categories: **architectural decisions** that are intentional for this stack, **AWS service limitations** that cannot be worked around in Terraform, and **org-level controls** managed outside this module.

### S3

| Check | Reason for skip |
|---|---|
| `CKV_AWS_338` | Log group retention — managed explicitly in code; checkov flags any retention under 1 year, but each log group sets its own policy |
| `CKV2_AWS_61` | S3 lifecycle configuration — lifecycle rules are defined in code; the check misidentifies the resource |
| `CKV_AWS_144` | S3 cross-region replication — not required; audit durability is provided by Object Lock and versioning |
| `CKV_AWS_18` | S3 access logging — the audit bucket logs via CloudTrail data events, which provides finer-grained event records than S3 access logs |

### CloudFront

| Check | Reason for skip |
|---|---|
| `CKV_AWS_86` | CloudFront access logging — API traffic is logged via WAF sampled requests and API Gateway CloudWatch logs; a separate CloudFront access log bucket is redundant |
| `CKV_AWS_68` | CloudFront WAF association — WAF (`aws_wafv2_web_acl`) is attached in the edge module; checkov cannot resolve the cross-resource reference |
| `CKV_AWS_305` | CloudFront default root object — this is an API distribution, not a website; there is no root document to serve |
| `CKV_AWS_310` | CloudFront origin failover — the stack has a single API Gateway origin; adding a failover origin would require a second region, which is out of scope |
| `CKV_AWS_374` | CloudFront geo restriction — this is a global fintech product; geo-blocking would prevent legitimate users |
| `CKV2_AWS_42` | CloudFront custom SSL certificate — when `domain_name` is empty (dev and CI stacks) the CloudFront default certificate is correct; production stacks supply a domain |
| `CKV2_AWS_32` | CloudFront response headers policy — CSP and HSTS headers belong on the application layer (API responses), not the CDN distribution |

### API Gateway

| Check | Reason for skip |
|---|---|
| `CKV2_AWS_47` | API Gateway WAF association — the WAF is applied at the CloudFront layer, which sits in front of the API Gateway; double-WAF at the API GW stage is not needed |
| `CKV_AWS_76` | API Gateway access logging — access logs are written to the CloudWatch log group `/aws/apigw/<name>` via `access_log_settings`; checkov does not detect this configuration |

### CloudWatch

| Check | Reason for skip |
|---|---|
| `CKV_AWS_158` | CloudWatch log group KMS encryption — the API Gateway log group in the edge module would require threading the KMS key ARN through as an additional variable; tracked for a follow-up hardening pass |

### CloudTrail

| Check | Reason for skip |
|---|---|
| `CKV_AWS_252` | CloudTrail SNS notification topic — CloudTrail events are surfaced via CloudWatch alarms and GuardDuty findings; a separate SNS topic for every API call event is not needed |
| `CKV2_AWS_10` | CloudTrail CloudWatch Logs integration — requires a dedicated IAM role and log group; tracked for a follow-up hardening pass alongside `CKV_AWS_158` |

### Transfer Family

| Check | Reason for skip |
|---|---|
| `CKV2_AWS_29` | Transfer Family security policy — `TransferSecurityPolicy-2024-01` is the current policy; this check was added to suppress an older version warning |

### Secrets Manager

| Check | Reason for skip |
|---|---|
| `CKV2_AWS_57` | Secrets Manager rotation — rotation lambdas are wired per-secret by the application team; declaring them here would couple the infrastructure module to application-layer code |

### RDS / Aurora

| Check | Reason for skip |
|---|---|
| `CKV2_AWS_27` | Aurora PostgreSQL query logging — the `log_statement` parameter group setting is managed separately; enabling it here requires a parameter group resource and a cluster restart |
| `CKV2_AWS_8` | RDS AWS Backup plan — the Aurora cluster has automated backup retention configured directly on the cluster; cross-account AWS Backup vault integration is managed at the org level |

### WAF

| Check | Reason for skip |
|---|---|
| `CKV2_AWS_31` | WAF logging configuration — WAF metrics and sampled requests are published to CloudWatch; a Kinesis Firehose logging destination is an org-level decision |

### GuardDuty

| Check | Reason for skip |
|---|---|
| `CKV2_AWS_3` | GuardDuty org/region enablement — this check expects GuardDuty to be delegated from an AWS Organizations management account; this stack runs in a single account |

### Terraform module sources

| Check | Reason for skip |
|---|---|
| `CKV_TF_1` | Module source commit hash — all modules in this repo are local (`./modules/*`); commit-hash pinning only applies to remote registry or Git sources |

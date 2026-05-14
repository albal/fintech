# Fintech AWS Reference Infrastructure

Terraform that provisions a production-shaped fintech / payments stack on AWS:
multi-AZ VPC, ECS Fargate + Lambda compute, Aurora PostgreSQL + Redis +
DynamoDB data tier, SQS with DLQ, CloudFront + WAF + API Gateway edge,
Cognito auth, and a compliance baseline (KMS everywhere, CloudTrail with
Object Lock, GuardDuty, audit logging).

A visual companion lives at [`fintech-aws-architecture.drawio`](fintech-aws-architecture.drawio) —
open it in [draw.io](https://app.diagrams.net) to see the topology this code maps to.

---

## Architecture

```
              ┌─ End Users (Web / Mobile)
              ▼
    Route 53 → CloudFront → WAF (CLOUDFRONT scope, us-east-1)
                            ▼
                        API Gateway (HTTP API)  ──── Cognito (JWT)
                            ▼  (VPC link)
    ╔════════════════════════════════════════════════════════════╗
    ║ VPC (10.0.0.0/16)  ── AZ-A ──── AZ-B ──────────────────────║
    ║                                                            ║
    ║   Public subnets  : ALB (internal), NAT GW, IGW            ║
    ║   Private subnets : ECS Fargate ──► Lambda (payment, KYC)  ║
    ║   Database subnets: Aurora PG (writer/reader), Redis       ║
    ║                                                            ║
    ╚════════════════════════════════════════════════════════════╝
                            │
              Regional Managed Services (multi-AZ by default)
                  SQS Payments  ──►  SQS DLQ
                  DynamoDB ledger / idempotency
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
       External Processors          S3 (docs + audit, Object Lock)
       (Stripe, banks, KYC)         CloudTrail · GuardDuty · Transfer Family
```

Data flow on a payment:

1. Client → Route 53 → CloudFront (WAF inspects) → API Gateway (Cognito JWT)
2. API GW VPC link → internal ALB → ECS Fargate task (core app)
3. App writes to Aurora (system of record), caches in Redis, enqueues to SQS
4. Lambda consumes SQS → calls Stripe/Adyen → writes to DynamoDB ledger
5. Failed messages → SQS DLQ after 5 retries
6. Settlement files arrive via Transfer Family SFTP → S3 → reconciliation
7. Everything is encrypted with a single KMS CMK, audited by CloudTrail

---

## Module structure

```
terraform/
├── versions.tf         provider + version pins (AWS 6.45.0, tls ~> 4.0)
├── providers.tf        aws + aws.us_east_1 (CloudFront WAF must live in us-east-1)
├── variables.tf        root input variables (all validated)
├── locals.tf           name composition, AZ slicing, common tags
├── main.tf             wires the six child modules together
├── outputs.tf          top-level outputs (ALB DNS, CF domain, etc.)
├── .checkov.yaml       single source of truth for all checkov skips
├── .tflint.hcl         tflint config with AWS ruleset
├── scripts/
│   └── test-local.sh   mirrors the full CI pipeline locally
├── tests/
│   ├── plan.tftest.hcl         8 plan-time tests (naming, AZ scaling, domain options)
│   ├── apply.tftest.hcl        4 apply-time tests (full graph against mocks)
│   ├── validation.tftest.hcl   11 negative tests (every variable's validation rules)
│   ├── wiring.tftest.hcl       2 cross-module dependency-chain tests
│   ├── network.tftest.hcl      3 module isolation tests
│   ├── security.tftest.hcl     2 module isolation tests
│   ├── data.tftest.hcl         2 module isolation tests
│   ├── compute.tftest.hcl      2 module isolation tests
│   ├── edge.tftest.hcl         2 module isolation tests
│   └── observability.tftest.hcl 2 module isolation tests
└── modules/
    ├── network/        VPC (community module) + 2 gateway + 7 interface endpoints
    ├── security/       KMS CMK (with key policy) + IAM roles + Secrets Manager secrets
    ├── data/           Aurora · Redis · DynamoDB · SQS · DLQ
    ├── compute/        Internal ALB (HTTPS/443) · ECS Fargate · 2 Lambda fns · SG mesh
    ├── edge/           CloudFront · WAF · HTTP API · VPC link · Cognito · R53
    └── observability/  S3 (docs + audit) · CloudTrail · GuardDuty · SFTP
```

Each module has `main.tf`, `variables.tf`, `outputs.tf`. The community
`terraform-aws-modules/vpc/aws` is the only external module dependency —
everything else is raw resources for 1:1 mapping to the diagram.

---

## Prerequisites

| Requirement      | Version       | Notes                                          |
| ---------------- | ------------- | ---------------------------------------------- |
| Terraform        | `>= 1.6`      | 1.6 added native tests; 1.7+ adds mock_provider |
| AWS provider     | `6.45.0`      | Exact pin in `versions.tf`                     |
| AWS credentials  | —             | `aws configure` or env vars, region us-east-1  |
| AWS account      | —             | Service quotas for VPC, ECS, RDS, EIPs         |
| Permissions      | Admin-ish     | This module creates IAM, KMS, VPC, RDS, etc.   |
| tflint           | `>= 0.55`     | Static analysis (CI + local); `brew install tflint` |
| checkov          | `>= 3.2`      | Policy scanning (CI + local); `pip install checkov` |

---

## Quick start

```bash
cd terraform

# 1. Download providers + the VPC community module
terraform init

# 2. See what will be created
terraform plan

# 3. Provision (~15–20 min, mostly Aurora + CloudFront)
terraform apply

# 4. Outputs you'll need
terraform output
```

Override defaults via `terraform.tfvars` (gitignored by default):

```hcl
name           = "neobank"
environment    = "prod"
region         = "us-east-1"
az_count       = 3
vpc_cidr       = "10.20.0.0/16"
domain_name    = "api.neobank.com"
hosted_zone_id = "Z01234567890ABCDEFGHI"
```

---

## Input variables

| Variable          | Type     | Default        | Purpose                                                  |
| ----------------- | -------- | -------------- | -------------------------------------------------------- |
| `region`          | `string` | `us-east-1`    | Primary AWS region                                       |
| `name`            | `string` | `fintech`      | Prefix for every resource                                |
| `environment`     | `string` | `prod`         | Appended to `name` → `fintech-prod`                      |
| `vpc_cidr`        | `string` | `10.0.0.0/16`  | VPC CIDR; subnets are carved out of this                 |
| `az_count`        | `number` | `2`            | Number of AZs to span                                    |
| `domain_name`     | `string` | `""`           | Optional custom domain for CloudFront / API GW           |
| `hosted_zone_id`  | `string` | `""`           | Route 53 zone for the domain (if managed in Route 53)    |

---

## Outputs

| Output                      | What it gives you                                  |
| --------------------------- | -------------------------------------------------- |
| `vpc_id`                    | VPC ID for peering / cross-stack references        |
| `alb_dns_name`              | Internal ALB DNS (reachable via API GW VPC link)   |
| `cloudfront_domain`         | Public CloudFront endpoint                         |
| `api_gateway_endpoint`      | API Gateway HTTP API endpoint                      |
| `cognito_user_pool_id`      | For SDK / hosted UI configuration                  |
| `cognito_client_id`         | Public client ID (no secret)                       |
| `cognito_hosted_ui_domain`  | `<name>.auth.<region>.amazoncognito.com`           |
| `aurora_writer_endpoint`    | Primary Aurora endpoint                            |
| `aurora_reader_endpoint`    | Aurora reader endpoint                             |
| `redis_endpoint`            | Primary Redis endpoint                             |
| `ledger_table_name`         | DynamoDB ledger table name                         |
| `payments_queue_url`        | SQS queue URL                                      |
| `payments_dlq_arn`          | DLQ ARN (set CloudWatch alarms on this)            |
| `audit_log_bucket`          | S3 bucket holding CloudTrail logs (Object Lock)    |
| `documents_bucket`          | S3 bucket for customer documents                   |
| `kms_key_arn`               | Master CMK used by every service                   |

---

## Testing

The full suite — format check, validation, Terraform tests, tflint, and checkov — runs with one command:

```bash
bash scripts/test-local.sh
```

This mirrors the CI pipeline exactly. Individual tools can be run in isolation:

```bash
terraform test -no-color                                         # 38 tests, ~10 seconds, no AWS creds
tflint --format=default --no-color                               # root module
tflint --format=default --no-color --chdir=modules/<name>        # single module
checkov --directory . --config-file .checkov.yaml --compact --quiet
```

**38 tests across 10 files** — all run against mocked AWS, no real credentials needed:

| File | Tests | What it covers |
|---|---|---|
| `plan.tftest.hcl` | 8 | Naming, AZ scaling, tag correctness, domain option combinations |
| `apply.tftest.hcl` | 4 | Full dependency graph, computed ARN shapes, name/env propagation |
| `validation.tftest.hcl` | 11 | Negative tests — every variable's `validation` block rejects bad input |
| `wiring.tftest.hcl` | 2 | Cross-module outputs: every inter-module dependency is non-empty |
| `network.tftest.hcl` | 3 | VPC outputs present at az_count = 1, 2, and 4 |
| `security.tftest.hcl` | 2 | KMS ARN format, ARN stable across name changes |
| `data.tftest.hcl` | 2 | DynamoDB naming convention, SQS + DLQ exposed |
| `compute.tftest.hcl` | 2 | ALB DNS name present, survives name/env changes |
| `edge.tftest.hcl` | 2 | Cognito domain format, custom domain path |
| `observability.tftest.hcl` | 2 | S3 bucket outputs present, survive name changes |

See [`TESTS.md`](TESTS.md) for a detailed description of every test case and the rationale behind each checkov skip.

---

## Cost estimate

Rough monthly cost in us-east-1 with default settings (2 AZs, idle):

| Service               | Component                      | ~$ / mo |
| --------------------- | ------------------------------ | ------: |
| Aurora PostgreSQL     | 2× db.r6g.large + storage      |   ~350  |
| ElastiCache Redis     | 2× cache.r6g.large             |   ~250  |
| NAT Gateways          | 2× NAT GW + data transfer      |    ~70  |
| ECS Fargate           | 2 tasks × 1 vCPU / 2 GB        |    ~30  |
| ALB                   | App load balancer + LCUs       |    ~20  |
| CloudFront            | Idle, low traffic              |     ~5  |
| GuardDuty             | Detector + S3 monitoring       |     ~5  |
| Other                 | KMS, Secrets, CW Logs, S3      |    ~10  |
| **Total**             |                                | **~740** |

Dev override (single AZ, smaller instances) lands closer to $200–300/mo:

```hcl
az_count = 1
# and override the data module's instance classes (db.t4g.medium, cache.t4g.small)
```

---

## Production hardening checklist

Items the code does today:

- [x] KMS CMK with rotation, explicit key policy, used by every service that supports it
- [x] All S3 buckets: versioned, encrypted, public access blocked, lifecycle abort-incomplete-multipart
- [x] Audit bucket: Object Lock COMPLIANCE, 7-year retention
- [x] Aurora: encrypted, deletion protection, `rds.force_ssl = 1`, multi-AZ, IAM auth on
- [x] Redis: at-rest + in-transit encryption, AUTH token, multi-AZ failover
- [x] DynamoDB: PITR, KMS, deletion protection
- [x] SQS: KMS, redrive policy → DLQ after 5 retries
- [x] CloudFront: WAF with managed rule groups + per-IP rate limit
- [x] API Gateway: JWT authorizer via Cognito, structured access logs
- [x] ECS: Container Insights, `readonlyRootFilesystem`, ECS Exec via KMS
- [x] Lambda: in-VPC, KMS, X-Ray, DLQ-aware event source mapping, reserved concurrency
- [x] CloudTrail: multi-region, log-file validation, KMS, S3 + Lambda data events
- [x] GuardDuty: enabled with S3 + malware protection
- [x] VPC: private subnets, NAT per AZ, flow logs to CloudWatch
- [x] VPC endpoints: S3 + DynamoDB (gateway), Secrets/KMS/ECR/Logs/SQS/STS (interface), restricted egress SGs
- [x] Internal ALB: HTTPS/443 listener, TLS 1.3 SSL policy, access logs to S3
- [x] All security group rules have descriptions
- [x] Variable validation on all root inputs; CI gates on fmt + validate + 38 tests + tflint + checkov

Things you'll still want to do before going live:

- [ ] Replace the placeholder `public.ecr.aws/nginx/nginx` image with your real app
- [ ] Replace the placeholder Lambda zip with actual handler code
- [ ] Populate `<name>/payment-provider/api-key` in Secrets Manager
- [ ] Configure Secrets Manager rotation for the Aurora master credential
- [ ] Replace the self-signed ACM cert on the internal ALB with a private CA cert
- [ ] Restrict Transfer Family SFTP ingress to bank partner CIDRs (currently 0.0.0.0/0)
- [ ] Split the single CMK into per-service keys if you need strict PCI scope separation
- [ ] Set up CloudWatch alarms: DLQ depth > 0, Aurora CPU, ALB 5xx rate, WAF blocks
- [ ] Add Backup vault + AWS Backup plan for Aurora and DynamoDB
- [ ] Configure CloudFront logging to the audit bucket
- [ ] Add a remote state backend (S3 + DynamoDB lock table) — see below
- [ ] Wire KMS key ARN to the API Gateway CloudWatch log group
- [ ] Subscribe GuardDuty findings to Security Hub or a SIEM

---

## Remote state

This template uses local state by default. For team use, add a backend:

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "fintech-tfstate-<account-id>"
    key            = "infra/prod.tfstate"
    region         = "us-east-1"
    dynamodb_table = "fintech-tfstate-lock"
    encrypt        = true
    kms_key_id     = "alias/aws/s3"
  }
}
```

Chicken-and-egg: the state bucket + lock table must exist before the
`backend "s3"` block can be initialized. Bootstrap them in a separate,
minimal Terraform stack (or with the AWS CLI), then run `terraform init`
here.

---

## Common operations

```bash
# Plan only the data tier
terraform plan -target=module.data

# Refresh a specific output
terraform output cognito_user_pool_id

# Force re-create the Lambda zip
rm modules/compute/build/lambda.zip
terraform apply -target=module.compute

# Drift detection (read-only)
terraform plan -detailed-exitcode
```

### Destroying

Several resources are marked `deletion_protection = true` or have similar
guards. To tear the whole stack down you'll need to disarm them first:

```bash
# Aurora cluster
aws rds modify-db-cluster --db-cluster-identifier fintech-prod-ledger \
    --no-deletion-protection --apply-immediately

# DynamoDB tables
aws dynamodb update-table --table-name fintech-prod-ledger \
    --deletion-protection-enabled false

# Cognito user pool
aws cognito-idp update-user-pool --user-pool-id <id> --deletion-protection INACTIVE

# ALB
aws elbv2 modify-load-balancer-attributes --load-balancer-arn <arn> \
    --attributes Key=deletion_protection.enabled,Value=false

# Audit bucket has Object Lock COMPLIANCE — objects CANNOT be deleted before
# their retention expires, even by root. Plan accordingly: either wait out
# retention or use a separate AWS account for non-prod test runs.

terraform destroy
```

---

## Troubleshooting

| Symptom                                                          | Cause / Fix                                                                                       |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `Error: creating WAFv2 WebACL: ... InvalidParameterException`    | WAF for CloudFront scope must be in `us-east-1`. The `aws.us_east_1` provider alias handles this. |
| `Error: creating IAM Role: EntityAlreadyExists`                  | A previous failed apply left an orphan IAM role. `terraform import` it or delete in console.      |
| Aurora apply hangs at "still creating"                           | First-time Aurora creation can take 10–15 min. Normal.                                            |
| `Error: error reading Secrets Manager Secret Version`            | Race condition on first apply — re-run `terraform apply`.                                         |
| `terraform test` fails with "invalid JSON policy"                | IAM policy document mock is missing. Run from the `terraform/` dir; all mocks are in `tests/`.    |
| `Error: ... DBClusterAlreadyExistsFault`                         | Final-snapshot name collision after a previous destroy. Bump `final_snapshot_identifier`.         |
| Lambda timing out connecting to RDS                              | Cold start + VPC ENI attachment. Lambda is already at `reserved_concurrent_executions = 100`.     |
| `terraform destroy` fails on S3 buckets                          | Versioned objects + Object Lock prevent deletion. See "Destroying" above.                         |

---

## Layout reference

```
terraform/
├── .gitignore
├── .checkov.yaml                     checkov skip list (shared by CI and local script)
├── .tflint.hcl                       tflint config + AWS ruleset plugin
├── README.md                         ← you are here
├── TESTS.md                          test descriptions + checkov skip rationale
├── versions.tf
├── providers.tf
├── variables.tf
├── locals.tf
├── main.tf
├── outputs.tf
├── scripts/
│   └── test-local.sh                 local CI mirror (fmt · validate · test · tflint · checkov)
├── tests/
│   ├── plan.tftest.hcl
│   ├── apply.tftest.hcl
│   ├── validation.tftest.hcl
│   ├── wiring.tftest.hcl
│   ├── network.tftest.hcl
│   ├── security.tftest.hcl
│   ├── data.tftest.hcl
│   ├── compute.tftest.hcl
│   ├── edge.tftest.hcl
│   └── observability.tftest.hcl
└── modules/
    ├── network/
    │   ├── main.tf                   VPC + endpoints
    │   ├── variables.tf
    │   └── outputs.tf
    ├── security/
    │   ├── main.tf                   KMS · IAM · Secrets Manager
    │   ├── variables.tf
    │   └── outputs.tf
    ├── data/
    │   ├── main.tf                   Aurora · Redis · DynamoDB · SQS
    │   ├── variables.tf
    │   └── outputs.tf
    ├── compute/
    │   ├── main.tf                   ALB (HTTPS) · ECS · Lambda · SG mesh
    │   ├── variables.tf
    │   └── outputs.tf
    ├── edge/
    │   ├── main.tf                   CloudFront · WAF · API GW · Cognito
    │   ├── variables.tf
    │   └── outputs.tf
    └── observability/
        ├── main.tf                   S3 · CloudTrail · GuardDuty · SFTP
        ├── variables.tf
        └── outputs.tf
```

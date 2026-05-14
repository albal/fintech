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
├── versions.tf         provider + version pins
├── providers.tf        aws + aws.us_east_1 (CloudFront WAF must live in us-east-1)
├── variables.tf        root input variables
├── locals.tf           name composition, AZ slicing, common tags
├── main.tf             wires the six child modules together
├── outputs.tf          top-level outputs (ALB DNS, CF domain, etc.)
├── tests/
│   ├── plan.tftest.hcl    8 plan-time tests
│   └── apply.tftest.hcl   4 apply-time tests against mocked AWS
└── modules/
    ├── network/        VPC (community module) + 2 gateway + 7 interface endpoints
    ├── security/       KMS CMK + IAM roles + Secrets Manager secrets
    ├── data/           Aurora · Redis · DynamoDB · SQS · DLQ
    ├── compute/        Internal ALB · ECS Fargate · 2 Lambda fns · SG mesh
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
| AWS provider     | `~> 5.50`     | Pinned in `versions.tf`                        |
| AWS credentials  | —             | `aws configure` or env vars, region us-east-1  |
| AWS account      | —             | Service quotas for VPC, ECS, RDS, EIPs         |
| Permissions      | Admin-ish     | This module creates IAM, KMS, VPC, RDS, etc.   |

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

Tests run entirely against mocked AWS — no credentials, no cost, ~10 seconds:

```bash
terraform test
```

```
tests/
├── plan.tftest.hcl     8 plan-time tests (naming, AZ scaling, domain options)
└── apply.tftest.hcl    4 apply-time tests (full graph against mocks)
```

What native tests cover:
- Naming cascades correctly across modules when `name` / `environment` change
- AZ count scales subnet creation
- Optional `domain_name` / `hosted_zone_id` paths plan + apply cleanly
- Full dependency graph evaluates without errors

What they **don't** cover well — **add a static analyzer for these:**
- Compliance assertions like "every S3 bucket has public access blocked"
- Open security group rules, hardcoded secrets, etc.

Recommended layer:

```bash
checkov -d . --framework terraform
# or
tfsec .
# or, in CI
trivy config .
```

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

- [x] KMS CMK with rotation, used by every service that supports it
- [x] All S3 buckets: versioned, encrypted, public access blocked
- [x] Audit bucket: Object Lock COMPLIANCE, 7-year retention
- [x] Aurora: encrypted, deletion protection, `rds.force_ssl = 1`, multi-AZ, IAM auth on
- [x] Redis: at-rest + in-transit encryption, AUTH token, multi-AZ failover
- [x] DynamoDB: PITR, KMS, deletion protection
- [x] SQS: KMS, redrive policy → DLQ after 5 retries
- [x] CloudFront: WAF with managed rule groups + per-IP rate limit
- [x] API Gateway: JWT authorizer via Cognito, structured access logs
- [x] ECS: Container Insights, `readonlyRootFilesystem`, ECS Exec via KMS
- [x] Lambda: in-VPC, KMS, X-Ray, DLQ-aware event source mapping
- [x] CloudTrail: multi-region, log-file validation, KMS, S3 + Lambda data events
- [x] GuardDuty: enabled with S3 + malware protection
- [x] VPC: private subnets, NAT per AZ, flow logs to CloudWatch
- [x] VPC endpoints: S3 + DynamoDB (gateway), Secrets/KMS/ECR/Logs/SQS/STS (interface)

Things you'll still want to do before going live:

- [ ] Replace the placeholder `public.ecr.aws/nginx/nginx` image with your real app
- [ ] Replace the placeholder Lambda zip with actual handler code
- [ ] Populate `<name>/payment-provider/api-key` in Secrets Manager
- [ ] Configure Secrets Manager rotation for the Aurora master credential
- [ ] Terminate TLS at the internal ALB (currently HTTP since API GW terminates)
- [ ] Restrict Transfer Family SFTP ingress to bank partner CIDRs (currently 0.0.0.0/0)
- [ ] Split the single CMK into per-service keys if you need strict PCI scope separation
- [ ] Set up CloudWatch alarms: DLQ depth > 0, Aurora CPU, ALB 5xx rate, WAF blocks
- [ ] Add Backup vault + AWS Backup plan for Aurora and DynamoDB
- [ ] Configure CloudFront logging to the audit bucket
- [ ] Add a remote state backend (S3 + DynamoDB lock table) — see below
- [ ] Run `checkov` / `tfsec` in CI and gate merges on it
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
| `terraform test` fails with "invalid JSON policy"                | You're not using the mocks in `tests/`. Run from the `terraform/` dir, not `tests/`.              |
| `Error: ... DBClusterAlreadyExistsFault`                         | Final-snapshot name collision after a previous destroy. Bump `final_snapshot_identifier`.         |
| Lambda timing out connecting to RDS                              | Cold start + VPC ENI attachment. Lambda is already at `reserved_concurrent_executions = 100`.     |
| `terraform destroy` fails on S3 buckets                          | Versioned objects + Object Lock prevent deletion. See "Destroying" above.                         |

---

## Layout reference

```
terraform/
├── .gitignore
├── README.md                         ← you are here
├── versions.tf
├── providers.tf
├── variables.tf
├── locals.tf
├── main.tf
├── outputs.tf
├── tests/
│   ├── plan.tftest.hcl
│   └── apply.tftest.hcl
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
    │   ├── main.tf                   ALB · ECS · Lambda · SG mesh
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

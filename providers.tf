provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

# WAF Web ACLs scoped to CloudFront must live in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

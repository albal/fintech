data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "${var.name}-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  common_tags = {
    Project     = var.name
    Environment = var.environment
    ManagedBy   = "terraform"
    Compliance  = "PCI-DSS"
  }
}

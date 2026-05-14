module "network" {
  source = "./modules/network"

  name     = local.name
  vpc_cidr = var.vpc_cidr
  azs      = local.azs
  tags     = local.common_tags
}

module "security" {
  source = "./modules/security"

  name = local.name
  tags = local.common_tags
}

module "data" {
  source = "./modules/data"

  name                     = local.name
  vpc_id                   = module.network.vpc_id
  vpc_cidr                 = module.network.vpc_cidr
  database_subnet_ids      = module.network.database_subnet_ids
  private_subnet_ids       = module.network.private_subnet_ids
  kms_key_arn              = module.security.kms_key_arn
  db_master_secret_arn     = module.security.db_master_secret_arn
  db_master_secret_version = module.security.db_master_secret_version_id
  tags                     = local.common_tags
}

module "compute" {
  source = "./modules/compute"

  name                  = local.name
  vpc_id                = module.network.vpc_id
  vpc_cidr              = module.network.vpc_cidr
  private_subnet_ids    = module.network.private_subnet_ids
  kms_key_arn           = module.security.kms_key_arn
  task_execution_role   = module.security.ecs_task_execution_role_arn
  task_role             = module.security.ecs_task_role_arn
  task_role_name        = module.security.ecs_task_role_name
  lambda_role_arn       = module.security.lambda_execution_role_arn
  lambda_role_name      = module.security.lambda_execution_role_name
  db_endpoint           = module.data.aurora_endpoint
  db_secret_arn         = module.security.db_master_secret_arn
  redis_endpoint        = module.data.redis_endpoint
  ledger_table_name     = module.data.ledger_table_name
  ledger_table_arn      = module.data.ledger_table_arn
  payments_queue_url    = module.data.payments_queue_url
  payments_queue_arn    = module.data.payments_queue_arn
  aurora_security_group = module.data.aurora_security_group_id
  redis_security_group  = module.data.redis_security_group_id
  tags                  = local.common_tags
}

module "edge" {
  source = "./modules/edge"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name               = local.name
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  alb_listener_arn   = module.compute.alb_listener_arn
  alb_security_group = module.compute.alb_security_group_id
  domain_name        = var.domain_name
  hosted_zone_id     = var.hosted_zone_id
  tags               = local.common_tags
}

module "observability" {
  source = "./modules/observability"

  name               = local.name
  vpc_id             = module.network.vpc_id
  private_subnet_ids = module.network.private_subnet_ids
  kms_key_arn        = module.security.kms_key_arn
  transfer_role_arn  = module.security.transfer_role_arn
  tags               = local.common_tags
}

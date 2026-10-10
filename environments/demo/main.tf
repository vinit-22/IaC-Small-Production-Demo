data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }

locals {
  azs           = slice(data.aws_availability_zones.available.names, 0, 2)
  bucket_name   = "${var.name}-uploads-${data.aws_caller_identity.current.account_id}"
  function_name = "${var.name}-upload"
}

module "vpc" {
  source       = "../../modules/vpc"
  name         = var.name
  cidr         = "10.0.0.0/16"
  azs          = local.azs
  public_cidrs = ["10.0.0.0/24", "10.0.1.0/24"]
  app_cidrs    = ["10.0.10.0/24", "10.0.11.0/24"]
  data_cidrs   = ["10.0.20.0/24", "10.0.21.0/24"]
}

module "iam" {
  source               = "../../modules/iam"
  name                 = var.name
  region               = var.region
  account_id           = data.aws_caller_identity.current.account_id
  upload_bucket_name   = local.bucket_name
  lambda_function_name = local.function_name
}

module "ecs" {
  source                  = "../../modules/ecs"
  name                    = var.name
  region                  = var.region
  vpc_id                  = module.vpc.vpc_id
  public_subnet_ids       = module.vpc.public_subnet_ids
  app_subnet_ids          = module.vpc.app_subnet_ids
  instance_profile_name   = module.iam.ec2_instance_profile_name
  task_execution_role_arn = module.iam.task_execution_role_arn

  services = {
    "nginx-a" = "<html><body style=\"background:#d4edda\"><h1>Hello from nginx-a</h1></body></html>"
    "nginx-b" = "<html><body style=\"background:#cce5ff\"><h1>Hello from nginx-b</h1></body></html>"
  }
}

module "lambda_api" {
  source          = "../../modules/lambda_api"
  name            = var.name
  function_name   = local.function_name
  bucket_name     = local.bucket_name
  lambda_role_arn = module.iam.lambda_role_arn
  source_file     = "${path.root}/../../app/lambda/handler.py"
}

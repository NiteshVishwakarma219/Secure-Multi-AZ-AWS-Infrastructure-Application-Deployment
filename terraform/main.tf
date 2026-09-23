
module "networking" {
  source = "./modules/networking"

  project_name             = var.project_name
  vpc_cidr                 = var.vpc_cidr
  azs                      = var.azs
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
  single_nat_gateway       = var.single_nat_gateway
  enable_flow_logs         = false
  tags                     = local.tags
}

module "security_groups" {
  source = "./modules/security-groups"

  project_name = var.project_name
  vpc_id       = module.networking.vpc_id
  backend_port = 8000
  tags         = local.tags
}

module "storage" {
  source = "./modules/storage"

  project_name = var.project_name
  ec2_role_arn = module.iam.ec2_role_arn

  tags = local.tags
}
module "secrets" {
  source = "./modules/secrets"

  project_name = var.project_name
  db_username  = var.db_username
  db_password  = var.db_password
  kms_key_id   = module.storage.kms_key_id

  tags = local.tags
}


module "iam" {
  source = "./modules/iam"

  project_name = var.project_name

  secrets_manager_arns = [
    module.secrets.db_credentials_secret_arn,
    module.secrets.app_secrets_secret_arn,
  ]

  s3_bucket_arns = [
    module.storage.bucket_arns["documents"],
    module.storage.bucket_arns["artifacts"],
  ]

  kms_key_arns = [
    module.storage.kms_key_arn
  ]

  tags = local.tags
}

module "database" {
  source = "./modules/database"

  project_name          = var.project_name
  private_db_subnet_ids = module.networking.private_db_subnet_ids
  db_sg_id              = module.security_groups.db_sg_id
  kms_key_id            = module.storage.kms_key_arn

  db_username = module.secrets.db_username
  db_password = module.secrets.db_password

  multi_az = var.db_multi_az

  tags = local.tags
}

module "load_balancer" {
  source = "./modules/load-balancer"

  project_name      = var.project_name
  vpc_id            = module.networking.vpc_id
  public_subnet_ids = module.networking.public_subnet_ids
  alb_sg_id         = module.security_groups.alb_sg_id
  backend_port      = 8000

  logs_bucket_name    = module.storage.bucket_names["logs"]
  alb_certificate_arn = module.edge.alb_certificate_arn

  tags = local.tags

  # Make sure the S3 logs bucket policy exists
  # before ALB access logging is configured.
  depends_on = [
    aws_s3_bucket_policy.logs
  ]
}

module "compute" {
  source = "./modules/compute"

  project_name           = var.project_name
  instance_profile_name  = module.iam.ec2_instance_profile_name
  app_sg_id              = module.security_groups.app_sg_id
  private_app_subnet_ids = module.networking.private_app_subnet_ids

  target_group_arns = module.load_balancer.target_group_arns

  db_credentials_secret_arn = module.secrets.db_credentials_secret_arn
  app_secrets_secret_arn    = module.secrets.app_secrets_secret_arn

  db_endpoint = module.database.db_address
  db_name     = module.database.db_name

  kms_key_arn = module.storage.kms_key_arn

  min_size         = var.asg_min_size
  max_size         = var.asg_max_size
  desired_capacity = var.asg_desired_capacity

  tags = local.tags
}

module "edge" {
  source = "./modules/edge"

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  project_name        = var.project_name
  domain_name         = var.domain_name
  create_route53_zone = var.create_route53_zone
  enable_cloudfront   = var.enable_cloudfront

  alb_dns_name = module.load_balancer.alb_dns_name
  alb_zone_id  = module.load_balancer.alb_zone_id

  tags = local.tags
}

module "monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name

  aws_region = var.aws_region

  alarm_email = var.alarm_email

  alarm_phone_number = var.alarm_phone_number

  asg_name = module.compute.asg_name

  alb_arn_suffix = module.load_balancer.alb_arn_suffix

  target_group_arn_suffixes = module.load_balancer.target_group_arn_suffixes

  db_instance_id = module.database.db_instance_id

  tags = local.tags
}

module "security_monitoring" {
  source = "./modules/security-monitoring"

  project_name = var.project_name

  vpc_id = module.networking.vpc_id

  logs_bucket_name = module.storage.bucket_names["logs"]
  logs_bucket_arn  = module.storage.bucket_arns["logs"]

  sns_topic_arn = module.monitoring.sns_topic_arn

  lambda_role_arn = module.iam.lambda_role_arn

  enable_guardduty    = var.enable_guardduty
  enable_security_hub = var.enable_security_hub
  enable_config       = var.enable_config

  tags = local.tags

  # CloudTrail and AWS Config need the bucket policy
  # before they start using the S3 bucket.
  depends_on = [
    aws_s3_bucket_policy.logs
  ]
}

module "backup" {
  source = "./modules/backup"

  project_name     = var.project_name
  backup_tag_value = var.environment

  tags = local.tags
}


# ============================================================
# DATA SOURCES
# ============================================================

data "aws_caller_identity" "current" {}

data "aws_elb_service_account" "main" {}


# ============================================================
# CENTRAL LOGGING S3 BUCKET POLICY
# ============================================================
#
# This bucket receives:
#
# 1. ALB access logs
# 2. CloudTrail logs
# 3. AWS Config logs
#
# The bucket itself is created by the storage module.
# This policy grants only the required service permissions.
#
# IMPORTANT:
# The logs bucket should use S3-managed encryption (SSE-S3)
# rather than the project KMS key because ALB log delivery
# has compatibility requirements around bucket encryption.
#
# ============================================================

resource "aws_s3_bucket_policy" "logs" {
  bucket = module.storage.bucket_names["logs"]

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [

      # ======================================================
      # CLOUDTRAIL - BUCKET PERMISSION CHECK
      # ======================================================

      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"

        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }

        Action   = "s3:GetBucketAcl"
        Resource = module.storage.bucket_arns["logs"]
      },


      # ======================================================
      # CLOUDTRAIL - WRITE LOGS
      # ======================================================

      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"

        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }

        Action = "s3:PutObject"

        Resource = "${module.storage.bucket_arns["logs"]}/cloudtrail/AWSLogs/${data.aws_caller_identity.current.account_id}/*"

        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },


      # ======================================================
      # AWS CONFIG - BUCKET PERMISSION CHECK
      # ======================================================

      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"

        Principal = {
          Service = "config.amazonaws.com"
        }

        Action = [
          "s3:GetBucketAcl",
          "s3:ListBucket"
        ]

        Resource = module.storage.bucket_arns["logs"]
      },


      # ======================================================
      # AWS CONFIG - WRITE CONFIGURATION HISTORY
      # ======================================================

      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"

        Principal = {
          Service = "config.amazonaws.com"
        }

        Action = "s3:PutObject"

        Resource = "${module.storage.bucket_arns["logs"]}/aws-config/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"

        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },


      # ======================================================
      # ALB ACCESS LOG DELIVERY
      # ======================================================

      {
        Sid    = "ALBAccessLogsWrite"
        Effect = "Allow"

        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }

        Action = "s3:PutObject"

        Resource = "${module.storage.bucket_arns["logs"]}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"

        Condition = {
          ArnLike = {
            "aws:SourceArn" = "arn:aws:elasticloadbalancing:${var.aws_region}:${data.aws_caller_identity.current.account_id}:loadbalancer/*"
          }

          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}


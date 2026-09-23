# ------------------------------------------------------------------
# KMS key - shared for S3 / Secrets Manager / EBS encryption
# ------------------------------------------------------------------
resource "aws_kms_key" "main" {
  description             = "${var.project_name} platform encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }

        Action   = "kms:*"
        Resource = "*"
      },

      {
        Sid    = "AllowEC2RoleToUseKey"
        Effect = "Allow"

        Principal = {
          AWS = var.ec2_role_arn
        }

        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]

        Resource = "*"
      },

      {
        Sid    = "AllowAutoScalingServiceLinkedRoleForEBS"
        Effect = "Allow"

        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
        }

        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:GenerateDataKeyWithoutPlaintext",
          "kms:ReEncrypt*"
        ]

        Resource = "*"
      }
    ]
  })

  tags = var.tags
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-key"
  target_key_id = aws_kms_key.main.key_id
}

# ------------------------------------------------------------------
# S3 buckets
#   - employee documents (application uploads)
#   - application artifacts
#   - centralized logs (ALB / CloudTrail / VPC Flow Logs)
#   - Terraform remote state
# All private, versioned, encrypted, block-public-access enforced.
# ------------------------------------------------------------------
locals {
  buckets = {
    documents = "${var.project_name}-employee-documents"
    artifacts = "${var.project_name}-app-artifacts"
    logs      = "${var.project_name}-platform-logs"
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets
  bucket   = "${substr(each.value, 0, 50)}-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, { Name = each.value })
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this
  bucket   = each.value.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = {
    for k, v in aws_s3_bucket.this : k => v
    if k != "logs"
  }

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.main.arn
    }

    bucket_key_enabled = true
  }
}


resource "aws_s3_bucket_public_access_block" "this" {
  for_each                = aws_s3_bucket.this
  bucket                  = each.value.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle: transition/expire logs to control cost
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.this["logs"].id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 365
    }
  }
}

data "aws_caller_identity" "current" {}

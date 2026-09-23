data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ------------------------------------------------------------------
# CloudTrail - "who did what in AWS"
# ------------------------------------------------------------------
resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = var.logs_bucket_name
  s3_key_prefix                 = "cloudtrail"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true

  tags = var.tags
}

# NOTE: the bucket policy that grants CloudTrail write access to
# var.logs_bucket_name is intentionally NOT defined here. The same
# "logs" bucket also receives ALB access logs (loadbalancer module),
# and S3 allows only ONE bucket policy document per bucket. Both sets
# of statements are combined into a single aws_s3_bucket_policy
# resource in the root module (environments/dev/main.tf) instead.

# ------------------------------------------------------------------
# VPC Flow Logs - "what traffic flowed where"
# ------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/${var.project_name}/vpc-flow-logs"
  retention_in_days = 90

  tags = var.tags
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.project_name}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project_name}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "${aws_cloudwatch_log_group.flow_logs.arn}:*"
    }]
  })
}

resource "aws_flow_log" "main" {
  vpc_id               = var.vpc_id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn

  tags = var.tags
}

# ------------------------------------------------------------------
# GuardDuty - managed threat detection
# ------------------------------------------------------------------
resource "aws_guardduty_detector" "main" {
  count  = var.enable_guardduty ? 1 : 0
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = var.tags
}

# ------------------------------------------------------------------
# AWS Config - resource configuration & compliance state
# ------------------------------------------------------------------
resource "aws_config_configuration_recorder" "main" {
  count    = var.enable_config ? 1 : 0
  name     = "${var.project_name}-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "main" {
  count          = var.enable_config ? 1 : 0
  name           = "${var.project_name}-delivery-channel"
  s3_bucket_name = var.logs_bucket_name
  s3_key_prefix  = "aws-config"

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_configuration_recorder_status" "main" {
  count      = var.enable_config ? 1 : 0
  name       = aws_config_configuration_recorder.main[0].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.main]
}

resource "aws_iam_role" "config" {
  count = var.enable_config ? 1 : 0
  name  = "${var.project_name}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  count      = var.enable_config ? 1 : 0
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

# Example managed rules: flag exactly the misconfigurations this project
# intentionally tests (Section 36) - public S3, open SSH, etc.
resource "aws_config_config_rule" "s3_public_read_prohibited" {
  count = var.enable_config ? 1 : 0
  name  = "${var.project_name}-s3-public-read-prohibited"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

resource "aws_config_config_rule" "restricted_ssh" {
  count = var.enable_config ? 1 : 0
  name  = "${var.project_name}-restricted-ssh"

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }

  depends_on = [aws_config_configuration_recorder.main]
}

# ------------------------------------------------------------------
# Security Hub - centralized findings from GuardDuty + Config + others
# ------------------------------------------------------------------
resource "aws_securityhub_account" "main" {
  count = var.enable_security_hub ? 1 : 0
}

resource "aws_securityhub_standards_subscription" "cis" {
  count         = var.enable_security_hub ? 1 : 0
  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.main]
}

# ------------------------------------------------------------------
# EventBridge -> Lambda -> SNS for automated security response
#   Example: GuardDuty finding fires -> Lambda notifies/remediates
# ------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  count       = var.enable_guardduty ? 1 : 0
  name        = "${var.project_name}-guardduty-findings"
  description = "Route GuardDuty findings to the security response Lambda"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_lambda" {
  count     = var.enable_guardduty ? 1 : 0
  rule      = aws_cloudwatch_event_rule.guardduty_findings[0].name
  target_id = "security-response-lambda"
  arn       = aws_lambda_function.security_response.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.enable_guardduty ? 1 : 0
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_response.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_findings[0].arn
}

data "archive_file" "security_response" {
  type        = "zip"
  output_path = "${path.module}/build/security_response.zip"

  source {
    content  = <<-PY
      import json
      import os
      import boto3

      sns = boto3.client("sns")
      TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]

      def handler(event, context):
          # Minimal, auditable response: notify the security channel.
          # Extend here for automated remediation (isolate instance,
          # revoke a security group rule, disable a key, etc.) once
          # the specific finding types this project handles are decided.
          message = json.dumps(event)
          sns.publish(
              TopicArn=TOPIC_ARN,
              Subject="Security finding detected",
              Message=message,
          )
          return {"status": "notified"}
    PY
    filename = "index.py"
  }
}

resource "aws_lambda_function" "security_response" {
  function_name    = "${var.project_name}-security-response"
  role             = var.lambda_role_arn
  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.security_response.output_path
  source_code_hash = data.archive_file.security_response.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      SNS_TOPIC_ARN = var.sns_topic_arn
    }
  }

  tags = var.tags
}

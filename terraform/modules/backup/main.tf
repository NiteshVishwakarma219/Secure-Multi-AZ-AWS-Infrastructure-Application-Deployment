resource "aws_backup_vault" "main" {
  name = "${substr(var.project_name, 0, 35)}-backup-vault"
  tags = var.tags
}

resource "aws_backup_plan" "main" {
  name = "${substr(var.project_name, 0, 35)}-backup-plan"

  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = var.backup_schedule

    lifecycle {
      delete_after = var.retention_days
    }
  }

  tags = var.tags
}

resource "aws_iam_role" "backup" {
  name = "${substr(var.project_name, 0, 35)}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}
resource "aws_backup_selection" "main" {
  name         = "${var.project_name}-backup-select"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.main.id

  resources = ["*"]

  condition {
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.backup_tag_value
    }
  }
}

# ------------------------------------------------------------------
# DB credentials - never hardcoded in Terraform/Docker/Git.
# The application reads this at runtime instead.
# ------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/db-credentials"
  description             = "EEMS PostgreSQL credentials"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = 0 # dev/test project gets destroyed & recreated often; skip the 30-day soft-delete window

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}
# App-level secrets (JWT signing key, SMTP creds for email notifications, etc.)
resource "random_password" "jwt_secret" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "app_secrets" {
  name                    = "${var.project_name}/app-secrets"
  description             = "EEMS application secrets (JWT signing key, SMTP credentials)"
  kms_key_id              = var.kms_key_id
  recovery_window_in_days = 0 # dev/test project gets destroyed & recreated often; skip the 30-day soft-delete window

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    jwt_secret    = random_password.jwt_secret.result
    smtp_host     = ""
    smtp_username = ""
    smtp_password = ""
  })

  lifecycle {
    ignore_changes = [secret_string] # fill in real SMTP values out-of-band, don't let Terraform overwrite them
  }
}

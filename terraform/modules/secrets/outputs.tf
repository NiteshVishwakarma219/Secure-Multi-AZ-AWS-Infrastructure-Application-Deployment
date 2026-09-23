output "db_credentials_secret_arn" {
  value = aws_secretsmanager_secret.db_credentials.arn
}

output "app_secrets_secret_arn" {
  value = aws_secretsmanager_secret.app_secrets.arn
}

output "db_password" {
  value     = var.db_password
  sensitive = true
}

output "db_username" {
  value = var.db_username
}

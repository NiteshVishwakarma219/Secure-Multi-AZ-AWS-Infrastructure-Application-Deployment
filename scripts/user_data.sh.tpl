#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------------
# EEMS host bootstrap
#   - installs Docker
#   - pulls DB credentials + app secrets from Secrets Manager at boot
#     (never baked into the AMI or the Terraform state as plaintext env)
#   - runs the frontend and backend containers
# ------------------------------------------------------------------

dnf update -y
dnf install -y docker jq awscli
systemctl enable docker
systemctl start docker

REGION="${aws_region}"

DB_SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${db_credentials_secret_arn}" \
  --region "$REGION" \
  --query SecretString --output text)

APP_SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "${app_secrets_secret_arn}" \
  --region "$REGION" \
  --query SecretString --output text)

DB_USERNAME=$(echo "$DB_SECRET_JSON" | jq -r .username)
DB_PASSWORD=$(echo "$DB_SECRET_JSON" | jq -r .password)
JWT_SECRET=$(echo "$APP_SECRET_JSON" | jq -r .jwt_secret)

DB_HOST="${db_endpoint}"

docker network create eems-net || true

docker run -d \
  --name eems-backend \
  --network eems-net \
  --restart unless-stopped \
  -p 8000:8000 \
  -e DB_HOST="$DB_HOST" \
  -e DB_USERNAME="$DB_USERNAME" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e JWT_SECRET="$JWT_SECRET" \
  ${backend_image}

docker run -d \
  --name eems-frontend \
  --network eems-net \
  --restart unless-stopped \
  -p 80:80 \
  ${frontend_image}

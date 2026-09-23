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
dnf install -y docker jq awscli amazon-ssm-agent
systemctl enable docker
systemctl start docker

# SSM Agent isn't pre-installed on this AMI - install it explicitly.
systemctl enable amazon-ssm-agent --now || true

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
DB_PORT="5432"
DB_NAME_VAL="${db_name}"

# Prisma (used by the backend) needs a full connection URL, not
# individual host/user/pass vars. DIRECT_URL is the same here since
# there's no connection pooler (e.g. PgBouncer) in front of RDS.
DATABASE_URL="postgresql://$DB_USERNAME:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME_VAL?schema=public"
DIRECT_URL="$DATABASE_URL"

docker network create eems-net || true

docker run -d \
  --name nexops-backend \
  --network eems-net \
  --restart unless-stopped \
  -p 8000:8000 \
  -e DATABASE_URL="$DATABASE_URL" \
  -e DIRECT_URL="$DIRECT_URL" \
  -e DB_HOST="$DB_HOST" \
  -e DB_PORT="$DB_PORT" \
  -e DB_NAME="$DB_NAME_VAL" \
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

# ------------------------------------------------------------------
# Diagnostic: print container logs to this script's own stdout.
# cloud-init tees this script's stdout to both
# /var/log/cloud-init-output.log AND the EC2 serial console, so this
# shows up in `aws ec2 get-console-output` without needing SSM.
# ------------------------------------------------------------------
sleep 25
echo "===== SSM agent status ====="
systemctl status amazon-ssm-agent --no-pager || true
echo "===== nexops-backend status/logs (first boot) ====="
docker ps -a --filter "name=nexops-backend"
docker logs nexops-backend 2>&1 || true
echo "===== eems-frontend status/logs (first boot) ====="
docker ps -a --filter "name=eems-frontend"
docker logs eems-frontend 2>&1 || true
echo "===== end diagnostic block ====="

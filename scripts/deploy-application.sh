#!/bin/bash
set -e
cd /opt/eems
# Application deployment commands will be finalized in Step 15.
docker compose pull
docker compose up -d

#!/bin/bash
set -e
curl -f http://localhost/ || exit 1
curl -f http://localhost:8000/ || exit 1
echo "Application health checks passed."

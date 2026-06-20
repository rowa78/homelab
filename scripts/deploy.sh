#!/bin/bash
set -euo pipefail

REPO=/homelab

echo "[deploy] Starting deployment at $(date)"

# Pull latest changes
git -C "$REPO" pull origin main
echo "[deploy] Git pull complete"

# Decrypt secrets
SOPS_AGE_KEY_FILE="$REPO/.age-key.txt" \
  sops --decrypt "$REPO/secrets.enc.env" > "$REPO/.env"
echo "[deploy] Secrets decrypted"

# Deploy all stacks
for stack_dir in "$REPO"/apps/*/; do
  compose_file="$stack_dir/docker-compose.yml"
  [ -f "$compose_file" ] || continue
  stack_name=$(basename "$stack_dir")
  echo "[deploy] Updating stack: $stack_name"
  docker-compose \
    -f "$compose_file" \
    --env-file "$REPO/.env" \
    up -d --remove-orphans
done

echo "[deploy] Deployment complete at $(date)"

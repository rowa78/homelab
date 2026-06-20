#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_HOST="infra"

echo "[deploy] Starting deployment at $(date)"

# Pull latest changes
git -C "$REPO" pull origin main
echo "[deploy] Git pull complete"

# Decrypt secrets
SOPS_AGE_KEY_FILE="$REPO/.age-key.txt" \
  sops --decrypt "$REPO/secrets.enc.env" > "$REPO/.env"
echo "[deploy] Secrets decrypted"

# Write SSH deploy key (only needed for remote hosts)
SSH_KEY_FILE=$(mktemp)
chmod 600 "$SSH_KEY_FILE"
echo "$DEPLOY_SSH_KEY_B64" | base64 -d > "$SSH_KEY_FILE"
trap "rm -f '$SSH_KEY_FILE'" EXIT

SSH_OPTS=(-i "$SSH_KEY_FILE" -o StrictHostKeyChecking=accept-new -o BatchMode=yes)

deploy_stack_local() {
  local stack="$1"
  local compose_file="$REPO/apps/$stack/docker-compose.yml"
  [ -f "$compose_file" ] || { echo "[deploy]   Warnung: $compose_file nicht gefunden, übersprungen"; return; }
  docker-compose -f "$compose_file" --env-file "$REPO/.env" up -d --remove-orphans
}

deploy_stack_remote() {
  local host="$1"
  local stack="$2"
  ssh "${SSH_OPTS[@]}" "$host" \
    "docker-compose -f /opt/homelab/apps/$stack/docker-compose.yml \
     --env-file /opt/homelab/.env up -d --remove-orphans"
}

# Deploy to each host
for host_dir in "$REPO"/hosts/*/; do
  host=$(basename "$host_dir")
  stacks_file="$host_dir/stacks"
  [ -f "$stacks_file" ] || continue

  echo "[deploy] Host: $host"

  if [ "$host" = "$LOCAL_HOST" ]; then
    # Infra-Host: lokales Deployment, kein SSH
    while IFS= read -r stack; do
      [[ "$stack" =~ ^#|^$ ]] && continue
      echo "[deploy]   Stack: $stack (lokal)"
      deploy_stack_local "$stack"
    done < "$stacks_file"
  else
    # Remote-Host: Repo synchronisieren, dann via SSH deployen
    rsync -az --delete \
      -e "ssh ${SSH_OPTS[*]}" \
      --exclude='.git/' \
      --exclude='.env' \
      --exclude='.age-key.txt' \
      "$REPO/" "$host:/opt/homelab/"
    scp "${SSH_OPTS[@]}" "$REPO/.env" "$host:/opt/homelab/.env"

    while IFS= read -r stack; do
      [[ "$stack" =~ ^#|^$ ]] && continue
      echo "[deploy]   Stack: $stack"
      deploy_stack_remote "$host" "$stack"
    done < "$stacks_file"
  fi

  echo "[deploy] Host $host done"
done

echo "[deploy] Deployment complete at $(date)"

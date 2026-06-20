#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_HOST="infra"

usage() {
  echo "Usage: $0 <stack> [host]"
  echo ""
  echo "  stack   Name des Stacks (Verzeichnisname unter apps/)"
  echo "  host    Zielhost (default: $LOCAL_HOST)"
  echo ""
  echo "Beispiele:"
  echo "  $0 traefik"
  echo "  $0 traefik infra"
  echo "  $0 oauth2-proxy docker-apps-1"
  exit 1
}

[ "${1:-}" = "" ] && usage

STACK="$1"
HOST="${2:-$LOCAL_HOST}"
COMPOSE_FILE="$REPO/apps/$STACK/docker-compose.yml"

[ -f "$COMPOSE_FILE" ] || { echo "Fehler: $COMPOSE_FILE nicht gefunden"; exit 1; }

if [ "$HOST" = "$LOCAL_HOST" ]; then
  echo "[$STACK] Neustart auf $HOST (lokal)..."
  docker compose -f "$COMPOSE_FILE" --env-file "$REPO/.env" up -d --force-recreate
else
  SSH_KEY_FILE=$(mktemp)
  chmod 600 "$SSH_KEY_FILE"
  echo "${DEPLOY_SSH_KEY_B64:-}" | base64 -d > "$SSH_KEY_FILE"
  trap "rm -f '$SSH_KEY_FILE'" EXIT
  SSH_OPTS=(-i "$SSH_KEY_FILE" -o StrictHostKeyChecking=accept-new -o BatchMode=yes)

  echo "[$STACK] Neustart auf $HOST (remote)..."
  ssh "${SSH_OPTS[@]}" "$HOST" \
    "docker compose -f /opt/homelab/apps/$STACK/docker-compose.yml \
     --env-file /opt/homelab/.env up -d --force-recreate"
fi

echo "[$STACK] Fertig."

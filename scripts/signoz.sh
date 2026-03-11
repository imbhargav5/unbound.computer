#!/usr/bin/env bash

set -euo pipefail

SIGNOZ_DIR="$HOME/Code/signoz"
SIGNOZ_DOCKER_DIR="$SIGNOZ_DIR/deploy/docker"
SIGNOZ_COMPOSE_FILE="$SIGNOZ_DOCKER_DIR/docker-compose.yaml"

print_usage() {
  cat <<'EOF'
Usage: ./scripts/signoz.sh <start|stop|status>
EOF
}

print_missing_checkout() {
  cat <<EOF
error: SigNoz checkout not found at:
  $SIGNOZ_COMPOSE_FILE

Recovery:
  git clone -b main https://github.com/SigNoz/signoz.git "$SIGNOZ_DIR"
EOF
}

require_checkout() {
  if [ ! -f "$SIGNOZ_COMPOSE_FILE" ]; then
    print_missing_checkout >&2
    exit 1
  fi
}

run_compose() {
  (cd "$SIGNOZ_DOCKER_DIR" && docker compose "$@")
}

case "${1:-}" in
  start)
    require_checkout
    run_compose up -d --remove-orphans
    ;;
  stop)
    require_checkout
    run_compose down
    ;;
  status)
    require_checkout
    run_compose ps
    cat <<'EOF'

Expected local endpoints:
  UI: http://localhost:3301
  OTLP HTTP: http://localhost:4318
  OTLP gRPC: localhost:4317
EOF
    ;;
  *)
    print_usage >&2
    exit 1
    ;;
esac

#!/usr/bin/env bash
# Builds, restarts the dev daemon, and optionally launches the macOS app.
# Usage:
#   ./scripts/dev-daemon.sh          # build + restart daemon (foreground)
#   ./scripts/dev-daemon.sh --app    # build + restart daemon + run macOS app

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DAEMON_DIR="$ROOT/apps/daemon"
BASE_DIR="$HOME/.unbound-dev"
SOCKET="$BASE_DIR/daemon.sock"
PID_FILE="$BASE_DIR/daemon.pid"
ENV_FILE="$DAEMON_DIR/.env.local"

# ── Build daemon ──────────────────────────────────────────────
echo "Building daemon..."
cd "$DAEMON_DIR"
cargo build -p daemon-bin
DAEMON_BIN="$DAEMON_DIR/target/debug/unbound-daemon"

if [ ! -f "$DAEMON_BIN" ]; then
  echo "error: daemon binary not found at $DAEMON_BIN"
  exit 1
fi

# ── Stop existing dev daemon ──────────────────────────────────
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "Stopping existing dev daemon (PID $PID)..."
    kill "$PID" 2>/dev/null || true
    for i in $(seq 1 12); do
      kill -0 "$PID" 2>/dev/null || break
      sleep 0.25
    done
    kill -9 "$PID" 2>/dev/null || true
  fi
fi
rm -f "$SOCKET" "$PID_FILE"

# ── Load env vars ─────────────────────────────────────────────
if [ -f "$ENV_FILE" ]; then
  echo "Loading env from $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

# ── Start daemon ──────────────────────────────────────────────
mkdir -p "$BASE_DIR"

if [[ "${1:-}" == "--app" ]]; then
  # Background the daemon, wait for socket, then launch the app
  echo "Starting dev daemon in background (base-dir: $BASE_DIR)..."
  RUST_LOG="${RUST_LOG:-debug}" "$DAEMON_BIN" start --base-dir "$BASE_DIR" --foreground &
  DAEMON_PID=$!

  # Wait for socket (daemon init includes auth/network calls that can be slow)
  echo "Waiting for daemon socket..."
  for i in $(seq 1 240); do
    if [ -S "$SOCKET" ]; then
      echo "Dev daemon ready (PID $DAEMON_PID)"
      break
    fi
    if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
      echo "error: daemon process exited during startup"
      exit 1
    fi
    sleep 0.25
  done

  if [ ! -S "$SOCKET" ]; then
    echo "error: daemon did not start within 60s"
    kill "$DAEMON_PID" 2>/dev/null || true
    exit 1
  fi

  echo "Building and running macOS app..."
  cd "$ROOT/apps/macos"
  xcodebuild \
    -project unbound-macos.xcodeproj \
    -scheme unbound-macos \
    -configuration Debug \
    build 2>&1 | tail -5

  # Find and launch the built app
  BUILD_DIR=$(xcodebuild \
    -project unbound-macos.xcodeproj \
    -scheme unbound-macos \
    -configuration Debug \
    -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | awk '{print $3}')

  if [ -d "$BUILD_DIR/Unbound.app" ]; then
    echo "Launching Unbound.app..."
    open "$BUILD_DIR/Unbound.app"
  elif [ -d "$BUILD_DIR/unbound-macos.app" ]; then
    echo "Launching unbound-macos.app..."
    open "$BUILD_DIR/unbound-macos.app"
  else
    echo "warning: could not find built .app in $BUILD_DIR"
    ls "$BUILD_DIR"/*.app 2>/dev/null || echo "  (none)"
  fi

  echo "Daemon running in background (PID $DAEMON_PID). Kill with: kill $DAEMON_PID"
else
  # Run daemon in foreground — user sees logs directly, Ctrl+C stops it
  echo "Starting dev daemon in foreground (base-dir: $BASE_DIR)..."
  echo "Press Ctrl+C to stop."
  exec env RUST_LOG="${RUST_LOG:-debug}" "$DAEMON_BIN" start --base-dir "$BASE_DIR" --foreground
fi

#!/usr/bin/env bash
# Builds, restarts the dev daemon, and optionally launches the Tauri desktop app.
# Usage:
#   ./scripts/dev-daemon.sh          # build + restart daemon (foreground)
#   ./scripts/dev-daemon.sh --app    # build + restart daemon + desktop app

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DAEMON_DIR="$ROOT/apps/daemon"
DESKTOP_DIR="$ROOT/apps/desktop"
BASE_DIR="$HOME/.unbound-dev"
SOCKET="$BASE_DIR/daemon.sock"
PID_FILE="$BASE_DIR/daemon.pid"
APP_PID_FILE="$BASE_DIR/desktop-app.pid"
STARTUP_STATUS_FILE="$BASE_DIR/startup-status.json"
ENV_FILE="$DAEMON_DIR/.env.local"

DAEMON_PID=""
APP_PID=""
LAUNCHED_APP=0
CLEANING_UP=0

print_startup_status() {
  local elapsed_s="$1"
  if [ -f "$STARTUP_STATUS_FILE" ]; then
    echo "last startup status after ${elapsed_s}s:"
    sed 's/^/  /' "$STARTUP_STATUS_FILE"
  else
    echo "last startup status after ${elapsed_s}s: (not available)"
  fi
}

stop_pid_if_running() {
  local pid="$1"
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.25
    done
    kill -9 "$pid" 2>/dev/null || true
  fi
}

stop_dev_daemon() {
  echo "Stopping dev daemon (base-dir: $BASE_DIR)..."
  if [ -x "$DAEMON_BIN" ]; then
    "$DAEMON_BIN" --base-dir "$BASE_DIR" stop >/dev/null 2>&1 || true
  fi

  if [ -n "$DAEMON_PID" ]; then
    stop_pid_if_running "$DAEMON_PID"
  elif [ -f "$PID_FILE" ]; then
    local pid
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    stop_pid_if_running "$pid"
  fi

  rm -f \
    "$BASE_DIR/daemon.pid" \
    "$BASE_DIR/daemon.sock" \
    "$BASE_DIR/ably-auth.sock" \
    "$BASE_DIR/falco.sock" \
    "$BASE_DIR/nagato.sock" \
    "$BASE_DIR/daemon-ably.sock"
}

stop_dev_app() {
  echo "Stopping Unbound Desktop dev app..."

  if [ -n "$APP_PID" ]; then
    stop_pid_if_running "$APP_PID"
  elif [ -f "$APP_PID_FILE" ]; then
    local pid
    pid=$(cat "$APP_PID_FILE" 2>/dev/null || true)
    stop_pid_if_running "$pid"
  fi

  rm -f "$APP_PID_FILE"
}

cleanup_app_mode() {
  local exit_code="${1:-0}"
  if [ "$CLEANING_UP" -eq 1 ]; then
    return
  fi
  CLEANING_UP=1
  if [ "$LAUNCHED_APP" -eq 1 ]; then
    stop_dev_app
  fi
  stop_dev_daemon

  if [ "$LAUNCHED_APP" -eq 1 ]; then
    echo "Dev daemon and Unbound Desktop stopped."
  else
    echo "Dev daemon stopped."
  fi
}

monitor_background_processes() {
  while true; do
    if [ -n "$APP_PID" ] && ! kill -0 "$APP_PID" 2>/dev/null; then
      wait "$APP_PID"
      return $?
    fi

    if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
      wait "$DAEMON_PID"
      return $?
    fi

    sleep 1
  done
}

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
rm -f "$SOCKET" "$PID_FILE" "$STARTUP_STATUS_FILE"

# ── Load env vars ─────────────────────────────────────────────
if [ -f "$ENV_FILE" ]; then
  echo "Loading env from $ENV_FILE"
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

DAEMON_LOG_FILTER="${UNBOUND_DAEMON_RUST_LOG:-${UNBOUND_LOG_LEVEL:-debug}}"
echo "Using daemon log filter: $DAEMON_LOG_FILTER"

# ── Start daemon ──────────────────────────────────────────────
mkdir -p "$BASE_DIR"

if [[ "${1:-}" == "--app" ]]; then
  # Background the daemon, wait for socket, then launch the app
  echo "Starting dev daemon in background (base-dir: $BASE_DIR)..."
  START_TS=$(date +%s)
  UNBOUND_RUST_LOG="$DAEMON_LOG_FILTER" "$DAEMON_BIN" start --base-dir "$BASE_DIR" --foreground &
  DAEMON_PID=$!
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'cleanup_app_mode "$?"' EXIT

  # Wait for socket (daemon init includes auth/network calls that can be slow)
  echo "Waiting for daemon socket..."
  for i in $(seq 1 240); do
    if [ -S "$SOCKET" ]; then
      echo "Dev daemon ready (PID $DAEMON_PID)"
      break
    fi
    if ! kill -0 "$DAEMON_PID" 2>/dev/null; then
      ELAPSED=$(( $(date +%s) - START_TS ))
      echo "error: daemon process exited during startup"
      print_startup_status "$ELAPSED"
      exit 1
    fi
    sleep 0.25
  done

  if [ ! -S "$SOCKET" ]; then
    ELAPSED=$(( $(date +%s) - START_TS ))
    echo "error: daemon did not start within 60s"
    print_startup_status "$ELAPSED"
    kill "$DAEMON_PID" 2>/dev/null || true
    exit 1
  fi

  echo "Launching Tauri desktop app..."
  stop_dev_app
  cd "$DESKTOP_DIR"
  pnpm tauri:dev &
  APP_PID=$!
  echo "$APP_PID" > "$APP_PID_FILE"
  LAUNCHED_APP=1

  echo "Dev daemon running in background (PID $DAEMON_PID)."
  if [ "$LAUNCHED_APP" -eq 1 ]; then
    echo "Desktop app running in dev mode (PID $APP_PID)."
    echo "Press Ctrl+C to stop the desktop app and the daemon."
  else
    echo "Press Ctrl+C to stop the daemon."
  fi

  monitor_background_processes
else
  # Run daemon in foreground — user sees logs directly, Ctrl+C stops it
  echo "Starting dev daemon in foreground (base-dir: $BASE_DIR)..."
  echo "Press Ctrl+C to stop."
  exec env UNBOUND_RUST_LOG="$DAEMON_LOG_FILTER" "$DAEMON_BIN" start --base-dir "$BASE_DIR" --foreground
fi

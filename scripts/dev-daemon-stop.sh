#!/usr/bin/env bash
# Stops the dev daemon and Debug macOS app launched via daemon:dev:app.
# Usage:
#   ./scripts/dev-daemon-stop.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DAEMON_DIR="$ROOT/apps/daemon"
BASE_DIR="$HOME/.unbound-dev"
PID_FILE="$BASE_DIR/daemon.pid"
DAEMON_BIN="$DAEMON_DIR/target/debug/unbound-daemon"
APP_BUNDLE_ID="com.arni.unbound-macos-dev"
APP_PROCESS_PATTERN="/Unbound Dev.app/Contents/MacOS/Unbound Dev"

echo "Stopping Unbound Dev.app..."
osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

for _ in $(seq 1 20); do
  if ! pgrep -f "$APP_PROCESS_PATTERN" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

if pgrep -f "$APP_PROCESS_PATTERN" >/dev/null 2>&1; then
  echo "Force stopping Unbound Dev.app..."
  pkill -f "$APP_PROCESS_PATTERN" >/dev/null 2>&1 || true
fi

echo "Stopping dev daemon (base-dir: $BASE_DIR)..."
if [ -x "$DAEMON_BIN" ]; then
  "$DAEMON_BIN" --base-dir "$BASE_DIR" stop >/dev/null 2>&1 || true
fi

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" 2>/dev/null || true)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$PID" 2>/dev/null || break
      sleep 0.25
    done
    kill -9 "$PID" 2>/dev/null || true
  fi
fi

rm -f \
  "$BASE_DIR/daemon.pid" \
  "$BASE_DIR/daemon.sock" \
  "$BASE_DIR/ably-auth.sock" \
  "$BASE_DIR/falco.sock" \
  "$BASE_DIR/nagato.sock" \
  "$BASE_DIR/daemon-ably.sock"

echo "Dev daemon and Unbound Dev.app stopped."

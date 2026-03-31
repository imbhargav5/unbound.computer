#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${UNBOUND_DESKTOP_DEV_PORT:-1420}"
LISTEN_PID="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -n 1 || true)"

if [ -n "$LISTEN_PID" ]; then
  COMMAND="$(ps -p "$LISTEN_PID" -o command= 2>/dev/null || true)"

  case "$COMMAND" in
    *"$ROOT"*vite*"--port $PORT"*)
      echo "Reusing existing desktop dev server on port $PORT (PID $LISTEN_PID)."
      exit 0
      ;;
    *)
      echo "error: desktop dev server port $PORT is already in use by another process"
      if [ -n "$COMMAND" ]; then
        echo "  $COMMAND"
      else
        echo "  pid $LISTEN_PID"
      fi
      echo "Stop that process or start the desktop dev server separately before running Tauri."
      exit 1
      ;;
  esac
fi

exec pnpm dev

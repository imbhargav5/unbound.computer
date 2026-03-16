#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESKTOP_DIR="$ROOT_DIR/apps/desktop"
DAEMON_DIR="$ROOT_DIR/apps/daemon"
DIST_DIR="$ROOT_DIR/dist/macos"
APP_EXPORT_DIR="$DIST_DIR/export-app"
DAEMON_EXPORT_DIR="$DIST_DIR/export-daemon"
DESKTOP_TAURI_CONFIG="$DESKTOP_DIR/src-tauri/tauri.conf.json"
DESKTOP_CARGO_TOML="$DESKTOP_DIR/src-tauri/Cargo.toml"
DESKTOP_METADATA_BACKUP_DIR="$(mktemp -d)"

# Source release env vars (Supabase URL/key, presence config, etc.)
# These are compile-time values baked into the daemon binary.
if [[ -f "$ROOT_DIR/.env.release" ]]; then
  echo "==> Loading .env.release"
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env.release"
else
  echo "WARNING: No .env.release found at $ROOT_DIR/.env.release" >&2
  echo "  Daemon will be built with default (non-production) Supabase config." >&2
  echo "  Create .env.release with SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, etc." >&2
fi

MACOS_ARCH="${MACOS_ARCH:-arm64}"
APP_ZIP_NAME="${APP_ZIP_NAME:-unbound-desktop-macos-apple-silicon.zip}"
DAEMON_ARCHIVE_NAME="${DAEMON_ARCHIVE_NAME:-unbound-daemon-macos-apple-silicon.zip}"
MACOS_RELEASE_VERSION="${MACOS_RELEASE_VERSION:-}"
MACOS_BUILD_NUMBER="${MACOS_BUILD_NUMBER:-${CURRENT_PROJECT_VERSION:-}}"
MACOS_SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:-}"
MACOS_TEAM_ID="${MACOS_TEAM_ID:-}"
ALLOW_UNSIGNED="${ALLOW_UNSIGNED:-0}"

if [[ -z "$MACOS_RELEASE_VERSION" ]]; then
  if command -v pnpm >/dev/null 2>&1; then
    MACOS_RELEASE_VERSION="$(pnpm --silent tsx "$ROOT_DIR/scripts/release/get-current-version.ts")"
  elif command -v npx >/dev/null 2>&1; then
    MACOS_RELEASE_VERSION="$(npx --yes tsx "$ROOT_DIR/scripts/release/get-current-version.ts")"
  else
    echo "ERROR: pnpm or npx is required to read release version. Set MACOS_RELEASE_VERSION." >&2
    exit 1
  fi
fi

if [[ -z "$MACOS_BUILD_NUMBER" ]]; then
  MACOS_BUILD_NUMBER="$(date +%s)"
fi

if [[ "$ALLOW_UNSIGNED" != "1" ]]; then
  if [[ -z "$MACOS_SIGNING_IDENTITY" || -z "$MACOS_TEAM_ID" ]]; then
    echo "ERROR: MACOS_SIGNING_IDENTITY and MACOS_TEAM_ID are required for signed builds." >&2
    echo "Set ALLOW_UNSIGNED=1 to build unsigned artifacts." >&2
    exit 1
  fi
fi

case "$MACOS_ARCH" in
  arm64|x86_64)
    ;;
  *)
    echo "ERROR: Unsupported MACOS_ARCH: $MACOS_ARCH" >&2
    exit 1
    ;;
esac

mkdir -p "$DIST_DIR"
rm -rf "$APP_EXPORT_DIR" "$DAEMON_EXPORT_DIR"
rm -f \
  "$DIST_DIR/$APP_ZIP_NAME" \
  "$DIST_DIR/$DAEMON_ARCHIVE_NAME" \
  "$DIST_DIR/SHA256SUMS"

cp "$DESKTOP_TAURI_CONFIG" "$DESKTOP_METADATA_BACKUP_DIR/tauri.conf.json"
cp "$DESKTOP_CARGO_TOML" "$DESKTOP_METADATA_BACKUP_DIR/Cargo.toml"

restore_desktop_metadata() {
  cp "$DESKTOP_METADATA_BACKUP_DIR/tauri.conf.json" "$DESKTOP_TAURI_CONFIG"
  cp "$DESKTOP_METADATA_BACKUP_DIR/Cargo.toml" "$DESKTOP_CARGO_TOML"
  rm -rf "$DESKTOP_METADATA_BACKUP_DIR"
}

trap restore_desktop_metadata EXIT

apply_desktop_metadata() {
  python3 - "$DESKTOP_TAURI_CONFIG" "$DESKTOP_CARGO_TOML" "$MACOS_RELEASE_VERSION" "$MACOS_BUILD_NUMBER" <<'PY'
import json
import pathlib
import re
import sys

tauri_path = pathlib.Path(sys.argv[1])
cargo_path = pathlib.Path(sys.argv[2])
version = sys.argv[3]
build_number = sys.argv[4]

config = json.loads(tauri_path.read_text())
config["version"] = version
bundle = config.setdefault("bundle", {})
macos = bundle.setdefault("macOS", {})
macos["bundleVersion"] = build_number
tauri_path.write_text(json.dumps(config, indent=2) + "\n")

cargo = cargo_path.read_text()
cargo, count = re.subn(r'(?m)^version = "[^"]+"$', f'version = "{version}"', cargo, count=1)
if count != 1:
    raise SystemExit("failed to update desktop Cargo.toml version")
cargo_path.write_text(cargo)
PY
}

codesign_if_needed() {
  local target_path="$1"

  if [[ "$ALLOW_UNSIGNED" == "1" ]]; then
    return
  fi

  codesign \
    --force \
    --timestamp \
    --options runtime \
    --sign "$MACOS_SIGNING_IDENTITY" \
    "$target_path"
}

codesign_app_if_needed() {
  local app_path="$1"

  if [[ "$ALLOW_UNSIGNED" == "1" ]]; then
    return
  fi

  codesign \
    --force \
    --deep \
    --timestamp \
    --options runtime \
    --sign "$MACOS_SIGNING_IDENTITY" \
    "$app_path"
}

echo "==> Building release daemon"
pushd "$DAEMON_DIR" >/dev/null
cargo build -p daemon-bin --release
popd >/dev/null

DAEMON_BIN="$DAEMON_DIR/target/release/unbound-daemon"
if [[ ! -x "$DAEMON_BIN" ]]; then
  echo "ERROR: Expected daemon binary at $DAEMON_BIN" >&2
  exit 1
fi

echo "==> Building Tauri desktop app"
apply_desktop_metadata
pushd "$DESKTOP_DIR" >/dev/null
pnpm tauri:build
popd >/dev/null

BUILT_APP_PATH="$(find "$DESKTOP_DIR/src-tauri/target/release/bundle" -maxdepth 4 -name '*.app' -print -quit)"
if [[ -z "$BUILT_APP_PATH" ]]; then
  echo "ERROR: Could not find built Tauri app bundle under apps/desktop/src-tauri/target/release/bundle" >&2
  exit 1
fi

APP_PATH="$APP_EXPORT_DIR/$(basename "$BUILT_APP_PATH")"
DAEMON_PATH="$DAEMON_EXPORT_DIR/unbound-daemon"

mkdir -p "$APP_EXPORT_DIR" "$DAEMON_EXPORT_DIR"
ditto "$BUILT_APP_PATH" "$APP_PATH"
cp -f "$DAEMON_BIN" "$DAEMON_PATH"
chmod +x "$DAEMON_PATH"

if [[ -e "$APP_PATH/Contents/MacOS/unbound-daemon" ]]; then
  echo "ERROR: Desktop app bundle unexpectedly contains unbound-daemon." >&2
  exit 1
fi

codesign_app_if_needed "$APP_PATH"
codesign_if_needed "$DAEMON_PATH"

if [[ "$ALLOW_UNSIGNED" != "1" ]]; then
  codesign --verify --deep --strict "$APP_PATH"
  codesign --verify --strict "$DAEMON_PATH"
fi

echo "==> Packaging desktop app"
ditto -c -k --keepParent "$APP_PATH" "$DIST_DIR/$APP_ZIP_NAME"

echo "==> Packaging daemon"
ditto -c -k --keepParent "$DAEMON_PATH" "$DIST_DIR/$DAEMON_ARCHIVE_NAME"

pushd "$DIST_DIR" >/dev/null
shasum -a 256 "$APP_ZIP_NAME" "$DAEMON_ARCHIVE_NAME" > SHA256SUMS
popd >/dev/null

echo ""
echo "Release artifacts created in $DIST_DIR"
ls -la "$DIST_DIR"

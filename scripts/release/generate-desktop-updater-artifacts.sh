#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_PATH="${1:-}"
DIST_DIR="${2:-$ROOT_DIR/dist/macos}"
VERSION="${3:-}"
RELEASE_TAG="${4:-}"

if [[ -z "$APP_PATH" || -z "$VERSION" ]]; then
  echo "Usage: $0 <app-path> <dist-dir> <version> [release-tag]" >&2
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "ERROR: Expected app bundle directory at $APP_PATH" >&2
  exit 1
fi

if [[ -z "${RELEASE_TAG}" ]]; then
  RELEASE_TAG="v${VERSION}"
fi

UPDATER_ARCHIVE_NAME="${UPDATER_ARCHIVE_NAME:-unbound-desktop-macos-apple-silicon-updater.tar.gz}"
UPDATER_METADATA_NAME="${UPDATER_METADATA_NAME:-latest.json}"
UPDATER_TARGET="${TAURI_UPDATER_TARGET:-darwin-aarch64}"
UPDATER_REPOSITORY="${TAURI_UPDATER_REPOSITORY:-imbhargav5/unbound.computer}"
UPDATER_BASE_URL="${UNBOUND_DESKTOP_UPDATER_ASSET_BASE_URL:-https://github.com/${UPDATER_REPOSITORY}/releases/download/${RELEASE_TAG}}"

if [[ -z "${TAURI_UPDATER_PUBLIC_KEY:-}" || -z "${TAURI_SIGNING_PRIVATE_KEY:-}" ]]; then
  echo "WARNING: Skipping desktop updater artifact generation because TAURI_UPDATER_PUBLIC_KEY or TAURI_SIGNING_PRIVATE_KEY is missing." >&2
  exit 0
fi

mkdir -p "$DIST_DIR"

UPDATER_ARCHIVE_PATH="$DIST_DIR/$UPDATER_ARCHIVE_NAME"
UPDATER_SIGNATURE_PATH="${UPDATER_ARCHIVE_PATH}.sig"
UPDATER_METADATA_PATH="$DIST_DIR/$UPDATER_METADATA_NAME"

rm -f "$UPDATER_ARCHIVE_PATH" "$UPDATER_SIGNATURE_PATH" "$UPDATER_METADATA_PATH"

tar -czf "$UPDATER_ARCHIVE_PATH" -C "$(dirname "$APP_PATH")" "$(basename "$APP_PATH")"

pushd "$ROOT_DIR/apps/desktop" >/dev/null
sign_args=(tauri signer sign -k "$TAURI_SIGNING_PRIVATE_KEY")
if [[ -n "${TAURI_SIGNING_PRIVATE_KEY_PASSWORD:-}" ]]; then
  sign_args+=(-p "$TAURI_SIGNING_PRIVATE_KEY_PASSWORD")
fi
sign_args+=("$UPDATER_ARCHIVE_PATH")
pnpm "${sign_args[@]}"
popd >/dev/null

if [[ ! -f "$UPDATER_SIGNATURE_PATH" ]]; then
  echo "ERROR: Expected updater signature at $UPDATER_SIGNATURE_PATH" >&2
  exit 1
fi

UPDATER_SIGNATURE="$(tr -d '\r\n' < "$UPDATER_SIGNATURE_PATH")"
UPDATER_DOWNLOAD_URL="${UPDATER_BASE_URL}/$(basename "$UPDATER_ARCHIVE_PATH")"
PUBLISHED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

python3 - "$UPDATER_METADATA_PATH" "$VERSION" "$PUBLISHED_AT" "$UPDATER_TARGET" "$UPDATER_DOWNLOAD_URL" "$UPDATER_SIGNATURE" <<'PY'
import json
import pathlib
import sys

metadata_path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
published_at = sys.argv[3]
target = sys.argv[4]
download_url = sys.argv[5]
signature = sys.argv[6]

payload = {
    "version": version,
    "pub_date": published_at,
    "platforms": {
        target: {
            "url": download_url,
            "signature": signature,
        }
    },
}

metadata_path.write_text(json.dumps(payload, indent=2) + "\n")
PY

echo "Desktop updater artifacts created:"
echo "  $UPDATER_ARCHIVE_PATH"
echo "  $UPDATER_SIGNATURE_PATH"
echo "  $UPDATER_METADATA_PATH"

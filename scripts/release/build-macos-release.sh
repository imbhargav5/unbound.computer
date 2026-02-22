#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

PROJECT_DIR="$ROOT_DIR/apps/macos"
PROJECT_FILE="$PROJECT_DIR/unbound-macos.xcodeproj"
SCHEME="unbound-macos"
DIST_DIR="$ROOT_DIR/dist/macos"
RELEASE_XCCONFIG="${RELEASE_XCCONFIG:-$PROJECT_DIR/Config/Release.xcconfig}"

MACOS_RELEASE_VERSION="${MACOS_RELEASE_VERSION:-}"
MACOS_BUILD_NUMBER="${MACOS_BUILD_NUMBER:-${CURRENT_PROJECT_VERSION:-}}"
MACOS_SIGNING_IDENTITY="${MACOS_SIGNING_IDENTITY:-}"
MACOS_TEAM_ID="${MACOS_TEAM_ID:-}"
MACOS_CODE_SIGN_STYLE="${MACOS_CODE_SIGN_STYLE:-Manual}"
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

mkdir -p "$DIST_DIR"

EXPORT_OPTIONS_PLIST="$(mktemp -t unbound-macos-export-options.XXXXXX.plist)"
trap 'rm -f "$EXPORT_OPTIONS_PLIST"' EXIT

XCCONFIG_ARGS=()
if [[ -f "$RELEASE_XCCONFIG" ]]; then
  XCCONFIG_ARGS=(-xcconfig "$RELEASE_XCCONFIG")
fi

if [[ "$ALLOW_UNSIGNED" == "1" ]]; then
  cat > "$EXPORT_OPTIONS_PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>development</string>
</dict>
</plist>
PLIST
else
  cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>teamID</key>
  <string>${MACOS_TEAM_ID}</string>
  <key>signingCertificate</key>
  <string>${MACOS_SIGNING_IDENTITY}</string>
</dict>
</plist>
PLIST
fi

build_and_export() {
  local arch="$1"
  local archive_path="$DIST_DIR/unbound-macos-${arch}.xcarchive"
  local export_path="$DIST_DIR/export-${arch}"

  rm -rf "$archive_path" "$export_path"

  echo "==> Archiving (${arch})"
  xcodebuild archive \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$archive_path" \
    ${XCCONFIG_ARGS[@]+"${XCCONFIG_ARGS[@]}"} \
    ARCHS="$arch" \
    ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="$MACOS_RELEASE_VERSION" \
    CURRENT_PROJECT_VERSION="$MACOS_BUILD_NUMBER" \
    RELEASE_VERSION="$MACOS_RELEASE_VERSION" \
    RELEASE_BUILD_NUMBER="$MACOS_BUILD_NUMBER" \
    ${MACOS_TEAM_ID:+DEVELOPMENT_TEAM="$MACOS_TEAM_ID"} \
    ${MACOS_SIGNING_IDENTITY:+CODE_SIGN_IDENTITY="$MACOS_SIGNING_IDENTITY"} \
    ${MACOS_SIGNING_IDENTITY:+CODE_SIGN_STYLE="$MACOS_CODE_SIGN_STYLE"} \
    ${ALLOW_UNSIGNED:+CODE_SIGNING_ALLOWED=$( [[ "$ALLOW_UNSIGNED" == "1" ]] && echo NO || echo YES )}

  echo "==> Exporting (${arch})"
  xcodebuild -exportArchive \
    -archivePath "$archive_path" \
    -exportPath "$export_path" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

  local app_path
  app_path="$(find "$export_path" -maxdepth 1 -name "*.app" -print -quit)"
  if [[ -z "$app_path" ]]; then
    echo "ERROR: Expected .app in $export_path" >&2
    exit 1
  fi

  local zip_name="unbound-macos-v${MACOS_RELEASE_VERSION}-${arch}.zip"
  local zip_path="$DIST_DIR/$zip_name"
  echo "==> Zipping (${arch}) -> $zip_name"
  ditto -c -k --keepParent "$app_path" "$zip_path"
}

build_and_export arm64
build_and_export x86_64

pushd "$DIST_DIR" >/dev/null
shasum -a 256 unbound-macos-v${MACOS_RELEASE_VERSION}-arm64.zip unbound-macos-v${MACOS_RELEASE_VERSION}-x86_64.zip > SHA256SUMS
popd >/dev/null

echo ""
echo "Release artifacts created in $DIST_DIR"
ls -la "$DIST_DIR"

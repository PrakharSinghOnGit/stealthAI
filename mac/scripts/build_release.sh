#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/stealthAI.xcodeproj"
SCHEME="stealthAI"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/stealthAI.app"
ZIP_PATH="$DIST_DIR/stealthAI-macos.zip"

rm -rf "$DERIVED_DATA_PATH" "$DIST_DIR"
mkdir -p "$DIST_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but app bundle was not found at: $APP_PATH" >&2
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Created release artifact: $ZIP_PATH"

if [[ -f "$ROOT_DIR/scripts/unzip_and_run.sh" ]]; then
  cp "$ROOT_DIR/scripts/unzip_and_run.sh" "$DIST_DIR/"
  echo "Copied unzip_and_run.sh to $DIST_DIR"
else
  echo "Warning: unzip_and_run.sh not found in the current directory. Please ensure it is included in the scripts directory." >&2
fi
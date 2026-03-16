#!/bin/bash
# Script to bundle whisper-cli into the macOS app after building
# Run: bash scripts/bundle_whisper.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
WHISPER_CLI="$PROJECT_DIR/native/whisper.cpp/build/bin/whisper-cli"
APP_DIR="$PROJECT_DIR/build/macos/Build/Products/Debug/voice_ink.app"

if [ ! -f "$WHISPER_CLI" ]; then
  echo "Error: whisper-cli not found. Build whisper.cpp first."
  exit 1
fi

if [ ! -d "$APP_DIR" ]; then
  echo "Error: App not found. Run: flutter build macos --debug"
  exit 1
fi

cp "$WHISPER_CLI" "$APP_DIR/Contents/Resources/whisper-cli"
chmod +x "$APP_DIR/Contents/Resources/whisper-cli"
echo "✓ whisper-cli bundled into app"

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$(find "$SCRIPT_DIR" -maxdepth 1 -name '*.app' -print -quit)"
APP_NAME="$(basename "$APP_PATH")"
TARGET="$HOME/Applications/$APP_NAME"

if [[ -d "$TARGET" ]]; then
  osascript -e "tell application \"Finder\" to delete POSIX file \"$TARGET\""
fi

osascript -e "display notification \"The app was moved to the Trash. Your vocabulary CSV was kept.\" with title \"${APP_NAME%.app}\""

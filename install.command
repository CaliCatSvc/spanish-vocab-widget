#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$(find "$SCRIPT_DIR" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  osascript -e 'display alert "Installer" message "The app was not found next to this installer."'
  exit 1
fi

APP_NAME="$(basename "$APP_PATH")"
DESTINATION="$HOME/Applications/$APP_NAME"
mkdir -p "$HOME/Applications"
ditto "$APP_PATH" "$DESTINATION"
open "$DESTINATION"
osascript -e "display notification \"Installed in your Applications folder\" with title \"${APP_NAME%.app}\""

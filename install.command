#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$(find "$SCRIPT_DIR" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  osascript -e 'display alert "Installer" message "The app was not found next to this installer."'
  exit 1
fi

APP_NAME="$(basename "$APP_PATH")"
APP_TITLE="${APP_NAME%.app}"
EXECUTABLE_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP_PATH/Contents/Info.plist")"
DESTINATION="$HOME/Applications/$APP_NAME"

if ! osascript -e "display dialog \"Spanish Vocab Widget is 30-day shareware. After the evaluation period, continued use requires a paid personal license. By installing, you agree to the included license and shareware terms.\" with title \"$APP_TITLE\" buttons {\"Cancel\", \"Agree and Install\"} default button \"Agree and Install\" cancel button \"Cancel\"" >/dev/null; then
  exit 0
fi

mkdir -p "$HOME/Applications"

osascript -e "tell application \"$APP_TITLE\" to quit" 2>/dev/null || true
for attempt in 1 2 3 4 5; do
  if ! pgrep -x "$EXECUTABLE_NAME" >/dev/null 2>&1; then break; fi
  sleep 0.2
done

if [[ -d "$DESTINATION" ]]; then
  rm -rf "$DESTINATION"
fi

ditto "$APP_PATH" "$DESTINATION"
open "$DESTINATION"
osascript -e "display notification \"The old app was replaced. Your vocabulary and settings were kept.\" with title \"$APP_TITLE\""

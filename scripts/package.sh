#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${1:-Spanish Vocab Widget}"
ZIP_NAME="${2:-Spanish_Vocab_Widget_for_Mac.zip}"
OUTPUT_DIR="${3:-$ROOT_DIR/dist}"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp -R "$OUTPUT_DIR/$APP_NAME.app" "$STAGE_DIR/"
cp "$ROOT_DIR/install.command" "$STAGE_DIR/Install $APP_NAME.command"
cp "$ROOT_DIR/uninstall.command" "$STAGE_DIR/Uninstall $APP_NAME.command"
cp "$ROOT_DIR/Example Vocabulary.csv" "$STAGE_DIR/"
cp "$ROOT_DIR/LICENSE" "$STAGE_DIR/License.txt"
cp "$ROOT_DIR/PRIVACY.md" "$STAGE_DIR/Privacy.txt"
cp "$ROOT_DIR/SHAREWARE.md" "$STAGE_DIR/Shareware Terms.txt"
cp "$ROOT_DIR/HELP.md" "$STAGE_DIR/Adding More Vocabulary.txt"
chmod +x "$STAGE_DIR/Install $APP_NAME.command" "$STAGE_DIR/Uninstall $APP_NAME.command"

rm -f "$OUTPUT_DIR/$ZIP_NAME"
(cd "$STAGE_DIR" && zip -qry "$OUTPUT_DIR/$ZIP_NAME" .)
echo "$OUTPUT_DIR/$ZIP_NAME"

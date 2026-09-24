#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${1:-Spanish Vocab Widget}"
EXECUTABLE="${2:-SpanishVocabWidget}"
BUNDLE_ID="${3:-com.momalley.spanishvocabwidget}"
VOCABULARY_CSV="${4:-$ROOT_DIR/Resources/Vocabulary.csv}"
VOCABULARY_FOLDER="${5:-$APP_NAME}"
VERSION="${6:-1.0.0}"
BUILD_NUMBER="${7:-1}"
OUTPUT_DIR="${8:-$ROOT_DIR/dist}"
UPDATE_URL="${UPDATE_URL:-https://github.com/CaliCatSvc/spanish-vocab-widget/releases/latest}"
UPDATE_ASSET_NAME="${UPDATE_ASSET_NAME:-Spanish_Vocab_Widget_for_Mac.zip}"
AUTOMATIC_UPDATES_ENABLED="${AUTOMATIC_UPDATES_ENABLED:-true}"
CODE_ONLY_UPDATES="${CODE_ONLY_UPDATES:-false}"
PURCHASE_URL="${PURCHASE_URL:-https://paypal.me/calimoxo/9.99USD}"
SUPPORT_EMAIL="${SUPPORT_EMAIL:-spanishvocab@onda.aleeas.com}"
SHAREWARE_PRICE="${SHAREWARE_PRICE:-\$9.99 USD}"
TRIAL_DAYS="${TRIAL_DAYS:-30}"

APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"

rm -rf "$APP_PATH"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

clang -fobjc-arc -mmacosx-version-min=26.0 \
  -framework Cocoa -framework CoreGraphics -framework AVFoundation -framework UniformTypeIdentifiers \
  "$ROOT_DIR/Sources/SpanishVocabWidget.m" -o "$CONTENTS/MacOS/$EXECUTABLE"

cp "$VOCABULARY_CSV" "$CONTENTS/Resources/Vocabulary.csv"
cp "$ROOT_DIR/Resources/MexicanFlagIcon-1200.png" "$CONTENTS/Resources/MexicanFlagIcon-1200.png"
cp "$ROOT_DIR/LICENSE" "$CONTENTS/Resources/License.txt"
cp "$ROOT_DIR/PRIVACY.md" "$CONTENTS/Resources/Privacy.txt"
cp "$ROOT_DIR/SHAREWARE.md" "$CONTENTS/Resources/Shareware Terms.txt"
cp "$ROOT_DIR/HELP.md" "$CONTENTS/Resources/Adding More Vocabulary.txt"
sed \
  -e "s|__APP_NAME__|$APP_NAME|g" \
  -e "s|__EXECUTABLE__|$EXECUTABLE|g" \
  -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
  -e "s|__VOCABULARY_FOLDER__|$VOCABULARY_FOLDER|g" \
  -e "s|__VERSION__|$VERSION|g" \
  -e "s|__BUILD_NUMBER__|$BUILD_NUMBER|g" \
  -e "s|__UPDATE_URL__|$UPDATE_URL|g" \
  -e "s|__UPDATE_ASSET_NAME__|$UPDATE_ASSET_NAME|g" \
  -e "s|__AUTOMATIC_UPDATES_ENABLED__|$AUTOMATIC_UPDATES_ENABLED|g" \
  -e "s|__CODE_ONLY_UPDATES__|$CODE_ONLY_UPDATES|g" \
  -e "s|__PURCHASE_URL__|$PURCHASE_URL|g" \
  -e "s|__SUPPORT_EMAIL__|$SUPPORT_EMAIL|g" \
  -e "s|__SHAREWARE_PRICE__|$SHAREWARE_PRICE|g" \
  -e "s|__TRIAL_DAYS__|$TRIAL_DAYS|g" \
  "$ROOT_DIR/Info.plist.template" > "$CONTENTS/Info.plist"

codesign --force --deep --sign - "$APP_PATH"
echo "$APP_PATH"

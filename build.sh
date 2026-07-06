#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Diktier-Assistent"
EXECUTABLE_NAME="DiktierAssistent"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"

echo "Baue ${EXECUTABLE_NAME} (Release)…"
swift build -c release

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"

SIGN_IDENTITY="Diktier-Assistent Dev"
echo "Signiere App (${SIGN_IDENTITY})…"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo ""
echo "Fertig: $APP_BUNDLE"
echo "Zum dauerhaften Hintergrundbetrieb (Login-Item) am besten nach /Applications verschieben:"
echo "  cp -R \"$APP_BUNDLE\" /Applications/"
echo "Starten mit: open \"$APP_BUNDLE\""

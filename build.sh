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

# Ad-hoc-Signaturen sind bei jedem Build anders, deshalb fragt macOS nach jedem
# Neu-Build erneut nach Mikrofon-/Bedienungshilfen-Freigaben. Ein eigenes,
# selbstsigniertes Zertifikat gibt der App stattdessen eine stabile Identität -
# einmalig pro Rechner angelegt, danach für jeden weiteren Build wiederverwendet.
if ! security find-identity -v -p codesigning | grep -q "\"$SIGN_IDENTITY\""; then
  echo "Kein lokales Signatur-Zertifikat gefunden - lege »${SIGN_IDENTITY}« einmalig an…"
  CERT_DIR="$(mktemp -d)"
  trap 'rm -rf "$CERT_DIR"' EXIT
  P12_PASS="$(openssl rand -base64 24)"

  openssl req -x509 -newkey rsa:2048 -nodes -days 36500 \
    -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" \
    -subj "/CN=$SIGN_IDENTITY" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" \
    > /dev/null 2>&1

  # Ein leeres PKCS12-Passwort scheitert bei der Kombination aus Apples
  # "security import" und dem auf macOS mitgelieferten LibreSSL an einer
  # MAC-Verifikation - deshalb ein zufälliges, nur für diesen Import genutztes
  # Passwort statt eines leeren.
  openssl pkcs12 -export -out "$CERT_DIR/cert.p12" \
    -inkey "$CERT_DIR/key.pem" -in "$CERT_DIR/cert.pem" -passout "pass:$P12_PASS"

  security import "$CERT_DIR/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$P12_PASS" -T /usr/bin/codesign -T /usr/bin/security

  # Ohne diesen Trust-Eintrag lehnt codesign das selbstsignierte Zertifikat als
  # "no identity found" ab. macOS zeigt dafür einmalig eine Systemabfrage
  # (Passwort/Touch ID) - das ist normal und muss bestätigt werden.
  echo "Einmalige macOS-Sicherheitsabfrage: Bitte bestätigen, um dem Zertifikat für Code-Signierung zu vertrauen…"
  security add-trusted-cert -r trustRoot -p codeSign -k "$HOME/Library/Keychains/login.keychain-db" "$CERT_DIR/cert.pem"

  echo "Zertifikat angelegt und vertraut."
fi

echo "Signiere App (${SIGN_IDENTITY})…"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo ""
echo "Fertig: $APP_BUNDLE"
echo "Zum dauerhaften Hintergrundbetrieb (Login-Item) am besten nach /Applications verschieben:"
echo "  cp -R \"$APP_BUNDLE\" /Applications/"
echo "Starten mit: open \"$APP_BUNDLE\""

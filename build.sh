#!/usr/bin/env bash
#
# Build, sign, and bundle Sulfurcrest.app from the SwiftPM executable.
#
# Usage:
#   ./build.sh            # build + assemble + sign into ./build/Sulfurcrest.app
#   ./build.sh install    # also copy to /Applications
#   INSTALL=1 ./build.sh  # same as `install`
#
# Env:
#   SIGN_IDENTITY  Code-signing identity (default "Sulfurcrest Dev").
#                  Falls back to ad-hoc "-" if not found in the keychain.
#                  A stable identity keeps Accessibility/Mic grants across rebuilds.
#   HARDENED=1     Sign with the hardened runtime (needed for notarization).
#   BUILD_CONFIG   swift build configuration: release (default) or debug.
#                  Debug keeps an unoptimized binary for clearer crash reports.
#   INSTALL_DIR    Install location (default /Applications).
#
set -euo pipefail

APP_NAME="Sulfurcrest"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIGN_IDENTITY="${SIGN_IDENTITY:-Sulfurcrest Dev}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

cd "$PROJECT_DIR"

echo "==> swift build -c $BUILD_CONFIG"
swift build -c "$BUILD_CONFIG"
BIN_DIR="$(swift build -c "$BUILD_CONFIG" --show-bin-path)"
BIN_PATH="$BIN_DIR/$APP_NAME"

APP_BUNDLE="$PROJECT_DIR/build/$APP_NAME.app"
echo "==> assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Fall back to ad-hoc signing if the named identity is missing.
# (No `-v`: a self-signed dev cert is usable by codesign but isn't "trusted-valid".)
if [[ "$SIGN_IDENTITY" != "-" ]] && ! security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "!! Signing identity '$SIGN_IDENTITY' not found — using ad-hoc (-)."
    echo "   TCC grants (Accessibility/Mic) will reset on each rebuild."
    echo "   For stable grants, create a self-signed Code Signing certificate named"
    echo "   '$SIGN_IDENTITY' via Keychain Access > Certificate Assistant > Create a Certificate"
    echo "   (Identity Type: Self Signed Root, Certificate Type: Code Signing)."
    SIGN_IDENTITY="-"
fi

CODESIGN_ARGS=(--force --sign "$SIGN_IDENTITY" --entitlements "$PROJECT_DIR/Resources/$APP_NAME.entitlements")
if [[ "${HARDENED:-0}" == "1" ]]; then
    CODESIGN_ARGS+=(--options runtime)
fi

echo "==> codesign ($SIGN_IDENTITY${HARDENED:+, hardened})"
codesign "${CODESIGN_ARGS[@]}" "$APP_BUNDLE"
codesign --verify --verbose "$APP_BUNDLE" || true

if [[ "${1:-}" == "install" || "${INSTALL:-0}" == "1" ]]; then
    echo "==> installing to $INSTALL_DIR/$APP_NAME.app"
    rm -rf "${INSTALL_DIR:?}/$APP_NAME.app"
    cp -R "$APP_BUNDLE" "$INSTALL_DIR/"
    echo "Installed. Launch: open '$INSTALL_DIR/$APP_NAME.app'"
fi

echo "==> done: $APP_BUNDLE"

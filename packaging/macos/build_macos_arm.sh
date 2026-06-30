#!/usr/bin/env bash
#
# build_macos_arm.sh — Build a macOS Apple Silicon (arm64) .app for Notch.
#
# Produces:  dist/Notch.app   (and optionally dist/Notch-arm64.dmg)
#
# Requirements: macOS on Apple Silicon (or an arm64 Python toolchain),
#               Python 3.9+, and Xcode command line tools (for codesign/sips).
#
# Usage:
#   bash packaging/macos/build_macos_arm.sh            # build .app
#   MAKE_DMG=1 bash packaging/macos/build_macos_arm.sh # also build a .dmg
#
# Env overrides:
#   VOSK_MODEL_URL   Speech model zip to bundle (default: small en-us).
#   PYTHON           Python interpreter to use (default: python3).
#   MAKE_DMG         Set to 1 to also produce a DMG.
#
set -euo pipefail

# ── Locate repo root (two levels up from this script) ──────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

PYTHON="${PYTHON:-python3}"
APP_NAME="Notch"
BUNDLE_ID="ae.socia.notch"
VOSK_MODEL_URL="${VOSK_MODEL_URL:-https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip}"

echo "==> Notch macOS arm64 build"
echo "    repo: $REPO_ROOT"
echo "    arch: $(uname -m)"

# ── 1. Virtual environment + dependencies ──────────────────────────────
VENV_DIR="$REPO_ROOT/.venv-build"
"$PYTHON" -m venv "$VENV_DIR"
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip wheel
python -m pip install -r requirements.txt
python -m pip install "pyinstaller>=6.0"

# ── 2. Download the Vosk speech model (if not already present) ──────────
if [ ! -d "$REPO_ROOT/model" ] || [ ! -d "$REPO_ROOT/model/am" ]; then
    echo "==> Downloading Vosk speech model"
    TMP_ZIP="$(mktemp -t vosk-model.XXXXXX).zip"
    curl -fL "$VOSK_MODEL_URL" -o "$TMP_ZIP"
    UNZIP_DIR="$(mktemp -d -t vosk-model.XXXXXX)"
    unzip -q "$TMP_ZIP" -d "$UNZIP_DIR"
    # The zip extracts to a single top-level folder; move its contents to ./model
    INNER="$(find "$UNZIP_DIR" -maxdepth 1 -mindepth 1 -type d | head -n 1)"
    rm -rf "$REPO_ROOT/model"
    mv "$INNER" "$REPO_ROOT/model"
    rm -rf "$TMP_ZIP" "$UNZIP_DIR"
else
    echo "==> Reusing existing ./model"
fi

# ── 3. Build an .icns icon from the PNG (best effort) ───────────────────
ICON_ARG=()
SRC_PNG="$REPO_ROOT/assets/Notch_Clear_1.png"
if command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1 && [ -f "$SRC_PNG" ]; then
    echo "==> Generating app icon"
    ICONSET="$(mktemp -d)/Notch.iconset"
    mkdir -p "$ICONSET"
    for sz in 16 32 64 128 256 512; do
        sips -z "$sz" "$sz"     "$SRC_PNG" --out "$ICONSET/icon_${sz}x${sz}.png"     >/dev/null
        sips -z $((sz*2)) $((sz*2)) "$SRC_PNG" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
    done
    ICNS_PATH="$REPO_ROOT/build/Notch.icns"
    mkdir -p "$REPO_ROOT/build"
    iconutil -c icns "$ICONSET" -o "$ICNS_PATH"
    ICON_ARG=(--icon "$ICNS_PATH")
else
    echo "==> Skipping icon generation (sips/iconutil/PNG not available)"
fi

# ── 4. Run PyInstaller (arm64, windowed .app) ──────────────────────────
echo "==> Running PyInstaller"
rm -rf "$REPO_ROOT/dist/$APP_NAME.app"
pyinstaller \
    --noconfirm \
    --clean \
    --windowed \
    --name "$APP_NAME" \
    --target-arch arm64 \
    --osx-bundle-identifier "$BUNDLE_ID" \
    --collect-all vosk \
    --collect-all sounddevice \
    "${ICON_ARG[@]}" \
    main.py

APP_PATH="$REPO_ROOT/dist/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: $APP_PATH was not produced" >&2
    exit 1
fi

# ── 5. Place the speech model where the app expects it ─────────────────
# The app (frozen) looks for ./model next to the executable, i.e.
#   Notch.app/Contents/MacOS/model
echo "==> Bundling speech model into the .app"
rm -rf "$APP_PATH/Contents/MacOS/model"
cp -R "$REPO_ROOT/model" "$APP_PATH/Contents/MacOS/model"

# ── 6. Ad-hoc codesign (arm64 binaries must be signed to run) ──────────
if command -v codesign >/dev/null 2>&1; then
    echo "==> Ad-hoc codesigning"
    codesign --force --deep --sign - "$APP_PATH" || \
        echo "WARN: ad-hoc codesign failed; the app may need 'xattr -dr com.apple.quarantine'"
fi

echo "==> Built: $APP_PATH"

# ── 7. Optional DMG ────────────────────────────────────────────────────
if [ "${MAKE_DMG:-0}" = "1" ]; then
    echo "==> Creating DMG"
    DMG_PATH="$REPO_ROOT/dist/$APP_NAME-arm64.dmg"
    rm -f "$DMG_PATH"
    STAGE="$(mktemp -d)"
    cp -R "$APP_PATH" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG_PATH"
    rm -rf "$STAGE"
    echo "==> Built: $DMG_PATH"
fi

echo "==> Done."
echo "    To run an unsigned/un-notarized build, you may first need:"
echo "      xattr -dr com.apple.quarantine \"$APP_PATH\""

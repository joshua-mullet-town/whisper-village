#!/bin/bash
set -e

# Dev Build Script for Whisper Village
# Usage: ./scripts/dev.sh
# Builds Debug config, signs with local certificate, and launches the app

PROJECT_DIR="/Users/joshuamullet/code/whisper-village"
BUILD_DIR="$PROJECT_DIR/build/DerivedData"
APP_PATH="$BUILD_DIR/Build/Products/Debug/Whisper Village Dev.app"
SIGNING_IDENTITY="Whisper Village Signing"

echo "🛑 Killing existing Whisper Village Dev..."
pkill -f "Whisper Village Dev" 2>/dev/null || true
sleep 1

echo "🔨 Building Debug (bypassing Apple signing)..."
xcodebuild -scheme WhisperVillage \
    -project "$PROJECT_DIR/WhisperVillage.xcodeproj" \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tail -5

echo ""
echo "🔐 Re-signing with '$SIGNING_IDENTITY' certificate..."
codesign --deep --force --sign "$SIGNING_IDENTITY" "$APP_PATH"

echo "✅ Verifying signature..."
codesign -v "$APP_PATH" && echo "✅ Signature valid"

echo ""
echo "🚀 Launching Whisper Village Dev..."
open "$APP_PATH"

echo ""
echo "=================================="
echo "✅ Dev build ready!"

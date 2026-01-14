#!/bin/bash
set -e

# Ship It Script for Whisper Village
# Usage: ./scripts/ship-it.sh <version> "<release notes>"
# Example: ./scripts/ship-it.sh 1.8.6 "Bug fixes and improvements"

VERSION="$1"
NOTES="$2"

if [ -z "$VERSION" ] || [ -z "$NOTES" ]; then
    echo "Usage: ./scripts/ship-it.sh <version> \"<release notes>\""
    echo "Example: ./scripts/ship-it.sh 1.8.6 \"Bug fixes and improvements\""
    exit 1
fi

PROJECT_DIR="/Users/joshuamullet/code/whisper-village"
BUILD_DIR="$PROJECT_DIR/build/DerivedData"
APP_PATH="$BUILD_DIR/Build/Products/Release/Whisper Village.app"
DMG_PATH="$PROJECT_DIR/WhisperVillage-$VERSION.dmg"
SIGNING_IDENTITY="Whisper Village Signing"

# Sparkle tools location
SPARKLE_BIN="/Users/joshuamullet/Library/Developer/Xcode/DerivedData/VoiceInk-gqtdhjqfugpinvguwravwbwwibyw/SourcePackages/artifacts/sparkle/Sparkle/bin"

echo "🚀 Ship It Pipeline for v$VERSION"
echo "=================================="

# Step 1: Get current build number and increment
echo ""
echo "📝 Step 1: Reading current build number..."
CURRENT_BUILD=$(grep -A1 'CURRENT_PROJECT_VERSION' "$PROJECT_DIR/WhisperVillage.xcodeproj/project.pbxproj" | grep -o '[0-9]*' | head -1)
NEW_BUILD=$((CURRENT_BUILD + 1))
echo "   Current: $CURRENT_BUILD → New: $NEW_BUILD"

# Step 2: Update version in project.pbxproj
echo ""
echo "📝 Step 2: Updating version numbers..."
# This is tricky with sed on macOS, so we'll use perl
perl -i -pe "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PROJECT_DIR/WhisperVillage.xcodeproj/project.pbxproj"
perl -i -pe "s/MARKETING_VERSION = [0-9.]+;/MARKETING_VERSION = $VERSION;/g" "$PROJECT_DIR/WhisperVillage.xcodeproj/project.pbxproj"
echo "   Build: $NEW_BUILD, Marketing: $VERSION"

# Step 3: Build with ad-hoc signing
echo ""
echo "🔨 Step 3: Building Release (ad-hoc signing)..."
xcodebuild -scheme WhisperVillage \
    -project "$PROJECT_DIR/WhisperVillage.xcodeproj" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tail -5

# Step 4: Re-sign with self-signed certificate
echo ""
echo "🔐 Step 4: Re-signing with '$SIGNING_IDENTITY' certificate..."
codesign --deep --force --sign "$SIGNING_IDENTITY" "$APP_PATH"
echo "   ✅ Signed successfully"

# Verify signature
echo "   Verifying signature..."
codesign -v "$APP_PATH" && echo "   ✅ Signature valid"

# Step 5: Create DMG
echo ""
echo "📦 Step 5: Creating DMG..."
# Remove old DMG if exists
rm -f "$DMG_PATH"
create-dmg \
    --volname "Whisper Village" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "Whisper Village.app" 150 185 \
    --app-drop-link 450 185 \
    "$DMG_PATH" \
    "$APP_PATH"

# Get DMG size
DMG_SIZE=$(stat -f%z "$DMG_PATH")
echo "   DMG created: $DMG_PATH ($DMG_SIZE bytes)"

# Step 5.5: Sign DMG with EdDSA for Sparkle
echo ""
echo "🔑 Step 5.5: Signing DMG with EdDSA for Sparkle..."
# sign_update returns: sparkle:edSignature="..." length="..."
# We need to extract just the base64 signature value
SIGN_OUTPUT=$("$SPARKLE_BIN/sign_update" "$DMG_PATH" 2>&1)
EDDSA_SIG=$(echo "$SIGN_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | sed 's/sparkle:edSignature="//;s/"$//')
echo "   EdDSA signature: $EDDSA_SIG"

# Step 6: Create/Update GitHub Release
echo ""
echo "🐙 Step 6: Creating GitHub release v$VERSION..."
# Check if release exists
if gh release view "v$VERSION" &>/dev/null; then
    echo "   Release exists, updating asset..."
    gh release delete-asset "v$VERSION" "WhisperVillage-$VERSION.dmg" --yes 2>/dev/null || true
    gh release upload "v$VERSION" "$DMG_PATH"
else
    echo "   Creating new release..."
    gh release create "v$VERSION" \
        --title "Whisper Village v$VERSION" \
        --notes "$NOTES" \
        "$DMG_PATH"
fi
echo "   ✅ GitHub release ready"

# Step 7: Update appcast.xml with EdDSA signature
echo ""
echo "📡 Step 7: Updating appcast.xml with EdDSA signature..."
PUBDATE=$(date -R)
APPCAST_ENTRY="        <item>
            <title>$VERSION</title>
            <pubDate>$PUBDATE</pubDate>
            <sparkle:version>$NEW_BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <description><![CDATA[
                <h3>Version $VERSION</h3>
                <ul>
                    <li>$NOTES</li>
                </ul>
            ]]></description>
            <enclosure url=\"https://github.com/joshua-mullet-town/whisper-village/releases/download/v$VERSION/WhisperVillage-$VERSION.dmg\" length=\"$DMG_SIZE\" type=\"application/octet-stream\" sparkle:edSignature=\"$EDDSA_SIG\"/>
        </item>"

# Insert new item after <channel> tag (before first existing <item>)
# Using perl for reliable multi-line replacement
perl -i -0pe "s|(<channel>\s*<title>Whisper Village Releases</title>)|\\1\n$APPCAST_ENTRY|" "$PROJECT_DIR/appcast.xml"
echo "   ✅ appcast.xml updated with EdDSA signature"

# Step 8: Commit and push
echo ""
echo "📤 Step 8: Committing and pushing..."
cd "$PROJECT_DIR"
git add -A
git commit -m "Release v$VERSION: $NOTES

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push

echo ""
echo "=================================="
echo "🎉 v$VERSION shipped successfully!"
echo ""
echo "Users can update via:"
echo "  - Sparkle: Check for Updates in app"
echo "  - Manual: https://github.com/joshua-mullet-town/whisper-village/releases/tag/v$VERSION"
echo ""
echo "⚠️  First-time users need to run: xattr -cr /Applications/Whisper\\ Village.app"

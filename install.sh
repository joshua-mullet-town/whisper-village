#!/bin/bash
#
# Whisper Village Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/joshua-mullet-town/whisper-village/main/install.sh | bash
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Whisper Village Installer          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Get latest release info
echo -e "${YELLOW}→ Fetching latest release...${NC}"
LATEST_RELEASE=$(curl -s https://api.github.com/repos/joshua-mullet-town/whisper-village/releases/latest)
VERSION=$(echo "$LATEST_RELEASE" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
DMG_URL=$(echo "$LATEST_RELEASE" | grep '"browser_download_url".*\.dmg"' | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')

if [ -z "$VERSION" ] || [ -z "$DMG_URL" ]; then
    echo -e "${RED}✗ Could not fetch release info. Check your internet connection.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found ${VERSION}${NC}"

# Check if already installed
if [ -d "/Applications/Whisper Village.app" ]; then
    INSTALLED_VERSION=$(defaults read "/Applications/Whisper Village.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")
    echo -e "${YELLOW}→ Existing installation found: v${INSTALLED_VERSION}${NC}"

    # Quit if running
    if pgrep -f "Whisper Village" > /dev/null 2>&1; then
        echo -e "${YELLOW}→ Quitting Whisper Village...${NC}"
        pkill -f "Whisper Village" 2>/dev/null || true
        sleep 1
    fi
fi

# Download
TEMP_DIR=$(mktemp -d)
DMG_PATH="$TEMP_DIR/WhisperVillage.dmg"

echo -e "${YELLOW}→ Downloading ${VERSION}...${NC}"
curl -L --progress-bar -o "$DMG_PATH" "$DMG_URL"

# Mount DMG
echo -e "${YELLOW}→ Mounting disk image...${NC}"
MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse -quiet | grep "/Volumes" | awk '{print $3}')

if [ -z "$MOUNT_POINT" ]; then
    echo -e "${RED}✗ Failed to mount DMG${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Copy to Applications
echo -e "${YELLOW}→ Installing to /Applications...${NC}"
rm -rf "/Applications/Whisper Village.app" 2>/dev/null || true
cp -R "$MOUNT_POINT/Whisper Village.app" "/Applications/"

# Unmount
hdiutil detach "$MOUNT_POINT" -quiet

# Remove quarantine (THIS IS THE KEY STEP)
echo -e "${YELLOW}→ Removing quarantine flags...${NC}"
xattr -cr "/Applications/Whisper Village.app"

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     Installation Complete!             ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "Whisper Village ${VERSION} has been installed."
echo ""
echo -e "${YELLOW}IMPORTANT - First Launch Setup:${NC}"
echo -e "When you first open the app, you'll need to grant permissions:"
echo -e "  1. ${BLUE}Microphone${NC} - Required for voice recording"
echo -e "  2. ${BLUE}Accessibility${NC} - Required for hotkey detection"
echo -e "  3. ${BLUE}Screen Recording${NC} - Optional, for window detection"
echo ""
echo -e "${YELLOW}If permissions don't apply:${NC}"
echo -e "  • Go to System Settings → Privacy & Security"
echo -e "  • Remove Whisper Village from the list"
echo -e "  • Restart the app and re-grant permissions"
echo ""

# Ask to launch
read -p "Launch Whisper Village now? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    echo -e "${YELLOW}→ Launching Whisper Village...${NC}"
    open "/Applications/Whisper Village.app"
fi

echo -e "${GREEN}Done!${NC}"

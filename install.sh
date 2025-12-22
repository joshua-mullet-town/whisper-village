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
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m' # No Color

clear
echo ""
echo -e "${MAGENTA}  ╦ ╦┬ ┬┬┌─┐┌─┐┌─┐┬─┐  ╦  ╦┬┬  ┬  ┌─┐┌─┐┌─┐${NC}"
echo -e "${MAGENTA}  ║║║├─┤│└─┐├─┘├┤ ├┬┘  ╚╗╔╝││  │  ├─┤│ ┬├┤ ${NC}"
echo -e "${MAGENTA}  ╚╩╝┴ ┴┴└─┘┴  └─┘┴└─   ╚╝ ┴┴─┘┴─┘┴ ┴└─┘└─┘${NC}"
echo ""
echo -e "  ${CYAN}Talk to your Mac. It finally listens.${NC}"
echo ""
sleep 0.5

# Get latest release info
echo -e "${DIM}  Checking for the latest version...${NC}"
LATEST_RELEASE=$(curl -s https://api.github.com/repos/joshua-mullet-town/whisper-village/releases/latest)
VERSION=$(echo "$LATEST_RELEASE" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
DMG_URL=$(echo "$LATEST_RELEASE" | grep '"browser_download_url".*\.dmg"' | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')

if [ -z "$VERSION" ] || [ -z "$DMG_URL" ]; then
    echo -e "  ${RED}Hmm, couldn't reach GitHub. Check your internet?${NC}"
    exit 1
fi

echo -e "  ${GREEN}✓${NC} Found ${CYAN}${VERSION}${NC}"
echo ""

# Check if already installed
if [ -d "/Applications/Whisper Village.app" ]; then
    INSTALLED_VERSION=$(defaults read "/Applications/Whisper Village.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")
    echo -e "  ${DIM}Upgrading from v${INSTALLED_VERSION}...${NC}"

    # Quit if running
    if pgrep -x "Whisper Village" > /dev/null 2>&1; then
        echo -e "  ${DIM}Closing the running app...${NC}"
        pkill -x "Whisper Village" 2>/dev/null || true
        sleep 1
    fi
fi

# Download
TEMP_DIR=$(mktemp -d)
DMG_PATH="$TEMP_DIR/WhisperVillage.dmg"

echo -e "  ${DIM}Downloading...${NC}"
curl -L --progress-bar -o "$DMG_PATH" "$DMG_URL"

# Mount DMG
echo -e "  ${DIM}Unpacking...${NC}"
MOUNT_OUTPUT=$(hdiutil attach "$DMG_PATH" -nobrowse 2>&1)
MOUNT_RESULT=$?

if [ $MOUNT_RESULT -ne 0 ]; then
    echo -e "  ${RED}Something went wrong unpacking. Try again?${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep "/Volumes/" | sed 's/.*\(\/Volumes\/.*\)/\1/' | head -1)

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    echo -e "  ${RED}Couldn't find the app. Weird. Try again?${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Copy to Applications
echo -e "  ${DIM}Installing...${NC}"
rm -rf "/Applications/Whisper Village.app" 2>/dev/null || true
cp -R "$MOUNT_POINT/Whisper Village.app" "/Applications/"

# Unmount
hdiutil detach "$MOUNT_POINT" -quiet

# Remove quarantine (THE KEY STEP - makes it "just work")
xattr -cr "/Applications/Whisper Village.app"

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo -e "  ${GREEN}✓${NC} ${GREEN}You're all set!${NC}"
echo ""
echo -e "  ${CYAN}Whisper Village ${VERSION}${NC} is ready in your Applications folder."
echo ""
echo -e "  ${DIM}The app will guide you through setup when you open it.${NC}"
echo ""

# Ask to launch
if [ -t 0 ]; then
    read -p "  Launch it now? [Y/n] " -n 1 -r
    echo
else
    read -p "  Launch it now? [Y/n] " -n 1 -r < /dev/tty
    echo
fi

if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
    echo ""
    echo -e "  ${MAGENTA}Opening Whisper Village...${NC}"
    echo -e "  ${DIM}Happy talking! 🎙${NC}"
    open "/Applications/Whisper Village.app"
else
    echo ""
    echo -e "  ${DIM}Whenever you're ready, find it in Applications.${NC}"
fi

echo ""

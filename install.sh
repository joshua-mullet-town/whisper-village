#!/bin/bash
#
# Whisper Village Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/joshua-mullet-town/whisper-village/main/install.sh | bash
#

# Exit on error, but we'll handle errors gracefully
set -e

# ═══════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════
WIDTH=50  # Max width for visual elements

# Colors - using printf to ensure escape codes work when piped
RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[1;33m')
BLUE=$(printf '\033[0;34m')
MAGENTA=$(printf '\033[0;35m')
CYAN=$(printf '\033[0;36m')
WHITE=$(printf '\033[1;37m')
DIM=$(printf '\033[2m')
BOLD=$(printf '\033[1m')
NC=$(printf '\033[0m')

# Fun taglines
TAGLINES=(
    "Your keyboard is about to get jealous."
    "Dictation, but make it private."
    "Talk to your Mac. It finally listens."
    "Type less. Say more."
    "Your voice, your rules."
)
TAGLINE="${TAGLINES[$RANDOM % ${#TAGLINES[@]}]}"

# Fun waiting messages for download
WAIT_MESSAGES=(
    "Wrangling some bits..."
    "Convincing electrons to cooperate..."
    "Downloading pure magic..."
    "Almost there, promise..."
    "Good things come to those who wait..."
    "Making it snappy..."
    "Fetching the goods..."
)

# ═══════════════════════════════════════════════════════════════
# Helper Functions
# ═══════════════════════════════════════════════════════════════

# Print centered text
center() {
    local text="$1"
    local len=${#text}
    local padding=$(( (WIDTH - len) / 2 ))
    printf "%*s%s\n" $padding "" "$text"
}

# Print a horizontal line
line() {
    printf "  ${DIM}"
    printf '─%.0s' $(seq 1 $WIDTH)
    printf "${NC}\n"
}

# Animated progress bar
progress_bar() {
    local current=$1
    local total=$2
    local width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r  ${CYAN}["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "]${NC} ${WHITE}%3d%%${NC}" $percent
}

# Spinner with changing messages
spinner_download() {
    local pid=$1
    local frames=("◜" "◠" "◝" "◞" "◡" "◟")
    local i=0
    local msg_i=0
    local counter=0

    while kill -0 "$pid" 2>/dev/null; do
        local msg="${WAIT_MESSAGES[$msg_i]}"
        printf "\r  ${CYAN}${frames[$i]}${NC} ${DIM}%s${NC}          " "$msg"
        i=$(( (i + 1) % 6 ))
        counter=$((counter + 1))
        # Change message every ~3 seconds
        if [ $((counter % 30)) -eq 0 ]; then
            msg_i=$(( (msg_i + 1) % ${#WAIT_MESSAGES[@]} ))
        fi
        sleep 0.1
    done
    printf "\r%50s\r"
}

# Simple spinner
spinner() {
    local pid=$1
    local msg=$2
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${frames[$i]}${NC} %s" "$msg"
        i=$(( (i + 1) % 10 ))
        sleep 0.08
    done
    printf "\r"
}

# Success message
success() {
    printf "  ${GREEN}✓${NC} %s\n" "$1"
}

# Error message
error() {
    printf "  ${RED}✗${NC} %s\n" "$1"
}

# Warning message
warn() {
    printf "  ${YELLOW}!${NC} %s\n" "$1"
}

# ═══════════════════════════════════════════════════════════════
# Main Script
# ═══════════════════════════════════════════════════════════════

clear
echo ""

# Header
printf "${MAGENTA}${BOLD}\n"
cat << 'EOF'
        ╦ ╦┬ ┬┬┌─┐┌─┐┌─┐┬─┐
        ║║║├─┤│└─┐├─┘├┤ ├┬┘
        ╚╩╝┴ ┴┴└─┘┴  └─┘┴└─
           ╦  ╦┬┬  ┬  ┌─┐┌─┐┌─┐
           ╚╗╔╝││  │  ├─┤│ ┬├┤
            ╚╝ ┴┴─┘┴─┘┴ ┴└─┘└─┘
EOF
printf "${NC}\n"

# Tagline
printf "       ${CYAN}${TAGLINE}${NC}\n"
echo ""
sleep 0.3

# Feature box
printf "  ${DIM}╭──────────────────────────────────────────────╮${NC}\n"
printf "  ${DIM}│${NC}                                              ${DIM}│${NC}\n"
printf "  ${DIM}│${NC}   ${WHITE}✨ What you're getting:${NC}                    ${DIM}│${NC}\n"
printf "  ${DIM}│${NC}                                              ${DIM}│${NC}\n"
printf "  ${DIM}│${NC}      ${GREEN}◆${NC} Voice-to-text that actually works    ${DIM}│${NC}\n"
printf "  ${DIM}│${NC}      ${GREEN}◆${NC} 100%% private — runs on your Mac      ${DIM}│${NC}\n"
printf "  ${DIM}│${NC}      ${GREEN}◆${NC} Works in any app, anywhere           ${DIM}│${NC}\n"
printf "  ${DIM}│${NC}                                              ${DIM}│${NC}\n"
printf "  ${DIM}╰──────────────────────────────────────────────╯${NC}\n"
echo ""
sleep 0.3

# ─────────────────────────────────────────
# Step 1: Find latest version
# ─────────────────────────────────────────
line
printf "  ${WHITE}${BOLD}STEP 1${NC}  ${DIM}Finding the latest version${NC}\n"
line
echo ""

printf "  ${CYAN}◐${NC} Checking GitHub..."

LATEST_RELEASE=$(curl -s https://api.github.com/repos/joshua-mullet-town/whisper-village/releases/latest)
VERSION=$(echo "$LATEST_RELEASE" | grep '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
DMG_URL=$(echo "$LATEST_RELEASE" | grep '"browser_download_url".*\.dmg"' | sed -E 's/.*"browser_download_url": *"([^"]+)".*/\1/')

if [ -z "$VERSION" ] || [ -z "$DMG_URL" ]; then
    printf "\r"
    error "Couldn't reach GitHub. Check your connection?"
    exit 1
fi

printf "\r"
success "Found ${CYAN}${VERSION}${NC} — let's go!"
echo ""

# ─────────────────────────────────────────
# Handle existing installation
# ─────────────────────────────────────────
if [ -d "/Applications/Whisper Village.app" ]; then
    INSTALLED_VERSION=$(defaults read "/Applications/Whisper Village.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")
    printf "  ${DIM}Upgrading from v${INSTALLED_VERSION} → ${VERSION}${NC}\n"
    echo ""

    # Quit if running
    if pgrep -x "Whisper Village" > /dev/null 2>&1; then
        printf "  ${CYAN}◐${NC} Closing the app..."
        pkill -x "Whisper Village" 2>/dev/null || true
        sleep 2
        printf "\r"
        success "App closed"
    fi

    # Try to remove the old version
    printf "  ${CYAN}◐${NC} Removing old version..."
    chmod -R u+w "/Applications/Whisper Village.app" 2>/dev/null || true
    if rm -rf "/Applications/Whisper Village.app" 2>/dev/null; then
        printf "\r"
        success "Old version removed"
    else
        printf "\r"
        # Check if it still exists
        if [ -d "/Applications/Whisper Village.app" ]; then
            echo ""
            warn "Couldn't remove the old version automatically."
            echo ""
            printf "  ${WHITE}No worries! Just run this first:${NC}\n"
            echo ""
            printf "  ${CYAN}sudo rm -rf \"/Applications/Whisper Village.app\"${NC}\n"
            echo ""
            printf "  ${DIM}Then run the installer again.${NC}\n"
            echo ""
            exit 1
        fi
    fi
    echo ""
fi

# ─────────────────────────────────────────
# Step 2: Download
# ─────────────────────────────────────────
line
printf "  ${WHITE}${BOLD}STEP 2${NC}  ${DIM}Downloading the goods${NC}\n"
line
echo ""
printf "  ${DIM}📦 Size: ~250 MB • Your patience is appreciated${NC}\n"
echo ""

TEMP_DIR=$(mktemp -d)
DMG_PATH="$TEMP_DIR/WhisperVillage.dmg"

# Start download in background
curl -L -s -o "$DMG_PATH" "$DMG_URL" &
CURL_PID=$!

# Show spinner with fun messages while downloading
spinner_download $CURL_PID

# Wait for curl to finish
wait $CURL_PID
CURL_RESULT=$?

if [ $CURL_RESULT -ne 0 ]; then
    error "Download hiccup! Check your internet and try again."
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo ""
success "Download complete! ${DIM}That wasn't so bad, was it?${NC}"
echo ""

# ─────────────────────────────────────────
# Step 3: Install
# ─────────────────────────────────────────
line
printf "  ${WHITE}${BOLD}STEP 3${NC}  ${DIM}Installing to Applications${NC}\n"
line
echo ""

printf "  ${CYAN}◐${NC} Unpacking the magic..."

# Mount DMG
hdiutil attach "$DMG_PATH" -nobrowse -quiet 2>/dev/null

# Find mount point
MOUNT_POINT=$(ls -d /Volumes/Whisper\ Village* 2>/dev/null | head -1)

if [ -z "$MOUNT_POINT" ] || [ ! -d "$MOUNT_POINT" ]; then
    printf "\r"
    error "Couldn't mount the installer. Try again?"
    rm -rf "$TEMP_DIR"
    exit 1
fi

printf "\r"
success "Unpacked!"

printf "  ${CYAN}◐${NC} Moving to Applications..."

# Copy to Applications
if ! cp -R "$MOUNT_POINT/Whisper Village.app" "/Applications/" 2>/dev/null; then
    printf "\r"

    # Unmount before showing error
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
    rm -rf "$TEMP_DIR"

    echo ""
    warn "Couldn't install to Applications."
    echo ""
    printf "  ${WHITE}Quick fix — run this command:${NC}\n"
    echo ""
    printf "  ${CYAN}sudo rm -rf \"/Applications/Whisper Village.app\"${NC}\n"
    echo ""
    printf "  ${DIM}Then run the installer again. Easy peasy!${NC}\n"
    echo ""
    exit 1
fi

# Unmount
hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true

# Remove quarantine (so macOS doesn't complain)
xattr -cr "/Applications/Whisper Village.app" 2>/dev/null || true

# Cleanup temp files
rm -rf "$TEMP_DIR"

printf "\r"
success "Installed to ${CYAN}/Applications${NC}"
echo ""

# ─────────────────────────────────────────
# Done!
# ─────────────────────────────────────────
line
echo ""

# Celebration animation
for i in 1 2 3; do
    printf "\r  ${GREEN}${BOLD}✨ ✨ ✨${NC}"
    sleep 0.15
    printf "\r  ${MAGENTA}${BOLD}🎉 🎉 🎉${NC}"
    sleep 0.15
done
printf "\r              \r"

printf "  ${GREEN}${BOLD}╔════════════════════════════════════════════╗${NC}\n"
printf "  ${GREEN}${BOLD}║                                            ║${NC}\n"
printf "  ${GREEN}${BOLD}║         ✨  You're all set!  ✨            ║${NC}\n"
printf "  ${GREEN}${BOLD}║                                            ║${NC}\n"
printf "  ${GREEN}${BOLD}╚════════════════════════════════════════════╝${NC}\n"
echo ""
printf "  ${WHITE}${BOLD}Whisper Village ${VERSION}${NC} is ready to roll.\n"
echo ""
printf "  ${DIM}╭──────────────────────────────────────────╮${NC}\n"
printf "  ${DIM}│${NC}  ${CYAN}▸${NC} Quick setup takes ~2 minutes         ${DIM}│${NC}\n"
printf "  ${DIM}│${NC}  ${CYAN}▸${NC} Grant mic access when prompted        ${DIM}│${NC}\n"
printf "  ${DIM}│${NC}  ${CYAN}▸${NC} Pick a hotkey, start talking!         ${DIM}│${NC}\n"
printf "  ${DIM}╰──────────────────────────────────────────╯${NC}\n"
echo ""

# Launch the app
printf "  ${CYAN}◐${NC} Launching..."
open "/Applications/Whisper Village.app"
sleep 0.5
printf "\r"
success "App launched!"
echo ""

printf "  ${MAGENTA}${BOLD}Happy talking! 🎙️${NC}\n"
echo ""
printf "  ${DIM}Pro tip: Look for the menu bar icon (top right)${NC}\n"
echo ""

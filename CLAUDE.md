# Whisper Village - Development Guide

## User Workflow States

**Tell me which state you're in. I handle everything else.**

### State 1: "Fix a bug" / "Add a feature"
You have an idea or found a bug. We iterate locally until it works.

**What you do:** Describe the problem or feature. Test when I say "try it now."
**What I do:** Edit code, rebuild the Dev app, launch it for you to test. Repeat until fixed.

### State 2: "Ship it" / "Push a new version"
Local testing looks good. Time to release.

**What you do:** Say "ship it" or "push new version."
**What I do:**
1. Build Release version
2. Create DMG
3. Update version numbers
4. Create GitHub release
5. Update appcast.xml for auto-updates
6. Commit and push

### State 3: "I want to use the new version"
New version is pushed. You want to update your production app.

**What you do:** Say "update my app" or "use the new version."
**What I do:** Guide you through updating (Sparkle auto-update or manual DMG install).

---

## Memory System

**Every new agent should read these files FIRST:**

### STATE.md - What We Know (The Past)
- **Location:** `/Users/joshuamullet/code/whisper-village/STATE.md`
- **Contains:** Facts, lessons learned, accomplished work
- **Organization:** Newest entries at top with timestamps

### PLAN.md - What We're Doing (The Future)
- **Location:** `/Users/joshuamullet/code/whisper-village/PLAN.md`
- **Contains:** Current work, next steps, active tasks
- **Organization:** Current task at top, priority order descending

### The Workflow (Scoop & Consolidate)
1. Work on top item in PLAN.md
2. When completed: scoop it off the top
3. Consolidate into concise learning
4. Drop at top of STATE.md with timestamp

---

## Project Facts

**Whisper Village** is a macOS menu bar app for voice-to-text transcription.

- Swift/SwiftUI + Xcode
- Local Whisper + cloud providers (Deepgram, Groq, OpenAI, etc.)
- Distribution: GitHub Releases + Sparkle auto-updates

**Two apps exist:**
| App | Bundle ID | Purpose |
|-----|-----------|---------|
| Whisper Village | `town.mullet.WhisperVillage` | Production |
| Whisper Village Dev | `town.mullet.WhisperVillage.debug` | Development |

Can run both side-by-side. Dev has its own permissions.

---

## CLI Commands (For Claude's Reference)

User doesn't need to know these. Claude runs them.

```bash
# Build Dev
xcodebuild -scheme VoiceInk -project /Users/joshuamullet/code/whisper-village/VoiceInk.xcodeproj -configuration Debug -allowProvisioningUpdates build

# Run Dev
open "/Users/joshuamullet/Library/Developer/Xcode/DerivedData/VoiceInk-gqtdhjqfugpinvguwravwbwwibyw/Build/Products/Debug/Whisper Village Dev.app"

# Kill Dev
pkill -f "Whisper Village Dev"

# Full Cycle
pkill -f "Whisper Village Dev"; xcodebuild -scheme VoiceInk -project /Users/joshuamullet/code/whisper-village/VoiceInk.xcodeproj -configuration Debug -allowProvisioningUpdates build && open "/Users/joshuamullet/Library/Developer/Xcode/DerivedData/VoiceInk-gqtdhjqfugpinvguwravwbwwibyw/Build/Products/Debug/Whisper Village Dev.app"

# Build Release (for testing locally only)
xcodebuild -scheme VoiceInk -project /Users/joshuamullet/code/whisper-village/VoiceInk.xcodeproj -configuration Release -allowProvisioningUpdates clean archive
```

---

## ⚠️ CRITICAL: Distribution Signing (READ THIS BEFORE SHIPPING)

**This has caused issues multiple times. DO NOT SKIP THIS SECTION.**

### The Problem
- "Apple Development" certificates ONLY work on devices registered in the Apple Developer account
- To distribute to ANY Mac, you need a **Developer ID Application** certificate + notarization

### Check Available Certificates
```bash
security find-identity -v -p codesigning | grep -i "developer id"
```

### Current Status (as of Dec 2025)
**NO Developer ID certificate exists.** Only Apple Development certificates are available.

To fix this:
1. Go to https://developer.apple.com/account/resources/certificates/list
2. Create a "Developer ID Application" certificate
3. Download and install it in Keychain

### Proper Distribution Build (Once Developer ID Exists)

```bash
# 1. Build and archive
xcodebuild -scheme VoiceInk -project /Users/joshuamullet/code/whisper-village/VoiceInk.xcodeproj \
  -configuration Release \
  -archivePath /Users/joshuamullet/code/whisper-village/build/WhisperVillage.xcarchive \
  clean archive

# 2. Export with Developer ID signing
xcodebuild -exportArchive \
  -archivePath /Users/joshuamullet/code/whisper-village/build/WhisperVillage.xcarchive \
  -exportPath /Users/joshuamullet/code/whisper-village/build/Export \
  -exportOptionsPlist /Users/joshuamullet/code/whisper-village/ExportOptions.plist

# 3. Notarize (required for Gatekeeper)
xcrun notarytool submit /path/to/WhisperVillage.dmg \
  --apple-id "your@email.com" \
  --team-id "TEAM_ID" \
  --password "app-specific-password" \
  --wait

# 4. Staple the notarization ticket
xcrun stapler staple /path/to/WhisperVillage.dmg
```

### ExportOptions.plist (Create This File)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
</dict>
</plist>
```

### When User Says "Ship It"
1. **FIRST** run: `security find-identity -v -p codesigning | grep -i "developer id"`
2. If no Developer ID cert exists → STOP and tell user to create one
3. If cert exists → proceed with distribution build above

---

## Key Directories

- `VoiceInk/` - Main source code (legacy name)
- `VoiceInk/Services/` - Transcription, word replacement, AI enhancement
- `VoiceInk/Views/` - SwiftUI views
- `VoiceInk/Whisper/` - Local Whisper integration

---

## Important Instructions

Do what has been asked; nothing more, nothing less.
NEVER create files unless absolutely necessary.
ALWAYS prefer editing existing files over creating new ones.

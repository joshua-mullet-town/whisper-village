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
**What I do:** Follow the **Ship It Pipeline** below exactly.

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
- **Organization:** Newest entries at top with **full timestamps** (date AND time, e.g., `[2025-12-10 14:30]`)

### PLAN.md - What We're Doing (The Future)
- **Location:** `/Users/joshuamullet/code/whisper-village/PLAN.md`
- **Contains:** Current work, next steps, active tasks
- **Organization:** Current task at top, priority order descending

### The Workflow (Scoop & Consolidate)
1. Work on top item in PLAN.md
2. When completed: scoop it off the top
3. Consolidate into concise learning
4. Drop at top of STATE.md with **full timestamp** (date + time)

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

## 🚀 Ship It Pipeline

**Use the automated script - it handles everything correctly.**

```bash
./scripts/ship-it.sh <version> "<release notes>"
```

**Example:**
```bash
./scripts/ship-it.sh 1.8.7 "Fixed crash on startup"
```

**What the script does:**
1. Bumps version numbers in project.pbxproj
2. Builds Release with ad-hoc signing
3. Re-signs with "Whisper Village Signing" certificate
4. Creates DMG
5. Creates/updates GitHub release
6. Updates appcast.xml
7. Commits and pushes

**Why scripted?** The re-signing step was getting forgotten, breaking Sparkle updates. Script ensures correct signing every time.

---

## 📦 User Installation Instructions

**IMPORTANT:** Users must do this after downloading:

```bash
xattr -cr /Applications/Whisper\ Village.app
```

This removes the quarantine flag. Without it, Gatekeeper blocks the ad-hoc signed app.

Alternative: Right-click → Open → Click "Open" in the dialog (may need to do twice).

---

## 🔐 Self-Signed Certificate Setup (Already Done)

A self-signed certificate "Whisper Village Signing" is installed in the login keychain. This ensures:
- **Same signature across builds** → permissions persist across updates
- Users don't need to re-grant Mic/Accessibility after updates

**Certificate files** (for backup/recreation):
- `/Users/joshuamullet/code/whisper-village/certs/whisper-village.p12` - PKCS12 bundle
- `/Users/joshuamullet/code/whisper-village/certs/whisper-village.crt` - Certificate
- `/Users/joshuamullet/code/whisper-village/certs/whisper-village.key` - Private key

**To reinstall on a new machine:**
```bash
cd /Users/joshuamullet/code/whisper-village/certs
security import whisper-village.p12 -k ~/Library/Keychains/login.keychain-db -P "whisper" -T /usr/bin/codesign
security add-trusted-cert -d -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db whisper-village.crt
```

**Note:** Users still need `xattr -cr` on first install (Gatekeeper). But updates preserve permissions.

---

## Key Directories

- `VoiceInk/` - Main source code (legacy name)
- `VoiceInk/Services/` - Transcription, word replacement, AI enhancement
- `VoiceInk/Views/` - SwiftUI views
- `VoiceInk/Whisper/` - Local Whisper integration

---

## ⚠️ CRITICAL: Development Workflow

**NEVER modify or install to the production app during development.**

During bug fixing and feature development:
1. **ONLY build and test with "Whisper Village Dev"** (Debug configuration)
2. **NEVER touch `/Applications/Whisper Village.app`** until "Ship it" is requested
3. The Dev app has its own bundle ID (`town.mullet.WhisperVillage.debug`) and permissions
4. User tests with Dev app, confirms it works, THEN we ship to production

This separation exists because:
- Production app has user's real permissions and data
- Crashing production app disrupts user's workflow
- Dev app can crash without consequences

**When user says "ship it"** - ONLY THEN do we build Release and update production.

---

## Important Instructions

Do what has been asked; nothing more, nothing less.
NEVER create files unless absolutely necessary.
ALWAYS prefer editing existing files over creating new ones.

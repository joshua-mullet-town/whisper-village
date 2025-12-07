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

## 🚀 Ship It Pipeline (FOLLOW THIS EXACTLY)

**This is the tested, working release process. Do not deviate.**

### Step 1: Bump Version
Edit `VoiceInk.xcodeproj/project.pbxproj`:
- Increment `CURRENT_PROJECT_VERSION` (build number)
- Update `MARKETING_VERSION` (e.g., 1.2.0 → 1.3.0)

### Step 2: Build with Ad-Hoc Signing
```bash
xcodebuild -scheme VoiceInk \
  -project /Users/joshuamullet/code/whisper-village/VoiceInk.xcodeproj \
  -configuration Release \
  -derivedDataPath /Users/joshuamullet/code/whisper-village/build/DerivedData \
  clean build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

**Why ad-hoc?** No Developer ID certificate exists. Ad-hoc removes provisioning profile requirements so the app can run on any Mac.

### Step 3: Create DMG
```bash
create-dmg \
  --volname "Whisper Village" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Whisper Village.app" 150 185 \
  --app-drop-link 450 185 \
  /Users/joshuamullet/code/whisper-village/WhisperVillage-X.X.X.dmg \
  "/Users/joshuamullet/code/whisper-village/build/DerivedData/Build/Products/Release/Whisper Village.app"
```

### Step 4: Create/Update GitHub Release
```bash
# Check if release exists
gh release view vX.X.X

# Create new release (if doesn't exist)
gh release create vX.X.X \
  --title "Whisper Village vX.X.X" \
  --notes "Release notes here" \
  /Users/joshuamullet/code/whisper-village/WhisperVillage-X.X.X.dmg

# Or update existing release
gh release delete-asset vX.X.X WhisperVillage-X.X.X.dmg --yes
gh release upload vX.X.X /Users/joshuamullet/code/whisper-village/WhisperVillage-X.X.X.dmg
```

### Step 5: Update appcast.xml
Update `/Users/joshuamullet/code/whisper-village/appcast.xml`:
- Add new `<item>` entry at top
- Set correct `sparkle:version` (build number)
- Set correct `sparkle:shortVersionString` (marketing version)
- Set correct `length` (file size in bytes from DMG)
- Set correct download URL

### Step 6: Commit and Push
```bash
git add -A
git commit -m "Release vX.X.X: [description]"
git push
```

---

## 📦 User Installation Instructions

**IMPORTANT:** Users must do this after downloading:

```bash
xattr -cr /Applications/Whisper\ Village.app
```

This removes the quarantine flag. Without it, Gatekeeper blocks the ad-hoc signed app.

Alternative: Right-click → Open → Click "Open" in the dialog (may need to do twice).

---

## 🔮 Future: Proper Signing (Optional)

To eliminate the `xattr` requirement, get a Developer ID certificate:
1. Go to https://developer.apple.com/account/resources/certificates/list
2. Create "Developer ID Application" certificate
3. Then use proper signing + notarization instead of ad-hoc

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

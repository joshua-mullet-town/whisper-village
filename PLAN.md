# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Build/Test/Package/Update Workflow

**Goal:** Understand the full development and release cycle.

**What we know from BUILDING.md:**
1. **Prerequisites:** macOS 14.0+, Xcode, Swift
2. **Build whisper.cpp framework first:**
   ```bash
   git clone https://github.com/ggerganov/whisper.cpp.git
   cd whisper.cpp
   ./build-xcframework.sh
   ```
   This creates `build-apple/whisper.xcframework`

3. **Add framework to Xcode project:**
   - Drag whisper.xcframework into project, or
   - Add in "Frameworks, Libraries, and Embedded Content"

4. **Build:** Cmd+B or Product > Build
5. **Run:** Cmd+R or Product > Run

**Still need to figure out:**
- How to create DMG for release
- How Sparkle auto-updates work (appcast.xml)
- Whether users can update in-place vs download new DMG

**Files to investigate:**
- `appcast.xml` - Sparkle update feed
- Xcode archive/export settings

---

## Reference: Key Files

**Word Replacement:**
- `VoiceInk/Services/WordReplacementService.swift` - replacement logic + built-in fixes
- Called from 3 places:
  - `VoiceInk/Whisper/WhisperState.swift:277-281`
  - `VoiceInk/Services/AudioFileTranscriptionService.swift:65-72`
  - `VoiceInk/Services/AudioFileTranscriptionManager.swift:116-122`

**Transcription Flow:**
- `VoiceInk/Whisper/WhisperState.swift` - main transcription orchestration
- `VoiceInk/Services/LocalTranscriptionService.swift` - local Whisper
- `VoiceInk/Services/CloudTranscription/*` - cloud providers

---

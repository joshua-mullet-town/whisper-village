# Whisper Village State - What We Know

**Purpose:** Knowledge base of accomplished work, lessons learned, and current facts. Always add new entries at the top with timestamps.

---

## [2025-12-07] Phase 4 Complete - Streaming Preview UI with Parakeet Support

**Achievement:** Real-time chat-bubble streaming preview with chunk-commit system. Parakeet V3 works best.

**What Works:**
- Chat bubble UI shows transcription as you speak
- 1-second updates for responsive feedback
- 30-second commits lock bubbles in place (nothing disappears)
- Parakeet V3 streaming support added - faster than local Whisper
- Toggle moved to Settings → Experimental Features

**Key Parameters:**
- `streamingIntervalSeconds = 1.0` - update every second
- `chunkCommitIntervalSeconds = 30.0` - commit bubble every 30 seconds

**Recommendation:** Make Parakeet V3 the default model. It's fast enough for real-time streaming and produces excellent results.

**Files Modified:**
- `WhisperState.swift` - chunk-commit logic, Parakeet streaming support
- `MiniRecorderView.swift` - chat bubble UI
- `MiniRecorderPanel.swift` - larger window for bubbles
- `ParakeetTranscriptionService.swift` - added `transcribeSamples()` for streaming
- `ExperimentalFeaturesSection.swift` - streaming toggle moved here

---

## [2025-12-07] Streaming Transcription Working (Phase 1-3)

**Achievement:** Real-time streaming transcription every 3 seconds while recording.

**What Works:**
- AVAudioEngine captures audio → 16kHz mono buffer
- Timer fires every 3 seconds → runs whisper on last 10 seconds
- Interim results in ~1.7-1.9 seconds
- Sliding window keeps context rolling

**Sample Output:**
```
[12:10:43] Starting interim transcription with 54400 samples (3.40s)
[12:10:45] Interim result (1.67s): "Oh, right. Having a pants-pooping kind of time..."
[12:10:55] Starting interim transcription with 160000 samples (10.00s)
[12:10:57] Interim result (1.93s): "...Oh man, I'm actually seeing it. Yeah, it's really cool..."
```

**Key Parameters:**
- `streamingIntervalSeconds = 3.0` - transcribe every 3 seconds
- `streamingMaxAudioMs = 10000` - max 10 seconds of audio context

**Next:** Phase 4 (UI) or Phase 5 (voice commands)

---

## [2025-12-07] Streaming Audio Capture Working (Phase 1-2)

**Achievement:** AVAudioEngine captures real-time audio samples for streaming transcription.

**What We Built:**
- `StreamingRecorder.swift` - captures audio via AVAudioEngine instead of file-based AVAudioRecorder
- `StreamingLogger.swift` - file-based logging to `~/Library/Logs/WhisperVillage/streaming.log`
- Settings toggle in Audio Input → "Real-Time Streaming Mode"

**Key Technical Details:**
- Input: 48kHz (system mic) → Output: 16kHz mono Float32 (Whisper format)
- Resampling via linear interpolation
- Buffer accumulates samples with audio level detection
- Runs alongside existing Recorder (non-destructive)

**Proof It Works:**
```
Input format: 48000.0Hz → Target format: 16000.0Hz ✓
Buffer: 16000 samples (1.0s), level: 0.44  ← speaking detected
Buffer: 32000 samples (2.0s), level: 0.00  ← silence
Stopped. Returning 435200 samples (27.20 seconds) ✓
```

**Files Created:**
- `VoiceInk/Services/StreamingRecorder.swift`
- `VoiceInk/Services/StreamingLogger.swift`
- Modified `VoiceInk/Views/Settings/AudioInputSettingsView.swift` (toggle)
- Modified `VoiceInk/Whisper/WhisperState.swift` (integration)

**Next:** Phase 3 - run whisper_full() every 3 seconds on the buffer.

---

## [2025-12-07] Ship It Pipeline Working

**Achievement:** Figured out the complete release workflow with ad-hoc signing.

**The Problem:**
- "Apple Development" certificates only work on registered devices
- No Developer ID certificate exists
- Apps wouldn't run on other Macs

**The Solution:**
Ad-hoc signing removes provisioning profile requirements:
```bash
xcodebuild ... CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

**User Installation Requirement:**
Users must run after downloading:
```bash
xattr -cr /Applications/Whisper\ Village.app
```

**Full pipeline documented in CLAUDE.md under "Ship It Pipeline".**

---

## [2025-12-05] Word Replacement Regex Bug Fixed + Built-in I' Fix

**Achievement:** Fixed word replacements not matching patterns ending in apostrophes, and added permanent auto-fix for `I'` -> `I'm`.

**The Problem:**
- User configured word replacement `I'` -> `I'm` but it never worked
- Every user encounters this Whisper transcription error

**Root Cause:**
The regex `\bI'\b` fails because `\b` (word boundary) doesn't work after apostrophes.
- `\b` matches transition between word char (`[a-zA-Z0-9_]`) and non-word char
- `'` is non-word, space after is also non-word - no boundary exists
- So `\bI'\b` never matches `I' ` in actual text

**The Fix (2 parts):**

1. **Regex fix in `WordReplacementService.swift:22-29`:**
   - Detect when pattern ends with non-word char
   - Use lookahead `(?=\s|$)` instead of `\b` at end

2. **Built-in fixes in `WordReplacementService.swift:10-33`:**
   - Added `builtInFixes` array for common Whisper errors
   - Added `applyBuiltInFixes()` method that always runs
   - Currently fixes: `I'` -> `I'm`

**Key Insight:** To add more built-in fixes, just add patterns to the `builtInFixes` array.

---

## Project Facts

**App Name:** Whisper Village (rebranded from VoiceInk)
**Current Version:** v1.2.0
**Platform:** macOS
**Distribution:** GitHub Releases + Sparkle auto-updates

---

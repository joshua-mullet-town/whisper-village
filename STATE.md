# Whisper Village State - What We Know

**Purpose:** Knowledge base of accomplished work, lessons learned, and current facts. Always add new entries at the top with full timestamps (date + time).

---

## [2025-12-12 11:00] v1.6.2 - Graceful Stop & Jarvis Bypass

**Problem:** Final transcription could differ from live preview ("2010" bug). Root cause: stopping triggered a SEPARATE re-transcription of the same audio, and Parakeet model is non-deterministic.

**The Fix - Graceful Stop:**
1. Added `shouldStopStreamingGracefully` flag
2. Stop signals loop to finish current iteration + do ONE final pass
3. `stopStreamingTranscriptionGracefully()` waits for task completion
4. Returns `interimTranscription` directly - no separate re-transcription

**Key Insight:** The live transcription and "final" transcription were using identical code paths but being called separately. Model non-determinism meant same audio could produce different results. Solution: don't call it twice.

**Jarvis Bypass:**
- Toggle already existed: `@AppStorage("JarvisEnabled")`
- Added early guards in `performInterimTranscription()` and `toggleRecord()`
- When Jarvis OFF: simple path with no command detection, no chunks, no complexity

**Files Modified:**
- `WhisperState.swift` - Graceful stop + Jarvis bypass guards
- `JarvisCommandService.swift` - Minimum command length check (reject "." as command)

**Lesson Learned:** If live preview works well, use its result directly. Don't re-transcribe.

---

## [2025-12-11 10:30] Streaming Transcription Simplification - One Pipeline

**Problem:** App crashed with EXC_BAD_ACCESS in TdtDecoderState. Root cause: two transcription paths racing on a non-thread-safe decoder:
- Streaming preview: Timer-based, transcribed chunks every 1s, committed every 30s
- Final transcription: Transcribed full buffer at stop

**The Fix - One Pipeline:**
Simplified to always transcribe the FULL audio buffer. Preview = Final.

**Changes Made:**
1. **Removed chunk tracking variables:**
   - `currentChunkStartSample`, `chunkStartTime`, `chunkCommitIntervalSeconds`, `committedChunks`
   - `streamingTranscriptionTimer` (timer-based approach)

2. **New Task-based streaming loop:**
   - `streamingTranscriptionTask` replaces Timer
   - Runs continuously while recording, with 100ms delay between transcriptions
   - Completion-based, not interval-based

3. **Simplified `performInterimTranscription()`:**
   - Always calls `streamingRecorder.getCurrentSamples()` (full buffer)
   - No more chunk logic - preview IS the full transcription
   - `interimTranscription` = `jarvisTranscriptionBuffer` (same thing now)

4. **Preserved user-boundary chunks:**
   - `finalTranscribedChunks` still exists for "Jarvis pause" feature
   - Only populated when USER initiates a pause, not timer-based

**Benefits:**
- Preview = Final: What you see is what you get
- One code path: No race conditions
- ~50-70 lines of code deleted
- Natural rate limiting: Short recording = fast updates, long recording = slower (acceptable)

**Files Modified:**
- `WhisperState.swift` - Core simplification
- `WhisperState+UI.swift` - Removed committedChunks reference

---

## [2025-12-10 16:30] Transcription Architecture Fix - Full Audio Output

**Problem:** Two bugs caused by using live streaming preview as actual output:
1. **Last words cut off** - Preview buffer only updated every 1 second, so words spoken in the last second were missed
2. **30-second chunking artifacts** - Timer-based chunks could split words at boundaries

**Root Cause:** The code used `jarvisTranscriptionBuffer` (continuously updated preview text) for final output instead of transcribing the complete audio.

**The Fix - New Architecture:**
- **Live transcription = PREVIEW ONLY** (visual feedback in UI, never used for output)
- **On pause/send:** Transcribe the FULL audio buffer from `StreamingRecorder`
- **Store chunks only at USER pause boundaries** (not timer-based 30-second commits)
- **Final output = concatenated chunks from user actions**

**Key Changes:**
1. Added `finalTranscribedChunks: [String]` array - only populated on "Jarvis pause"
2. Added `transcribeFullAudioBuffer()` helper - transcribes complete audio in one shot
3. Added `voiceCommandSetFinalText` flag - distinguishes voice command stops from hotkey stops
4. Updated pause/send handlers to use full audio transcription
5. Updated `toggleRecord()` to transcribe full buffer on Option+Space (not use preview)

**Bonus - Trailing Words Capture:**
- Added configurable "linger" delay (0-1500ms) after hotkey stop
- Audio keeps recording during delay to capture any trailing words
- Setting in: Experimental Features → Jarvis Commands → Trailing Words Capture
- Default: 750ms (though the architecture fix made this mostly unnecessary)

**Files Modified:**
- `WhisperState.swift` - Core architecture changes
- `JarvisCommandService.swift` - Added `stripCommand()` helper
- `ExperimentalFeaturesSection.swift` - Added linger slider UI
- `StreamingRecorder.swift` - Added `audioEngine = nil` to release mic

---

## [2025-12-10 08:30] History Recording Fixed for Streaming Mode

**Problem:** Transcriptions weren't being saved to history when using streaming/Jarvis mode. Option+Cmd+V (paste last message) showed "No transcription available" and History view was empty.

**Root Cause:** The Jarvis `sendAndContinue` and `sendAndStop` actions pasted text directly via `CursorPaster.pasteAtCursor()` but never saved to `modelContext`. The original non-streaming code path went through `transcribeAndPaste()` which creates a `Transcription` object and inserts it into the database.

**Fix:** Added `saveStreamingTranscriptionToHistory()` helper function in WhisperState.swift that creates a `Transcription` object and saves to modelContext. Called from both `sendAndContinue` and `sendAndStop` cases.

**Files Modified:** `VoiceInk/Whisper/WhisperState.swift` (lines 824-839, 948-949, 970-971)

---

## [2025-12-10] User Stories & Mode Switching Complete

**User Stories - All Working:**
1. **Multi-Terminal Flip-Flop** ✓ - dictate → send → go to terminal 2 → dictate → send → go to terminal 1
2. **Terminal + Browser Validation** ✓ - dictate → go to terminal → send → go to browser → go to terminal → dictate
3. **Accidental Trigger Prevention** ✓ - Solved with "Jarvis" wake word prefix

**Phase 7 (Seamless Mode Switching) - Solved:**
The wake word approach ("Jarvis X") provides clear command/dictation separation without LLM latency overhead. User explicitly signals intent - no ambiguity, no false triggers, predictable behavior.

---

## [2025-12-10] Debug Log UI Polish Complete

**Achievement:** Polished the streaming preview into a proper timeline with visual states and smart scrolling.

**Features Implemented:**

1. **Unified Bubble Design** - All entries use consistent bubble styling with state indicators:
   - **Active**: Orange background + orange waveform (currently transcribing)
   - **Pending**: Gray background + gray waveform (will be sent)
   - **Sent**: Green-tinted background + checkmark (already sent)
   - **Command Pills**: Colored capsules for pause/listen/navigate/send actions
   - **Listening**: Green waveform pill after resume

2. **Duplicate Command Prevention** - Commands now use time-based debounce:
   - Compares `commandPart` (not full phrase) to handle transcription variations
   - 3-second window to prevent re-executing similar commands
   - Fixes "go to terminal" showing twice due to streaming re-detection

3. **Smart Scroll Behavior** - Using `defaultScrollAnchor(.bottom)`:
   - Starts at bottom, stays anchored when content changes
   - If user scrolls up, respects their position (no auto-pull-back)
   - When user scrolls back to bottom, auto-scroll resumes
   - Much simpler than manual scroll tracking attempts

4. **Visual Polish**:
   - Larger font (15pt) for live transcription bubble
   - Bottom padding (24px) for breathing room
   - Command pills with contextual icons and colors

**Key Learning:** SwiftUI's `defaultScrollAnchor(.bottom)` (macOS 14+) handles "stick to bottom" chat behavior automatically. Manual scroll position tracking via GeometryReader/PreferenceKey doesn't work because those only fire on layout changes, not scroll events.

**Files Modified:**
- `MiniRecorderView.swift` - Simplified scroll view with `defaultScrollAnchor(.bottom)`, visual state bubbles
- `WhisperState.swift` - Time-based command debounce with `lastExecutedJarvisCommandPart` and `lastJarvisCommandTime`

---

## [2025-12-09] Jarvis Command System - Full Debug & Polish

**Major Fixes Completed:**

1. **Debug Log Preview** - Transformed streaming preview into a persistent debug log showing all events (transcriptions, commands, actions, state changes). Nothing disappears during recording session.

2. **Cancel Flow Fixed** - Double-escape and X button now properly clear ALL state:
   - Stop streaming transcription timer FIRST (prevents race conditions)
   - Clear StreamingRecorder audio buffer (was causing old audio to re-transcribe)
   - Clear debug log, committed chunks, interim transcription, command mode
   - Added `clearBuffer()` method to StreamingRecorder

3. **"Jarvis listen" Resume Fixed** - Two issues resolved:
   - Added fuzzy matching for common transcription errors: "lake", "lists", "listing", "liston", "lesson" all map to "listen"
   - Built-in commands can now interrupt slow LLM calls (previously would skip with "already executing")

4. **Duplicate Entry Prevention** - Added `isExecutingJarvisCommand` flag and `lastExecutedJarvisCommand` tracking to prevent same command executing multiple times.

**Key Insight:** The cancel flow was clearing the debug log, but the StreamingRecorder still had old audio samples. When new recording started, it immediately transcribed the OLD audio and added it back to the log. Fix: Clear the audio buffer explicitly on dismiss.

**Files Modified:**
- `WhisperState.swift` - Debug log model, duplicate prevention, logging
- `WhisperState+UI.swift` - Proper cleanup in dismissMiniRecorder
- `StreamingRecorder.swift` - Added `clearBuffer()` method
- `JarvisCommandService.swift` - Fuzzy matching for listen, `isBuiltInCommand()` method
- `MiniRecorderView.swift` - Debug log entry rendering

---

## [2025-12-08] Jarvis Command Mode - Visual Indicator + Command Stripping

**Completed:**
1. **Pause state indicator** - Orange "⏸ Paused - say 'Jarvis listen' to resume" shows in preview box when in command mode
2. **Command stripping** - "Jarvis pause", "Jarvis send it", etc. are now stripped from transcription using `command.textBefore`

**Files Modified:**
- `WhisperState.swift` - Made `isInJarvisCommandMode` published, added command stripping in `executeJarvisCommand`
- `MiniRecorderView.swift` - Added pause indicator UI

---

## [2025-12-08] Jarvis Command System Implemented

**Achievement:** Voice-controlled command system with wake word detection and local LLM interpretation.

**How It Works:**
- Say "Jarvis" followed by any command
- Built-in commands: send it, stop, cancel, pause, listen, go to [app]
- LLM interprets natural language for app/tab navigation
- Enters "command mode" after most commands (stop transcribing)
- "Jarvis listen" resumes transcription

**Files Created:**
- `VoiceInk/Services/JarvisCommandService.swift` - Command detection and execution
- `VoiceInk/Services/OllamaClient.swift` - Local LLM client (Ollama + llama3.2:3b)

**Files Modified:**
- `WhisperState.swift` - Jarvis integration, command mode tracking
- `ExperimentalFeaturesSection.swift` - Jarvis settings UI (wake word, status)

---

## [2025-12-08] Local LLM App Switching Proof of Concept

**Achievement:** Proved local LLM (Ollama + Llama 3.2 3B) can interpret voice commands and choose correct app/tab.

**Test Results:** 11/12 passing

**Key Findings:**
- **Latency:** 600-700ms for basic commands, 1-1.8s for tab switching
- **Accuracy:** Correctly interprets "terminal" → iTerm2, "browser" → Chrome
- **Smart:** Can find tabs by content (e.g., "commander tab" finds tab with "commander" in name)
- **Natural:** Handles variations like "pull up", "switch to", "show me"

**What Works:**
```bash
# Get open apps
osascript -e 'tell app "System Events" to get name of every process whose background only is false'

# Get iTerm tabs with names
osascript (script that enumerates windows/tabs/session names)

# Get Chrome tabs with titles
osascript (script that enumerates windows/tabs/titles)
```

**LLM Setup:**
- Ollama as local server
- Model: llama3.2:3b (2GB)
- Few-shot prompting with examples in prompt

**Files Created:**
- `tests/test_llm_app_switching.py` - Unit tests proving LLM choices

---

## [2025-12-08] Voice Navigation Proof of Concept Working

**Achievement:** Proved two key capabilities for hands-free workflow:

### 1. Send & Continue
- Say "next" → pastes current transcription, hits Enter, **keeps recording**
- Can dictate multiple messages in one recording session
- Buffer clears after send, ready for next dictation

### 2. Focus App (Navigation)
- Say "go to chrome" → focuses Chrome, keeps recording
- Say "go to terminal" → focuses iTerm, keeps recording
- AppleScript runs via `Process` to activate apps
- Recording continues seamlessly after app switch

**Test Flow That Works:**
1. Start recording
2. "Hello this is message one" → "next" → pastes to current app
3. "go to chrome" → Chrome focuses
4. "Here's message two" → "next" → pastes in Chrome
5. "go to terminal" → iTerm focuses
6. "Final message" → "send it" → pastes, stops recording

**Key Insight:** The pieces work individually. Next challenge is making them seamless without accidental triggers.

**Files Modified:**
- `WhisperState.swift` - Added `.sendAndContinue` and `.focusApp` actions, targetApp field

---

## [2025-12-08] Streaming Transcription Feature Complete (Phases 1-5)

**Summary of what was built:**
- Phase 1: AVAudioEngine captures audio samples
- Phase 2: Buffer accumulates at 16kHz mono
- Phase 3: Timer-based streaming transcription (every 1s)
- Phase 4: Chat bubble UI with chunk-commit (30s commits)
- Phase 5: Voice Commands (stop, stop+send, user-configurable)
- Parakeet V3 streaming support
- Streaming preview polish (eyeball toggle, transparency, resize)
- Window position persistence (capsule-based)

**Releases:**
- v1.3.0: Initial streaming preview
- v1.4.0: Voice commands + polish

**Key Files:**
- `StreamingRecorder.swift` - AVAudioEngine capture
- `WhisperState.swift` - Streaming logic, voice commands
- `MiniRecorderView.swift` - Chat bubble UI
- `MiniRecorderPanel.swift` - Window positioning
- `ExperimentalFeaturesSection.swift` - Settings UI

---

## [2025-12-08] v1.4.0 Released

**Achievement:** Voice Commands shipped to GitHub.

**Release URL:** https://github.com/joshua-mullet-town/whisper-village/releases/tag/v1.4.0

---

## [2025-12-08] Phase 5 Complete - Voice Commands

**Achievement:** Full voice command system with user-configurable phrases.

**What Works:**
- Say trigger phrases to stop recording hands-free
- Two actions: "Stop & Paste" or "Stop, Paste & Send" (hits Enter)
- User-configurable phrases in Settings → Experimental Features
- Case-insensitive detection, handles trailing punctuation
- Trigger phrase stripped from final pasted text
- Window position remembers capsule location (not window center)

**Default Triggers:**
- `"send it"` → Stop, Paste & Send
- `"stop recording"` → Stop & Paste
- `"execute"` → Stop, Paste & Send

**Implementation:**
- `VoiceCommand` struct with `phrase` and `action`
- Stored in UserDefaults as JSON (`VoiceCommands` key)
- Settings UI to add/delete/reset commands
- `MiniRecorderPanel` saves capsule position for consistent placement

**Files Modified:**
- `WhisperState.swift` - VoiceCommand model, detection, execution
- `ExperimentalFeaturesSection.swift` - Voice commands settings UI
- `MiniRecorderPanel.swift` - Capsule-based position persistence

---

## [2025-12-08] Streaming Preview Polish Complete

**Achievement:** Polished streaming preview UI with eyeball toggle, transparency controls, resizable box.

**Features Added:**
- Eyeball toggle on orange bar (right side near timer) - show/hide preview
- Transparency +/- controls on preview box - affects background AND bubbles
- Resizable preview box with drag handle (WindowDragBlocker prevents window movement)
- Preview shows immediately when recording starts with "Listening..." placeholder
- Old content cleared when new recording starts

**Key Code:**
- `WindowDragBlocker` - NSViewRepresentable that overrides `mouseDownCanMoveWindow` to block window drag
- `@AppStorage` used for persisting visibility, opacity, width, height

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
**Current Version:** v1.4.0
**Platform:** macOS
**Distribution:** GitHub Releases + Sparkle auto-updates

---

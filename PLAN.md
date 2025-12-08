# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## DONE

- ✅ Phase 1: AVAudioEngine captures audio samples
- ✅ Phase 2: Buffer accumulates at 16kHz mono
- ✅ Phase 3: Timer-based streaming transcription
- ✅ Phase 4: Chat bubble UI with chunk-commit (30s commits, 1s updates)
- ✅ Parakeet V3 streaming support
- ✅ v1.3.0 shipped to GitHub
- ✅ Streaming Preview Polish (eyeball toggle, transparency, resize, immediate show)
- ✅ Phase 5: Voice Commands (stop, stop+send, user-configurable)
- ✅ v1.4.0 shipped to GitHub

---

## FUTURE: Phase 6 - Voice-Activated Start

**Goal:** Start transcription with voice alone (no hotkey needed).

**Challenges:**
- Always-on listening (battery/CPU impact)
- Wake word detection without full transcription
- False positive handling
- Privacy considerations

**Possible Approaches:**
- Lightweight wake word model (like "Hey Siri" style)
- Use system accessibility features
- Small dedicated model just for wake phrase detection

---

## FUTURE: Phase 7 - Application Navigation

**Goal:** Control your Mac with voice commands beyond transcription.

**Ideas:**
- "Focus Safari" → switch to Safari
- "Open terminal" → launch/focus Terminal
- "New tab" → Cmd+T in current app
- "Scroll down" → page navigation

**Challenges:**
- Need robust phrase detection (not just end-of-speech)
- Distinguishing commands from dictation
- App-specific commands
- System permissions for accessibility control

---

## Notes

These are ambitious features that go beyond transcription into voice assistant territory. May want to research existing solutions (macOS Voice Control, Talon, etc.) before building from scratch.

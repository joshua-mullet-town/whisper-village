# Whisper Village State - What We Know

**Purpose:** Knowledge base of accomplished work, lessons learned, and current facts. Always add new entries at the top with timestamps.

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
   ```swift
   let endsWithNonWordChar = original.last.map { !$0.isLetter && !$0.isNumber } ?? false
   let endBoundary = endsWithNonWordChar ? "(?=\\s|$)" : "\\b"
   ```

2. **Built-in fixes in `WordReplacementService.swift:10-33`:**
   - Added `builtInFixes` array for common Whisper errors
   - Added `applyBuiltInFixes()` method that always runs
   - Currently fixes: `I'` -> `I'm`
   - Called from all 3 transcription paths before user word replacements

**Files Modified:**
- `VoiceInk/Services/WordReplacementService.swift` - regex fix + built-in fixes
- `VoiceInk/Whisper/WhisperState.swift:277-278` - call built-in fixes
- `VoiceInk/Services/AudioFileTranscriptionService.swift:65-66` - call built-in fixes
- `VoiceInk/Services/AudioFileTranscriptionManager.swift:116-117` - call built-in fixes

**Key Insight:** To add more built-in fixes, just add patterns to the `builtInFixes` array.

---

## Project Facts

**App Name:** Whisper Village (rebranded from VoiceInk)
**Current Version:** v1.1.0
**Platform:** macOS
**Distribution:** GitHub Releases + Sparkle auto-updates

---

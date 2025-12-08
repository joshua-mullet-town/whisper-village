# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Streaming Preview Polish

### Tasks

1. **Fix I' -> I'm in streaming preview**
   - Final transcription shows "I'm" correctly
   - Streaming preview shows "I'" (missing the built-in fix)
   - Apply `WordReplacementService.applyBuiltInFixes()` to streaming results

2. **Add eyeball toggle on orange bar**
   - Only visible when streaming mode is enabled in settings
   - Open eye = preview box visible
   - Closed eye = preview box hidden
   - Quick toggle without going to settings

3. **Add transparency control to preview box**
   - Small control to increase/decrease opacity
   - Persists preference for next time

4. **Add resizable preview box**
   - Drag to resize (corner or edge handle)
   - Size persists for next session
   - Store in UserDefaults

---

## DONE

- ✅ Phase 1: AVAudioEngine captures audio samples
- ✅ Phase 2: Buffer accumulates at 16kHz mono
- ✅ Phase 3: Timer-based streaming transcription
- ✅ Phase 4: Chat bubble UI with chunk-commit (30s commits, 1s updates)
- ✅ Parakeet V3 streaming support
- ✅ v1.3.0 shipped to GitHub

---

## FUTURE: Phase 5 - Voice Commands

Detect trigger phrases in streaming transcription:
- "Send it" → paste + hit Enter
- "Execute" → paste + Enter + focus iTerm
- Strip command from final text
- User-configurable phrases

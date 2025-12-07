# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Phase 4 - Chunk-Commit Streaming UI

### The Vision
Chat-bubble style streaming preview. Every 10 seconds, a new "bubble" commits and scrolls up. Live preview at the bottom keeps self-correcting.

### Implementation Tasks

1. **Chunk-commit logic in WhisperState**
   - Track `committedChunks: [String]` array
   - Track `currentChunkStartTime`
   - Every 3s: transcribe current chunk (can self-correct)
   - Every 10s: commit chunk to array, start fresh

2. **Chat-bubble UI in MiniRecorderView**
   - ScrollView with bubbles (left-aligned, like texting yourself)
   - Each committed chunk = one bubble
   - Live preview at bottom = current bubble (still correcting)
   - Auto-scroll as new bubbles appear

3. **Fix balloon bug**
   - Orange capsule expands to full height before black box loads
   - Give it a fixed frame so it doesn't balloon

4. **Final transcription display**
   - When recording stops, show REAL transcription (from full audio file)
   - Display semi-transparent until clicked
   - On click, become fully opaque
   - Editable text box
   - Same paste behavior as before

### Cadence
- t=3s: transcribe 0-3s → live preview
- t=6s: transcribe 0-6s → live preview (self-corrects)
- t=9s: transcribe 0-9s → live preview (self-corrects)
- t=10s: transcribe 0-10s → COMMIT as bubble, start fresh
- t=13s: transcribe 10-13s → new live preview
- ...repeat

### Key Point
The bubbles are just visual feedback. Real transcription uses the full audio file at the end (existing proven approach). Bubbles don't affect final paste.

---

## DONE

- ✅ Phase 1: AVAudioEngine captures audio samples
- ✅ Phase 2: Buffer accumulates at 16kHz mono
- ✅ Phase 3: Timer-based streaming transcription (~1.8s per chunk)
- ✅ Basic streaming preview UI (editable text box above capsule)

---

## FUTURE: Phase 5 - Voice Commands

Detect trigger phrases in streaming transcription:
- "Send it" → paste + hit Enter
- "Execute" → paste + Enter + focus iTerm
- Strip command from final text
- User-configurable phrases

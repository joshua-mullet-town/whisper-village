# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## 🔥 ACTIVE: Notch Mode Live Transcription Display

**Goal:** Show live transcription below the notch recorder in a sleek, space-efficient way.

### Problem
- Mini recorder has a floating preview box (works fine)
- Notch recorder has NO live preview - can't see what you're dictating
- Need something sleeker than a big black box for the top-of-screen location

### UX Concept: Scrolling Ticker

A single-line transcription display below the notch that scrolls like a news ticker:

```
                    ┌─────────────────────────┐
                    │        [NOTCH]          │  ← Recording indicator
                    └─────────────────────────┘
    ← older words fade out    │ **newest words** │   new words appear →
```

**Behavior:**
- New words appear on the right
- As more words come, existing text slides left
- Only ~10-12 words visible at a time
- Newest/current words are bold/prominent in center-right
- Older words fade as they approach left edge
- Smooth animation, not jarring

**Alternative:** Instead of continuous scroll, words "settle" after appearing, only scroll when space runs out. Gives a moment of readability.

### Implementation Ideas

1. **Single-line Text view** with horizontal scroll and auto-scroll to end
2. **Custom view** with word-by-word animation (fade in from right)
3. **Marquee-style** continuous scroll at fixed speed
4. **Hybrid:** Appear on right, settle, then scroll left as group when full

### Visual Design
- Transparent/semi-transparent background
- Match notch aesthetic (rounded corners, subtle)
- Don't obstruct too much screen space
- Height: ~24-30px (single line + padding)
- Width: Match notch wings or slightly wider

### Files to Modify
- `NotchRecorderView.swift` - Add preview component below notch
- Possibly new `NotchTranscriptionTicker.swift` for the custom view
- `WhisperState.swift` - May need to expose current transcription differently

### Questions to Resolve
- Should it auto-hide when not speaking for a few seconds?
- Should the ticker be clickable (expand to full preview)?
- Should it respect the existing preview visibility toggle?

---

## BACKLOG: Self-Signed Certificate for Permission Persistence

**Problem:** With ad-hoc signing, each build has unique signature, so macOS requires re-granting permissions (Mic, Accessibility) after every update.

**Solution:** Create self-signed certificate in Keychain Access, use it for all builds. Same signature = permissions persist.

**Trade-off:** Gatekeeper still warns (not Apple-trusted), but `xattr -cr` handles that.

---

## BACKLOG: QoL - Streaming Preview Box Resizing is Janky

**Problem:** The text box that shows live transcription can technically be resized, but the interaction is terrible. You have to whip it around - it's not intuitive or smooth.

**Desired:** Standard, predictable resize handle behavior. Drag edge = resize. No fighting with it.

---

## BACKLOG: Bug - Mic Permanently Stolen from Other Apps

**Problem:** When Whisper Village activates, it permanently kills audio input for other apps (e.g., Teams). When Teams tries to re-enable mic, it also unmutes you - causing accidental unmutes in meetings.

**Fix Applied (testing needed):**
Added `audioEngine = nil` and `inputNode = nil` in `StreamingRecorder.stopRecording()` to fully release mic.

---

## FUTURE: Voice-Activated Start

**Goal:** Start transcription with voice alone (no hotkey needed).

---

## FUTURE: Claude Code Meta Assistant

**Goal:** A "copilot for the copilot" - local LLM that watches Claude Code sessions and provides guidance.

---

## FUTURE: Automated Transcription Testing Framework

**Goal:** Automated accuracy testing with TTS-generated audio to identify weaknesses and track improvements.

**Concept:**
1. **TTS Generation:** Use text-to-speech to generate audio from known ground truth text
2. **Transcription:** Run audio through the transcription pipeline
3. **Comparison:** Compare output to ground truth, calculate WER/CER
4. **Error Analysis:** Categorize errors (substitutions, insertions, deletions), identify patterns
5. **Feedback Loop:** Generate word replacement rules for consistent errors, track improvement over time

**Architecture Options:**
- Direct audio injection into pipeline (clean, fast, isolated testing)
- Live playback through speakers (realistic end-to-end, includes room acoustics)
- Pre-recorded human samples (most realistic, less flexible)

**Metrics:**
- Word Error Rate (WER)
- Character Error Rate (CER)
- Error categorization (substitutions vs insertions vs deletions)
- Per-word/phrase error frequency tracking

**Potential Uses:**
- Regression testing after changes
- Provider comparison (Whisper vs Deepgram vs Groq)
- Model comparison (tiny vs base vs small)
- Identify candidates for word replacement dictionary
- Generate training data for fine-tuning

---

## Notes

**Local LLM Infrastructure (established):**
- Ollama as the server
- llama3.2:3b for Jarvis command interpretation (600-700ms latency)
- llama3.1:8b-instruct-q4_0 for transcription correction (strict prompt, JSON output)

**Transcript Cleanup Research (2024-12-15):**

Datasets that exist:
- [DisfluencySpeech](https://huggingface.co/datasets/amaai-lab/DisfluencySpeech) - 10hrs, multiple transcript versions
- [PodcastFillers](https://podcastfillers.github.io/) - 35K filler annotations, 145hrs
- [Switchboard](https://github.com/vickyzayats/switchboard_corrected_reannotated) - BIO-tagged disfluencies

How Wispr Flow does it:
- Cloud-based fine-tuned Llama on Baseten
- TensorRT-LLM for 200ms inference
- <700ms end-to-end p99 latency
- Custom training data (not public)

Key insight: Audio→text (Whisper) works locally because it's a specialized single-task model. Text→cleaned text is hard because it requires "understanding" - either big LLMs (hallucinate) or fine-tuned models (training effort).

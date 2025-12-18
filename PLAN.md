# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## ✅ READY TO TEST: Self-Signed Certificate + One-Script Update

**Status:** Certificate created, `install.sh` script ready. Need to ship a release to test end-to-end.

### What's Done
- ✅ Self-signed certificate "Whisper Village Signing" created and trusted
- ✅ CLAUDE.md updated with new signing workflow
- ✅ `install.sh` script already handles download, mount, copy, xattr

### To Test
1. Ship a new release using the self-signed certificate (v1.8.1 or v1.9.0)
2. User installs via `install.sh` or manual DMG
3. Grant permissions (Mic, Accessibility)
4. Ship another release (v1.8.2 or v1.9.1)
5. User updates via `install.sh`
6. **Verify:** Permissions should persist without re-granting

### Trade-off
Gatekeeper still warns (not Apple-trusted), but `xattr -cr` handles that on first install.

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

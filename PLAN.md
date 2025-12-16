# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## 🔥 ACTIVE: CoreML Conversion - Native ML Cleanup

**Goal:** Convert filler/repetition models from PyTorch to CoreML so they run natively in Swift without a Python server.

**Why:**
- Ship ML cleanup to other devices without requiring `python ml/server.py`
- Zero external dependencies
- Uses Apple Neural Engine for fast inference
- Single self-contained app

**Steps:**
- [ ] Spike: Convert filler model (BERT token classifier) to CoreML
- [ ] Write Swift inference wrapper for CoreML model
- [ ] Test accuracy matches Python version
- [ ] If successful: convert repetition model too
- [ ] Replace MLCleanupService HTTP calls with native CoreML inference
- [ ] Remove Python server dependency for core features

**Models to convert:**
| Model | Type | Priority |
|-------|------|----------|
| filler-remover | BERT token classifier | HIGH |
| repetition-remover | BERT token classifier | HIGH |
| repair-remover | BERT token classifier | LOW (experimental) |
| list-formatter | T5 seq2seq | LOW (harder, experimental) |

---

## ✅ DONE: Auto List Formatting Model

**Date:** 2025-12-15 (completed)

**Status:** Model trained, 100% content accuracy. See STATE.md for details.

**Next steps for integration:**
- [x] Create `ListFormatter` class in `ml/pipeline/models.py`
- [x] Add post-processing: `_fix_newlines()` regex to handle inline dashes
- [x] Create pytest test suite (`ml/tests/test_list.py`) - 22 tests passing
- [x] Add to pipeline as optional stage
- [x] User toggle in settings (4 individual toggles)

---

## BACKLOG: Persistent Recorder UI (Always-On Widget)

**Goal:** Make the mini recorder always visible on screen, changing state visually instead of appearing/disappearing.

**States:**
- **Idle** - Subtle, minimal presence (just an icon or small pill)
- **Recording** - Obvious visual indication (pulsing, color change)
- **Transcribing** - Processing indicator
- **Done** - Brief success state, return to idle

**Benefits:**
- No jarring pop-up/dismiss
- Always know where the recorder is
- Can show last transcription in idle state
- Foundation for more advanced features (always-on voice activation)

**Effort:** Medium-High (~4-6 hours)

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

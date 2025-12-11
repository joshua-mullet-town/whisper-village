# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Bug - Mic Permanently Stolen from Other Apps
**Problem:** When Whisper Village activates, it permanently kills audio input for other apps (e.g., Teams). When Teams tries to re-enable mic, it also unmutes you - causing accidental unmutes in meetings.

**Research Findings:**
- This is a **known Teams bug on macOS** - Teams loses mic when other apps use it mid-call
- macOS 15.2 supposedly fixed it, but user is on 15.5 and still seeing issues
- Teams creates `MSTeamsAudioDevice.driver` in `/Library/Audio/Plug-Ins/HAL`
- Workaround: Toggle mic in Teams settings during call

**Fix Applied (testing needed):**
Added `audioEngine = nil` and `inputNode = nil` in `StreamingRecorder.stopRecording()` to fully release mic.

**If still broken, possible next steps:**
- Check if regular `Recorder.swift` (AVAudioRecorder) also causes issues
- Investigate Teams' Core Audio Driver conflicts
- Consider if we need to avoid using mic while Teams has it

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

## FUTURE: Phase 7 - Claude Code Meta Assistant

**Goal:** A "copilot for the copilot" - local LLM that watches Claude Code sessions and provides guidance.

**The Problem:**
When returning to a Claude Code session, you have to:
1. Remember what you asked Claude to do
2. Read what Claude did
3. Figure out what to do next

**The Idea:**
A local LLM that monitors Claude Code and provides concise summaries:
- "You asked Claude to fix the page color"
- "Claude modified styles.css and says it's fixed"
- "Next step: Test at localhost:3000 to verify"

**Technical Approach:**
- Use Claude Code hooks
- Feed last exchange to local LLM
- Display summary in HUD/overlay/separate terminal

---

## Notes

**Local LLM Infrastructure (established):**
- Ollama as the server
- llama3.2:3b for command interpretation (600-700ms latency)
- Can add larger model for Phase 8 summarization if needed

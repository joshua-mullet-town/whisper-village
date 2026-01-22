# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Pause/Resume Transcription

**Goal:** Allow user to pause mid-transcription, think, then resume - without losing what was already said.

**Why:**
- Sometimes you start talking and need to change direction
- Currently the only options are: finish or cancel entirely
- Pause lets you collect thoughts without losing progress

**Implementation Concept:**
- When paused: transcribe current audio buffer immediately, store the text
- When resumed: start fresh recording
- On final stop: concatenate stored text + new transcription
- Key insight: concatenate WORDS not audio (simpler, avoids audio stitching complexity)

**UI Considerations:**
- Need a pause hotkey or button
- Visual indicator that we're paused vs stopped vs recording
- Notch UI would need to show paused state

**Open Questions:**
- What triggers pause? Same hotkey as toggle? Different hotkey?
- Should pause auto-transcribe or just hold audio?
- How to handle multiple pause/resume cycles?

---

## NEXT: Spec Browser HUD (`/hud spec`)

**Goal:** Terminal-based navigator for spec-driven projects. Replaces PLAN.md + STATE.md with a visual interface for browsing spec files.

**Tech Stack:**
- **Ink** (React for terminal) - component-based TUI
- Global Claude Code command: `/hud spec`

---

## BACKLOG: Send to Terminal Mode

**Goal:** New mode that sends transcribed text directly to the last-focused terminal window.

**Why:**
- Developers live in the terminal (Claude Code, vim, git, npm, docker)
- Currently have to transcribe → copy → switch to terminal → paste
- This makes voice → CLI a single action

**Implementation Ideas:**
- Track last-focused terminal app (iTerm2, Terminal.app, etc.)
- New hotkey or mode toggle for "Send to Terminal"
- Possibly integrate with Command Mode for voice-driven CLI

**Status:** Attempted but blocked - couldn't get reliable terminal focus/send working. Revisit later.

---

## BACKLOG: Command Mode Phase 2 (Future)

**Ideas explored but deferred:**
- Slack navigation (requires OAuth token per workspace - too complex for now)
- Text commands ("type hello world")
- Complex commands ("open terminal and run npm start")
- Custom user-defined commands

---

## BACKLOG: Bug - Mic Permanently Stolen from Other Apps

**Problem:** When Whisper Village activates, it permanently kills audio input for other apps (e.g., Teams).

**Fix Applied (testing needed):**
Added `audioEngine = nil` and `inputNode = nil` in `StreamingRecorder.stopRecording()` to fully release mic.

---

## FUTURE: Voice-Activated Start

**Goal:** Start transcription with voice alone (no hotkey needed).

---

## FUTURE: Automated Transcription Testing Framework

**Goal:** Automated accuracy testing with TTS-generated audio to identify weaknesses and track improvements.

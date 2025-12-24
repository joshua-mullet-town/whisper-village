# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Nothing Active

Dashboard Feedback Section complete. See STATE.md.

---

## BACKLOG: Append Box - Attach Links/Logs to Transcription

**Problem:** After transcribing, user often needs to add extra content (links, error logs, code snippets). Current workflow: wait for paste → add spaces → paste additional content manually.

**Goal:** Provide an optional box/field where user can tack on additional content to the transcription before it pastes.

**Open Questions:**
- Where does this UI live? In the Live Preview Box? Separate popover?
- Keyboard shortcut to open the append field?
- Does it concat with newlines, spaces, or configurable separator?

---

## BACKLOG: Send to Terminal Mode

**Problem:** User is often viewing something (docs, browser) but wants to send voice commands to terminal. Current workflow: transcribe → navigate to terminal → paste → send → navigate back.

**Goal:** A mode where transcription automatically sends to the last active terminal window without requiring user to navigate there.

**Implementation Ideas:**
- Track "last focused terminal" (Terminal.app, iTerm, Warp, etc.)
- AppleScript/Accessibility API to send text to that window
- Maybe a dedicated hotkey or toggle for "terminal mode"
- Could auto-press Enter after paste (since terminal commands need execution)

**Use Case:** 90%+ of user's Whisper Village usage is terminal commands

---

## BACKLOG: Floating Terminal Overlay Mode

**Problem:** User wants to view docs/browser while still having terminal visible and accessible. Currently must switch between windows.

**Goal:** A mode where Whisper Village hosts/mirrors a terminal that floats on top of all windows with adjustable opacity.

**Concept:**
- Terminal window that follows you across all spaces/apps
- Adjustable opacity (see through to content underneath)
- Can hide/show with hotkey
- Always-on-top behavior
- Transcriptions could paste directly into this overlay terminal

**Implementation Ideas:**
- Could embed a terminal view (pseudo-terminal) in a floating NSPanel
- Or mirror/control an existing terminal window
- Opacity slider in settings or quick-toggle
- Hotkey to show/hide the overlay
- Position: corner, side, or user-draggable

**Use Case:** Claude Code open in terminal, want to see docs while still having terminal accessible

---

## BACKLOG: Command Mode Phase 2 (Future)

**Ideas explored but deferred:**
- Slack navigation (requires OAuth token per workspace - too complex for now)
- Text commands ("type hello world")
- Complex commands ("open terminal and run npm start")
- Custom user-defined commands

---

## BACKLOG: Bug - Mic Permanently Stolen from Other Apps

**Problem:** When Whisper Village activates, it permanently kills audio input for other apps (e.g., Teams). When Teams tries to re-enable mic, it also unmutes you - causing accidental unmutes in meetings.

**Fix Applied (testing needed):**
Added `audioEngine = nil` and `inputNode = nil` in `StreamingRecorder.stopRecording()` to fully release mic.

---

## FUTURE: Voice-Activated Start

**Goal:** Start transcription with voice alone (no hotkey needed).

---

## FUTURE: Automated Transcription Testing Framework

**Goal:** Automated accuracy testing with TTS-generated audio to identify weaknesses and track improvements.

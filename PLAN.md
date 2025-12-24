# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## PRODUCT DIRECTION: The Developer's Voice Tool

**Positioning:** Whisper Village is the ultimate voice-to-text tool for developers. Not general dictation - this is for people who live in the terminal.

### Target User
- Developers using CLI daily (Claude Code, vim, git, npm, docker)
- Power users who want voice without leaving their workflow
- People who think in commands, not paragraphs

### Why Developers?
- We're building features no general dictation app has:
  - Send to Terminal (voice → CLI without switching windows)
  - Floating Terminal Overlay (terminal follows you everywhere)
  - Append Box (attach logs/code to transcriptions)
  - Command Mode (voice navigation)
- Developers appreciate keyboard-first, customizable tools
- Terminal integration is a moat - consumer apps won't build this

### What This Means
- **Features:** Prioritize CLI/terminal integration over prose dictation
- **UX:** Power-user friendly (hotkeys, modes, customization)
- **Marketing:** Dev communities, CLI tool lists, "for developers" messaging
- **Pricing:** Can charge more for specialized tool vs commodity dictation

### Open Questions
- Where do we market? (HN, Reddit r/commandline, X dev community?)
- What's the tagline? "Voice for the terminal"? "Dictation for developers"?
- Do we build integrations? (VS Code extension, CLI tool, raycast?)

---

## CURRENT: Floating Terminal Overlay (iTerm2 API)

**Goal:** Mirror Claude Code sessions in a floating overlay you can see while browsing docs.

### Approach: iTerm2 Python API
- No workflow change - works with existing iTerm2 setup
- Auto-detects Claude Code sessions (smart filtering)
- Tab/swipe through available sessions
- Real-time content streaming + input

### Technical Stack
- **iTerm2 Python API** - session discovery, content streaming, input
- **SwiftTerm** - native Swift terminal view for overlay
- **Python daemon** - bridges iTerm2 API to Swift app
- **Floating NSPanel** - always-on-top, adjustable opacity

### Implementation Steps
1. ✅ Research complete - iTerm2 Python API confirmed viable
2. 🔄 Install `iterm2` Python package
3. 🔄 Create connection script, test session listing
4. Auto-detect Claude Code sessions (filter by name/content)
5. Stream session content via `get_screen_streamer()`
6. Send input via `async_send_text()`
7. SwiftTerm overlay panel with opacity control
8. Tab/swipe UI for switching between sessions
9. Hotkey to show/hide overlay

### Key APIs
```python
# List sessions
app = await iterm2.async_get_app(connection)
for window in app.terminal_windows:
    for tab in window.tabs:
        for session in tab.sessions:
            name = await session.async_get_variable("name")

# Stream content
async with session.get_screen_streamer() as streamer:
    content = await streamer.async_get()

# Send input
await session.async_send_text("my command\n")
```

### User Setup Required
- Enable Python API: iTerm2 → Preferences → General → Magic → Enable Python API

### Supersedes
- Append Box (can paste into overlay terminal)
- Send to Terminal Mode (overlay IS the terminal)

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

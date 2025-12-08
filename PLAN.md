# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

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

## FUTURE: Phase 7 - Application Navigation

**Goal:** Control your Mac with voice commands beyond transcription.

**Ideas:**
- "Focus Safari" → switch to Safari
- "Open terminal" → launch/focus Terminal
- "New tab" → Cmd+T in current app
- "Scroll down" → page navigation

**Challenges:**
- Need robust phrase detection (not just end-of-speech)
- Distinguishing commands from dictation
- App-specific commands
- System permissions for accessibility control

---

## FUTURE: Phase 8 - Local LLM for Fuzzy Command Matching

**Goal:** Use a local LLM to intelligently interpret voice commands instead of hard-coded phrase matching.

**The Problem:**
Hard-coded commands are brittle. If user says "open the browser" or "open Chrome" or "launch Chrome" or "go to Chrome" - they all mean the same thing, but string matching won't catch that.

**The Idea:**
- Run a small local LLM (like Llama, Phi, or similar)
- Feed it the transcribed command + list of available actions
- LLM determines intent and maps to correct action
- Much more flexible than regex/string matching

**Example:**
```
User says: "hey, can you pull up Chrome for me"
LLM interprets: { action: "open_app", target: "Google Chrome" }
```

**Challenges:**
- Latency - needs to be fast enough for voice UX
- Model size vs accuracy tradeoff
- Integration with existing command system
- Keeping it truly local (no API calls)

**Possible Approaches:**
- llama.cpp with a small model (3B params or less)
- MLX on Apple Silicon
- Ollama as a local server
- Fine-tuned model specifically for command interpretation

---

## FUTURE: Phase 9 - Claude Code Meta Assistant

**Goal:** A "copilot for the copilot" - local LLM that watches Claude Code sessions and provides guidance.

**The Problem:**
When returning to a Claude Code session, you have to:
1. Remember what you asked Claude to do
2. Read what Claude did
3. Figure out what to do next (test it? approve it? ask for changes?)

This context-switching is mentally taxing.

**The Idea:**
A local LLM that monitors Claude Code and provides concise summaries:
- "You asked Claude to fix the page color"
- "Claude modified styles.css and says it's fixed"
- "Next step: Test at localhost:3000 to verify"

**How It Would Work:**
1. Hook into Claude Code events (user prompt submitted, Claude response complete)
2. Extract last user message + last Claude response
3. Feed to local LLM with prompt: "Summarize what happened and suggest next action"
4. Display summary somewhere visible

**Where Should It Live?**
Options to explore:
- **Separate terminal window** - Always visible above main Claude Code terminal
- **Inside Whisper Village** - A HUD/overlay that shows the summary
- **tmux/terminal multiplexer** - Split pane that auto-updates
- **Menu bar widget** - Quick glance at current state

**Technical Approach:**
- Use Claude Code hooks (they fire on tool calls and responses)
- Write hook output to a file or pipe
- Separate process reads and feeds to local LLM
- Display result in chosen UI

**Challenges:**
- Parsing Claude Code's output format
- Keeping summaries concise and actionable
- Not being annoying (only update when meaningful)
- Choosing the right local LLM for summarization

---

## Notes

These are ambitious features that go beyond transcription into voice assistant territory. Phase 8 and 9 both rely on local LLMs - may want to establish a shared LLM infrastructure first.

Research existing solutions:
- macOS Voice Control, Talon (for Phase 6-7)
- Ollama, llama.cpp, MLX (for Phase 8-9)
- Claude Code hooks documentation (for Phase 9)

# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Local LLM for Smart App Switching

**Goal:** Replace hard-coded "go to chrome" commands with intelligent LLM-based app switching.

### What We Need to Prove

1. **Get open applications** - Can we quickly list all running apps?
2. **Get app details** - Can we see tabs in iTerm/Chrome?
3. **LLM tool use** - Can a local LLM call a "focus_app" tool correctly?
4. **Speed** - Is it fast enough for voice UX? (< 500ms ideally)

### Technical Approach

```
User says: "switch to the second terminal"
     ↓
1. Get list of open apps + their windows/tabs
2. Send to local LLM with tool definition:
   - Tool: focus_app(app_name, tab_index?)
   - Context: [iTerm: 3 tabs, Chrome: 5 tabs, Finder: 2 windows]
3. LLM returns: focus_app("iTerm", 2)
4. Execute AppleScript to focus iTerm tab 2
```

### Tests Written ✓

- [x] `test_get_open_apps()` - Returns list of running applications
- [x] `test_get_iterm_tabs()` - Returns iTerm tab count and titles
- [x] `test_get_chrome_tabs()` - Returns Chrome tab count and titles
- [x] `test_llm_chooses_correct_app()` - Given "open browser", LLM picks Chrome
- [x] `test_llm_chooses_correct_tab()` - Given "second terminal", LLM picks iTerm tab 2
- [x] `test_llm_handles_ambiguity()` - Given "terminal", LLM picks iTerm (not Terminal.app)
- [x] `test_tab_by_content()` - Given "commander tab", LLM finds tab with "commander" in name
- [x] Natural language variations ("pull up", "show me", "can you switch to")

### LLM Results

**Winner: Ollama + Llama 3.2 3B**
- 600-700ms latency for basic commands
- 1-1.8s for complex tab switching
- 2GB model size
- Few-shot prompting works great

Other options (not tested yet):
- llama.cpp - Could embed directly in Swift
- MLX - Apple Silicon optimized, might be faster

---

## User Stories to Support

These are the real workflows we're building toward:

### Story 1: Multi-Terminal Flip-Flop
> "I'm talking and I want to send to the current terminal, switch to a different terminal, then switch back."

Flow: dictate → send → go to terminal 2 → dictate → send → go to terminal 1

### Story 2: Terminal + Browser Validation
> "Talking, switch to terminal, inject command, go to browser to validate, switch back to terminal, keep talking."

Flow: dictate → go to terminal → send → go to browser → (visually check) → go to terminal → dictate

### Story 3: Avoid Accidental Triggers
> "I accidentally said 'execute' and it sent my incomplete message."

**Problem:** Common words trigger actions unexpectedly.

**Possible Solutions:**
- Use uncommon trigger phrases ("whisper send", "village go")
- Require a "command mode" activation word
- Use tone/pause detection (command voice vs dictation voice)
- LLM intent detection (is this a command or dictation?)

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

## FUTURE: Phase 7 - Seamless Mode Switching

**Goal:** Fluid transitions between dictation and commands without explicit mode switching.

**The Dream:**
- Just talk naturally
- LLM figures out what's a command vs what's dictation
- No "command mode" or "dictation mode" needed
- Context-aware (knows you're in a text field vs desktop)

**Reality Check:**
- Latency might make this impractical
- May need hybrid: obvious commands detected fast, ambiguous ones go to LLM

---

## FUTURE: Phase 8 - Claude Code Meta Assistant

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

**Accidental Trigger Problem:**
This is a real UX issue. Options to explore:
1. **Uncommon phrases** - "whisper send" instead of "send it"
2. **Confirmation delay** - Show what will happen, 500ms to cancel
3. **Command prefix** - "hey village, go to chrome" (only "hey village" activates command mode)
4. **LLM gating** - Every phrase goes to LLM first to classify as command vs dictation

**Local LLM Infrastructure:**
Phases 7 and 8 both need local LLM. Establish this infrastructure now:
- Ollama as the server (easy, well-supported)
- Small fast model for command interpretation (Phi-3, Llama 3.2 1B)
- Larger model for summarization if needed

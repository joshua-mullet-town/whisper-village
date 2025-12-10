# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: [No active task]

Pick from Future phases below.

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

**Local LLM Infrastructure (established):**
- Ollama as the server
- llama3.2:3b for command interpretation (600-700ms latency)
- Can add larger model for Phase 8 summarization if needed

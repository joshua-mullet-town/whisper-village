# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Test Streaming Simplification (needs user testing)

**What Changed:**
- Simplified streaming from two transcription paths to ONE
- Preview now always transcribes FULL audio buffer
- Preview = Final output (no more race conditions)
- Task-based loop instead of timer (100ms between transcriptions)

**Status:** Code complete, build succeeded. Needs user testing.

**Test Plan:**
1. Short recording (5-10 seconds): Preview should update quickly (~1s)
2. Medium recording (1-2 minutes): Preview updates slower but still works
3. Long recording (5+ minutes): Preview might take 3-4s to update - acceptable
4. Stop during transcription: Should wait for current transcription, then output
5. Jarvis pause: Should save current text, clear buffer, continue fresh
6. **Rapid start/stop**: The original crash scenario - try to trigger stop during active streaming

---

## BACKLOG: Self-Signed Certificate for Permission Persistence

**Problem:** With ad-hoc signing, each build has unique signature, so macOS requires re-granting permissions (Mic, Accessibility) after every update.

**Solution:** Create self-signed certificate in Keychain Access, use it for all builds. Same signature = permissions persist.

**Trade-off:** Gatekeeper still warns (not Apple-trusted), but `xattr -cr` handles that.

**Test Plan (local, no GitHub push needed):**
1. Create self-signed cert
2. Build Release with that cert
3. Install to /Applications
4. Grant permissions
5. Build new version with same cert
6. Install again
7. Verify permissions are still granted

**Implementation Steps:**
1. Create signing certificate in Keychain Access
2. Update Ship It Pipeline build command to use certificate
3. Document in CLAUDE.md

---

## BACKLOG: QoL - Streaming Preview Box Resizing is Janky
**Problem:** The text box that shows live transcription can technically be resized, but the interaction is terrible. You have to whip it around - it's not intuitive or smooth.

**Desired:** Standard, predictable resize handle behavior. Drag edge = resize. No fighting with it.

---

## BACKLOG: QoL - Keyboard Shortcuts Blocked While Transcribing
**Problem:** While Whisper Village is actively transcribing, system keyboard shortcuts like Cmd+1, Cmd+2 (for tab switching) are blocked. User can't switch tabs in Chrome/Safari until transcription finishes.

**Likely Cause:** Our hotkey handling might be capturing more key events than necessary, or the app is taking keyboard focus when it shouldn't.

**Desired:** Only capture the specific hotkeys we need. Let all other shortcuts pass through to the active app.

---

## BACKLOG: Bug - Mic Permanently Stolen from Other Apps
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

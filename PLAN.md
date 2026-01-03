# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## FUTURE: Worktree + GitHub Issue Integration

**Goal:** Describe an issue → auto-create GitHub issue → create branch from issue number.

**Workflow Vision:**
1. User runs `/worktree` with a description (not just branch name)
2. System detects it's a description, not a branch name
3. Creates GitHub issue in the project's repo using `gh issue create`
4. Extracts issue number from response
5. Creates branch named `issue-<number>-<slug>` (e.g., `issue-42-fix-login-bug`)
6. Creates worktree with that branch

**Per-Project Configuration:**
- Projects could have custom instructions for worktree creation
- Maybe `.worktree-config.json` in project root?
- Could specify: repo URL, branch naming convention, issue labels

**Open Questions:**
- How to distinguish description from branch name? (Length? Flag? Always description?)
- Where do project-specific instructions live?
- Should it also assign the issue? Add labels?

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

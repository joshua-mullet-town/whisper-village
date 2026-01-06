# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Spec Browser HUD (`/hud spec`)

**Goal:** Terminal-based navigator for spec-driven projects. Replaces PLAN.md + STATE.md with a visual interface for browsing spec files.

**Tech Stack:**
- **Ink** (React for terminal) - component-based TUI
- Global Claude Code command: `/hud spec`

**Features:**
- Directory tree navigation (collapse/expand `specs/journeys/`, `specs/system/`)
- Click into JSON files to see individual stories
- Expand/collapse JSON objects within files
- Visual status indicators computed from timestamps:
  - 🔴 Needs work (`story_updated_at > agent_verified_at` or `agent_verified_at` is null)
  - 🟡 Agent verified, awaiting human (`agent_verified_at > story_updated_at > human_verified_at`)
  - 🟢 Fully verified
- Story counts per file (e.g., "3/7 complete")

**Why This Replaces PLAN + STATE:**
- Stories with `agent_verified_at = null` = planned/future work (was PLAN.md)
- Stories with timestamps filled = completed work (was STATE.md)
- System specs = reference knowledge/facts
- One source of truth: the specs themselves

**Open Questions:**
- Should it support editing (mark as verified, add notes)?
- Keyboard shortcuts for navigation?
- Filter views (show only incomplete, only ready for review)?

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

# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Lazy Model Download (Reduce App Size 285MB → 35MB)

**Goal:** Ship a lightweight app without ML models bundled. Download models on-demand.

**Why:**
- Current app: 285MB (88% is ML models)
- ML models: `filler_remover.mlpackage` (126MB) + `repetition_remover.mlpackage` (126MB)
- Actual code/UI: ~35MB
- Faster downloads, faster updates, better UX

**Implementation:**

### Step 1: Model Storage Location
- Models stored in: `~/Library/Application Support/Whisper Village/Models/`
- Check this location on app launch

### Step 2: ModelDownloadManager
- Download from GitHub Releases (separate assets, not in DMG)
- Show progress UI during download
- Handle errors gracefully (retry, offline mode)

### Step 3: Migration for Existing Users
- On first launch after update, check if models exist in Application Support
- If not, copy from app bundle to Application Support (one-time)
- Future updates ship without bundled models

### Step 4: Update ML Model Loading
- Change model loading code to look in Application Support instead of bundle
- Graceful fallback if models missing (disable filler/repetition removal)

### Step 5: Settings UI
- Show model status: "AI Cleanup Models: Downloaded ✓" or "Download (250MB)"
- Allow re-download if corrupted

### Step 6: Remove Models from Xcode Bundle
- Remove mlpackage files from bundle
- Upload as separate GitHub Release assets

**Files to Modify:**
- Model loading code (find where mlpackage is loaded)
- Settings UI (add model status section)
- New: `ModelDownloadManager.swift`

---

## NEXT: Spec Browser HUD (`/hud spec`)

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

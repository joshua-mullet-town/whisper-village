# Whisper Village State - What We Know

**Purpose:** Knowledge base of accomplished work, lessons learned, and current facts. Always add new entries at the top with full timestamps (date + time).

---

## [2026-01-13 14:30] Project-Specific Worktree Automation - Complete

**Achievement:** Worktrees now run project-specific setup scripts after creation.

**Implementation:**
- **`~/.local/bin/worktree`** - Fast bash script (not prompt-based) for instant worktree creation
- **`.claude/worktree-setup.sh`** - Per-project setup script (runs after npm install)
- **`~/.claude/commands/worktree.md`** - Updated to call setup script in Step 7
- **WorktreeManager.swift** - Added `git worktree prune` on delete failure to prevent stale references

**Features:**
- Auto-detects package manager (npm/yarn/pnpm)
- Copies .env files from main repo
- Runs project-specific setup (e.g., Playwright browser install)
- Shows elapsed time, copies cd command to clipboard
- Prunes stale worktree references automatically

**Guinea Pig:** crowne-vault with `.claude/worktree-setup.sh` for Playwright + env setup

---

## [2026-01-12 12:50] Lazy Model Download - Complete (v1.9.8)

**Achievement:** Reduced app size from 285MB to 13MB DMG (95% reduction) by moving ML models to on-demand download.

**Key Changes:**
- **CleanupModelManager.swift** - Downloads models from GitHub Releases to `~/Library/Application Support/Whisper Village/Models/`
- **CoreMLCleanupService.swift** - Refactored to use generic `MLModel` with `MLDictionaryFeatureProvider` instead of Xcode-generated typed classes
- **AICleanupModelsSection.swift** - Settings UI showing model status (Ready/Not Downloaded/Downloading)
- **Migration logic** - Existing users' models auto-copied from bundle to Application Support

**Technical Notes:**
- Models hosted at `https://github.com/joshua-mullet-town/whisper-village/releases/download/models-v1`
- Uses `URLSession.shared.download()` + `/usr/bin/unzip` for extraction
- Inference changed from typed `filler_remover().prediction()` to generic `model.prediction(from: MLDictionaryFeatureProvider)`

---

## [2026-01-12 12:30] Worktree Manager Fixes - Complete (v1.9.7)

**Achievement:** Fixed two issues from GitHub Issue #3:
1. Real-time worktree detection without restart
2. Non-blocking deletion with progress indicator

**Implementation:**
- **WorktreeFileWatcher** - GCD DispatchSource watches `~/.worktrees/` and project subdirectories
- **Background deletion** - `Task.detached` prevents UI freeze, `deletingWorktrees` set tracks state
- **UI feedback** - Spinner shows during deletion, button disabled

---

## [2026-01-12 07:35] Cancel Shortcut Exposed - Complete (v1.9.6)

**Achievement:** Added Cancel shortcut to Settings UI (was hidden code, never exposed).

**Change:** Added `ShortcutRow` for `.cancelRecorder` in `ShortcutsSection.swift`

**Behavior:**
- Default: Double-tap Escape to cancel
- Custom: Set any shortcut for instant cancel (no double-tap)

---

## [2026-01-03 15:30] Claude Summary Hooks - Complete

**Achievement:** Built session summary system that auto-generates 2-line summaries after each Claude Code response using local Ollama (Phi-3).

**Key Components:**
- **claude-summary-hooks repo** - GitHub hosted, installable via Whisper Village settings
- **UserPromptSubmit hook** - Captures prompts to `/tmp/claude-{session}-conversation.json`
- **Stop hook** - Generates summaries via Ollama, saves to `.claude/SUMMARY.txt`
- **claude-summary command** - Live streaming viewer (`~/.local/bin/claude-summary`)

**Critical Fixes:**
1. **Claude Code 1.0.65 → 2.0.76 upgrade** - Old version didn't support hooks at all
2. **Hook format** - Needed `"matcher": "*"` with nested `"hooks"` array (new format)
3. **Stdin consumption bug** - Combined stop hook needed to read stdin once and pipe to both hooks
4. **Hook coexistence** - Fixed install scripts to append to Stop array instead of replacing (Goal Mode + Summary can coexist)
5. **Settings page lag** - `updateLatestSummary()` was scanning entire ~/code directory. Fixed by checking only known paths + added curl timeout for Ollama check.

**Files:**
- `github.com/joshua-mullet-town/claude-summary-hooks` - Standalone repo with install.sh
- `SummaryHookManager.swift` - Clones repo and runs installer (like GoalModeManager pattern)

---

## [2026-01-02 09:55] Interactive Button Feedback - Complete

**Achievement:** Added visual feedback to worktree action buttons to make them feel interactive and clickable.

**Implementation:**
- **WorktreeActionButton** component with hover and click effects
- **Hover effects:** Background highlight (`Color.primary.opacity(0.1)`) and cursor change to pointing hand
- **Click effects:** Scale down to 0.95 and color opacity to 0.6 when pressed
- **Smooth animations:** 0.1s for hover, 0.05s for press with ease-in-out timing

**Technical Details:**
- Added custom `pressEvents` view modifier using `DragGesture` for proper press/release detection
- Uses `NSCursor.pointingHand.push()` and `NSCursor.pop()` for cursor feedback
- Fixed naming conflict by renaming ClaudeCodeSection's button to `WorktreeCommandButton`

**Files Modified:**
- `VoiceInk/Views/Recorder/NotchRecorderView.swift:802-854` - Added WorktreeActionButton component and pressEvents extension
- `VoiceInk/Views/Settings/ClaudeCodeSection.swift:1055` - Renamed to WorktreeCommandButton to avoid conflict

**User Experience:** Buttons now provide clear visual feedback when hovering and clicking, making them feel more responsive and interactive as requested.

---

## [2026-01-02 09:15] Frictionless Worktree Management - Complete

**Achievement:** Built complete worktree management system with Claude Code slash command integration and Whisper Village notch UI.

**Components:**
- **Slash command** (`/worktree`) - Installable from Whisper Village settings, creates worktrees in `~/.worktrees/`
- **WorktreeManager.swift** - Service that scans `~/.worktrees/` and manages worktree operations (copy path, delete)
- **Notch integration** - Tree icon appears in notch when worktrees exist, shows panel with all worktrees grouped by project
- **Settings integration** - WorktreeCommandRow in ClaudeCodeSection with install/uninstall capability

**Key Design Decisions:**
- Global worktree location: `~/.worktrees/<project>/<branch>/` (avoids gitignore, centralized management)
- Embedded slash command content in app (simpler than Goal Mode's GitHub repo approach)
- Metadata files (`.worktree-meta.json`) for UI tracking with project, branch, created date, etc.
- Notch-first UI (user specifically requested icon in notch, not menu bar)
- Copy path to clipboard functionality for easy `cd` operations

**Technical Implementation:**
- WorktreeCommandManager handles install/uninstall of `~/.claude/commands/worktree.md`
- WorktreeManager scans directories and reads metadata on app startup and panel open
- NotchRecorderView shows tree icon only when `isIdleState && worktreeManager.hasWorktrees`
- WorktreeNotchPanel provides scrollable list with copy/delete actions per worktree

**User Workflow:**
1. Install worktree command from Whisper Village settings
2. Use `/worktree branch-name` in Claude Code to create worktree
3. Tree icon appears in notch (when idle)
4. Click icon to see all worktrees, copy paths, or delete unwanted ones

---

## [2025-12-31 ~10:30] Goal Mode for Claude Code - Complete

**Achievement:** Built autonomous goal-driven loop system for Claude Code. Define a goal with verification criteria, Claude works until done or stuck.

**Components:**
- **GOAL.md template** - Status, Max iterations, Objective, Verification, Evidence, Notes sections
- **Stop hook** (`goal-stop.sh`) - Validates anatomy, enforces state machine, injects status-specific prompts
- **Slash command** (`/goal`) - Guided goal creation flow
- **Whisper Village integration** - Claude Code settings section with install/uninstall and info popover

**State Machine:**
```
PENDING → IMPLEMENTING → VERIFYING → DONE
              ↓              ↓
            STUCK          STUCK
```

**Key Design Decisions:**
- Evidence required before DONE (prevents optimistic false completion)
- Notes section for per-iteration progress logging
- Max iterations as safety limit
- Inspired by Ralph Wiggum's stop hook pattern (ignores `stop_hook_active` flag)

**Repo:** https://github.com/joshua-mullet-town/goal-mode

**Files Created:**
- `~/code/goal-mode/` - Full package with install.sh
- `VoiceInk/Views/Settings/ClaudeCodeSection.swift` - Settings UI with status, install/uninstall, info popover

---

## [2025-12-31 ~08:30] Custom Browser MCP Extension - Completed

**Achievement:** Built custom Chrome extension + MCP server for browser automation with file upload support.

**Why:** BrowserMCP doesn't support file uploads and is closed-source. Needed file uploads for testing bulk import features.

**Result:** Working MCP server at `~/code/bronco-browser/` that can:
- Navigate, click, type in browser tabs
- Upload files to file inputs
- Connect to existing browser sessions (inherits auth/cookies)

---

## [2025-12-26 ~14:00] Terminal HUD / Overlay - Completed via iTerm2 Native Feature

**Achievement:** Wanted floating terminal overlay for Claude Code sessions. Built custom solutions, then discovered iTerm2 already has this built-in.

### What We Tried (Abandoned)

1. **Terminal Overlay (Content Mirroring)**
   - Python daemon bridging iTerm2 API ↔ Swift app
   - Session discovery, content streaming, input sending
   - Floating NSPanel with opacity, font size, theme colors
   - Per-character styling with ScreenStreamer
   - **Why abandoned:** Was heading toward rebuilding iTerm features

2. **iTerm Visibility Control (AppleScript)**
   - AppleScript to show/hide iTerm window
   - Fn key hold detection for temporary visibility
   - Fn double-tap for "sticky" mode
   - **Why abandoned:** AppleScript can't bring window to front without stealing focus

### The Solution: iTerm2's Native Hotkey Window

iTerm2 has a built-in feature that does everything we wanted:
- **Floating window** - stays on top without stealing focus
- **Configurable transparency** - built-in opacity slider
- **Double-tap modifier** - summon/dismiss with Control, Option, etc.
- **Auto-hide** - when you click elsewhere

**Setup:** iTerm2 → Settings → Keys → Hotkey → Create a Dedicated Hotkey Window

### Key Lesson

Before building custom solutions, check if the tool you're integrating with already has the feature built-in. iTerm2's Hotkey Window is battle-tested and handles all the edge cases we were fighting (focus, transparency, floating).

### Files Cleaned Up

- Simplified `DeveloperSection.swift` - now just shows setup tips for iTerm2 Hotkey Window
- Removed custom ITermController code and Fn monitoring from settings UI
- Updated PLAN.md to mark this as completed

---

## [2025-12-23 14:45] Notch UI Improvements

**Achievement:** Added visual indicators to notch recorder for better UX.

### DEV Badge
- Small yellow "DEV" badge in upper-left corner of notch
- Only shows in dev builds (bundle ID ends with `.debug`)
- Helps distinguish which app started the recording

### Hotkey Symbol
- Shows current hotkey symbol (⌥, ⌃, ⌘, fn, ⇧) between X button and timer
- Reminds user which key to press to end recording
- Added `symbol` property to `HotkeyManager.HotkeyOption`

### Peek Button Visibility Fix
- **Old logic:** Only show when `previewStyle == "ticker"`
- **New logic:** Show UNLESS `(livePreviewEnabled && previewStyle == "box")`

| Live Preview | Style  | Peek Button |
|--------------|--------|-------------|
| OFF          | any    | YES         |
| ON           | ticker | YES         |
| ON           | box    | NO          |

### Files Modified
- `VoiceInk/HotkeyManager.swift` - Added `symbol` property to HotkeyOption
- `VoiceInk/Views/Recorder/NotchRecorderView.swift` - DEV badge, hotkey display, peek button fix

---

## [2025-12-23 13:55] v1.9.4 Shipped - Feedback to Slack

**Achievement:** Shipped v1.9.4 with full feedback-to-Slack integration.

### What Changed
- **Bug reports** → Slack #feedback channel (was email)
- **Feature requests** → Slack #feedback channel (was email)
- **Debug logs** → Slack #debug-logs channel (unchanged)
- All webhook URLs moved to `secrets.plist` (gitignored)

### Secrets Pattern
All Slack webhooks now loaded from `secrets.plist`:
- `CrashWebhookURL` - crash reports
- `DebugLogsWebhookURL` - debug logs
- `FeedbackWebhookURL` - bug reports + feature requests

Pattern: `Bundle.main.path(forResource: "secrets", ofType: "plist")`

### GitHub Secret Scanning Fix
Had to `git reset --soft` to remove old commit with hardcoded webhook URL. GitHub push protection blocked until secret was removed from history.

### Files
- `VoiceInk/secrets.plist` - actual webhooks (gitignored)
- `VoiceInk/secrets.plist.example` - template with placeholders
- `VoiceInk/Views/Metrics/FeedbackSectionView.swift` - standalone component
- `VoiceInk/Services/DebugLogCollector.swift` - loads from secrets.plist

---

## [2025-12-23 ~15:00] Dashboard Feedback Section

**Achievement:** Replaced single debug logs button with full feedback section at bottom of Dashboard.

### New Feedback Section
- **Report a Bug** - Popover with text editor → Slack
- **Request Feature** - Popover with text editor → Slack
- **Send Debug Logs** - Popover with optional email → Slack
- **Email contact** - Visible joshua@mullet.town with click-to-copy

### Design
- "HELP US IMPROVE" header
- Three cards with hover effects
- Color-coded icons (red bug, yellow lightbulb, blue docs)
- Moved to bottom of Dashboard (was in TimeEfficiencyView)

### Files
- `VoiceInk/Views/Metrics/FeedbackSectionView.swift` - Standalone component
- `VoiceInk/Views/Metrics/MetricsContent.swift` - Added FeedbackSectionView at bottom
- `VoiceInk/Views/Metrics/TimeEfficiencyView.swift` - Cleaned up, removed feedback code

---

## [2025-12-22 ~14:00] Debug Logs Feature - Remote Troubleshooting

**Achievement:** Added "Send Debug Logs to Joshua" button in Settings for remote user troubleshooting.

### What It Does
- Collects app version, macOS version, RAM, processor info
- Captures all relevant UserDefaults settings
- Grabs last 100 lines from streaming.log
- Posts to #debug-logs Slack channel with user's name (optional)
- Fallback: Copy to clipboard button

### Files Created
- `VoiceInk/Services/DebugLogCollector.swift` - Collector service with Slack webhook posting
- `VoiceInk/Views/Settings/SendDebugLogsSection.swift` - UI in Settings

### Location in App
Settings → scroll to "Having Issues?" section (above Data & Privacy)

---

## [2025-12-22 ~11:30] Settings Consolidation - Voice Engine Killed

**Achievement:** Removed Voice Engine sidebar item, consolidated all settings into one place. Added fast AI providers (Groq, Cerebras).

### What Changed
- **Killed Voice Engine page** - Was overly complex with Local/Cloud/Custom tabs
- **Added TranscriptionModelSection** - Simple dropdown in Settings for model selection
- **Enhanced AI Polish** - Now supports multiple providers (Groq, Cerebras, OpenAI)
- **Groq is default** - 15-25x faster than OpenAI for AI Polish

### New Settings Structure
```
Settings
├── Transcription (NEW - model dropdown + language)
├── Shortcuts
├── AI Polish (ENHANCED - multi-provider)
├── Command Mode
├── Recording Feedback
├── Live Preview
├── Auto Formatting
├── Visual
├── General
└── Data & Privacy
```

### Files Changed
- `VoiceInk/Views/Settings/TranscriptionModelSection.swift` - NEW: Simple model selector
- `VoiceInk/Views/Settings/FormatWithAISection.swift` - Added AIPolishProvider enum, Groq/Cerebras support
- `VoiceInk/Services/LLMFormattingService.swift` - Now uses selected provider/model
- `VoiceInk/Views/Settings/SettingsView.swift` - Added TranscriptionModelSection
- `VoiceInk/Views/ContentView.swift` - Removed Voice Engine from ViewType enum

### AI Polish Providers
| Provider | Speed | Default Model |
|----------|-------|---------------|
| Groq (default) | Fast | llama-3.3-70b-versatile |
| Cerebras | Fastest | llama-3.3-70b |
| OpenAI | Standard | gpt-5-mini |

---

## [2025-12-22 ~10:30] Install Script - POLISHED

**Achievement:** Redesigned install.sh to be visually exciting and professional.

### Features
- ASCII art header with Whisper Village logo
- Random fun taglines on each run
- Feature highlight box showing value props
- Step-by-step progress with clear indicators (STEP 1, STEP 2, STEP 3)
- Animated spinner with rotating fun messages during download
- Graceful error handling for permission issues (shows sudo command)
- Celebration animation on success
- Pro tips and next steps box

### Technical Fixes
- Color codes: Changed from `RED='\033[...'` to `RED=$(printf '\033[...')` for curl pipe compatibility
- Changed all `echo -e` to `printf` with `\n` for cross-shell compatibility
- Escaped `%` as `%%` in printf strings ("100% private")
- Handles old app owned by different user gracefully

### File
- `install.sh` - Complete rewrite for better UX

---

## [2025-12-21 ~15:30] Command Mode - COMPLETE

**Achievement:** Voice-activated system navigation. Start recording, say a command, hit Command Mode shortcut → immediately stops and executes.

### How It Works
1. Start normal recording with main hotkey
2. Say command: "terminal", "Chrome", "second terminal tab"
3. Hit Command Mode shortcut (e.g., ⌘⇧C)
4. Recording stops immediately → Ollama interprets → AppleScript executes

### Flow (Single Action)
- Shortcut triggers `triggerCommandMode()` which:
  - Captures current `interimTranscription`
  - Stops all recording (streaming, audio engine)
  - Sends to Ollama for interpretation
  - Executes via AppleScript (focusApp, focusTab)
  - Plays success/error sound

### Files Created
- `VoiceInk/Views/Settings/CommandModeSection.swift` - Settings UI with enable toggle, shortcut, Ollama status indicator

### Files Modified
| File | Changes |
|------|---------|
| `HotkeyManager.swift` | Added `.commandMode` shortcut, handler calls `triggerCommandMode()` |
| `WhisperState.swift` | Added `isInCommandMode`, `isCommandModeEnabled` properties |
| `WhisperState+UI.swift` | Added `triggerCommandMode()`, `executeCommandModeTranscription()`, AppleScript helpers |
| `NotchRecorderView.swift` | Added orange gradient for command mode, ⌘ icon indicator |
| `SettingsView.swift` | Added CommandModeSection to settings |

### Key Design Decisions
- **One action**: Shortcut immediately stops and executes (no extra step to stop)
- **Single command**: One command per activation, keeps it simple
- **Reuses existing code**: `OllamaClient.interpret()`, AppleScript helpers from old Jarvis

### Slack Navigation - Explored, Deferred
Researched Slack deep linking (`slack://channel?team=X&id=Y`). Requires:
- User OAuth Token (xoxp-...) with `channels:read`, `users:read` scopes
- Per-workspace installation (each org needs separate token)

Not worth the complexity for single-workspace use. Core Command Mode works great for apps/tabs.

---

## [2025-12-21 ~02:00] Settings Reorganization - COMPLETE

**All settings work is done.** Scooped from PLAN.md.

### Summary of All Changes
- **AI Polish** (renamed from "Format with AI") - dedicated section with GPT-5 model picker, cost tracking
- **Default behavior** - basic cleanup if no instructions given
- **Parakeet V3** - auto-downloads and sets as default for new users
- **Mini recorder** - forced migration to notch, picker removed
- **Voice Engine** - simplified, Parakeet recommended with green badge
- **About page** - "offline-first with optional cloud power" messaging
- **Removed** - Hotkey 2, Retry, Cancel Shortcut, Middle-Click, Recorder Style picker

### Deferred Cleanup (not blocking)
- Mini recorder code still exists (MiniRecorderView.swift, MiniWindowManager.swift, etc.)
- Can delete in future pass - UI is hidden, no user impact

---

## Project Facts

**App Name:** Whisper Village (rebranded from VoiceInk)
**Current Version:** v1.9.0
**Platform:** macOS
**Distribution:** GitHub Releases + Sparkle auto-updates
**DMG Size:** ~254MB (includes ~126MB CoreML models per model)

---

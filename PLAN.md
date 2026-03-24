# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Slim Down — Phase 1 (Strip UI) — DONE ✅

**Goal:** Remove everything except the core recording flow.

**Keep:** Notch bar (narrowed to timer + hotkey + peek), Deepgram + local Whisper/Parakeet, paste last, double-tap send, settings for transcription backend only.

### Files to DELETE entirely:
- Views/ContentView.swift → replace with minimal settings-only window
- Views/AudioTranscribeView.swift, TranscriptionHistoryView.swift, TranscriptionCard.swift
- Views/PermissionsView.swift, ModelSettingsView.swift
- Views/Common/ (all 5 files)
- Views/AI Models/ (all 10 files)
- Views/Settings/HomesteadView.swift, AudioInputSettingsView.swift
- Views/Recorder/MiniRecorderPanel.swift
- Services/AIService.swift, ClaudeSessionManager.swift, HomesteadManager.swift
- Services/WhisperServerManager.swift, TerminalSender.swift
- Services/TranscriptionAutoCleanupService.swift, TranscriptionFallbackManager.swift
- Services/DebugLogCollector.swift, AudioFileProcessor.swift
- Services/AudioFileTranscriptionManager.swift, AudioFileTranscriptionService.swift
- Services/CloudTranscription/CustomModelManager.swift
- Services/NativeAppleTranscriptionService.swift
- MediaController.swift, PlaybackController.swift, ClipboardManager.swift, WindowManager.swift
- Models/Transcription.swift (SwiftData history)
- Notifications/LiveBoxView.swift, LiveBoxPanel.swift, AppNotificationView.swift, AppNotifications.swift
- Whisper/WhisperState+ModelQueries.swift, WhisperHallucinationFilter.swift

### Files to MODIFY (strip unused code):
- WhisperVillage.swift — remove UpdaterViewModel, AIService, auto-cleanup, ClaudeSession, Sparkle, main WindowGroup
- NotchRecorderView.swift — remove worktree/spacetab/session/formatmode/commandmode, narrow width
- WhisperState.swift — remove jarvis, format mode, LLM, SpaceTab, PowerMode, ML cleanup, terminal send
- HotkeyManager.swift — remove triple-tap, format-LLM, command-mode secondary actions
- SettingsView.swift — strip to 3 sections: Model, Shortcuts, Visual
- MenuBarView.swift + MenuBarManager.swift — simplify to model + quit + settings
- AppDelegate.swift — remove PowerMode, license, onboarding
- ContentView.swift — replace with minimal settings window

## DONE: Slim Down — Phase 2 (Presenter Integration) ✅

Added PresenterClaimServer.swift — HTTP server on port 8179.
POST /claim {cardId} → stops recording, transcribes async, POSTs to /api/presenter/respond.
Updated electron-presenter Send Here button to call http://localhost:8179/claim on desktop.

---

## BACKLOG: Developer Voice Features

**Focus:** Make Whisper Village the ultimate voice tool for developers working in terminals and IDEs.

## BACKLOG: Spec Browser HUD (`/hud spec`)

**Goal:** Terminal-based navigator for spec-driven projects. Replaces PLAN.md + STATE.md with a visual interface for browsing spec files.

**Tech Stack:**
- **Ink** (React for terminal) - component-based TUI
- Global Claude Code command: `/hud spec`

---

## BACKLOG: Send to Terminal Mode

**Goal:** New mode that sends transcribed text directly to the last-focused terminal window.

**Why:**
- Developers live in the terminal (Claude Code, vim, git, npm, docker)
- Currently have to transcribe → copy → switch to terminal → paste
- This makes voice → CLI a single action

**Implementation Ideas:**
- Track last-focused terminal app (iTerm2, Terminal.app, etc.)
- New hotkey or mode toggle for "Send to Terminal"
- Possibly integrate with Command Mode for voice-driven CLI

**Status:** Attempted but blocked - couldn't get reliable terminal focus/send working. Revisit later.

---

## BACKLOG: Command Mode Phase 2 (Future)

**Ideas explored but deferred:**
- Slack navigation (requires OAuth token per workspace - too complex for now)
- Text commands ("type hello world")
- Complex commands ("open terminal and run npm start")
- Custom user-defined commands

---

## BACKLOG: Bug - Mic Permanently Stolen from Other Apps

**Problem:** When Whisper Village activates, it permanently kills audio input for other apps (e.g., Teams).

**Fix Applied (testing needed):**
Added `audioEngine = nil` and `inputNode = nil` in `StreamingRecorder.stopRecording()` to fully release mic.

---

## FUTURE: Voice-Activated Start

**Goal:** Start transcription with voice alone (no hotkey needed).

---

## FUTURE: Automated Transcription Testing Framework

**Goal:** Automated accuracy testing with TTS-generated audio to identify weaknesses and track improvements.

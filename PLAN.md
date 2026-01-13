# Whisper Village Plan - What We're Doing

**Purpose:** Active work queue and future plans. Current task always at top. When completed, scoop off top and consolidate into STATE.md.

---

## CURRENT: Rename VoiceInk → WhisperVillage Throughout Codebase

**Goal:** Eliminate legacy "VoiceInk" naming from code, directories, and project files so the codebase matches the product name.

**Why:**
- Users who browse the code see "VoiceInk" everywhere - looks sketchy/unprofessional
- Internal confusion between product name and code name
- Technical debt that only gets harder over time

### Scope Assessment

| Category | Count | Approach |
|----------|-------|----------|
| **Directories** | 4 (`VoiceInk/`, `VoiceInk.xcodeproj/`, `VoiceInkTests/`, `VoiceInkUITests/`) | Xcode GUI rename |
| **project.pbxproj** | 53 refs | Auto-updated by Xcode rename |
| **Swift files** | 30 files | Find/replace after Xcode rename |
| **Markdown/docs** | 5 files | Simple find/replace |
| **JSON/scripts** | 5 files | Simple find/replace |

### Safe Step-by-Step Approach

**Phase 1: Preparation (Low Risk)**
1. Commit all current changes
2. Create a backup branch: `git checkout -b pre-rename-backup`
3. Return to main: `git checkout main`

**Phase 2: Xcode Rename (Medium Risk)**
4. Open project in Xcode
5. Select project in Navigator → File Inspector → Identity and Type → Change name to "WhisperVillage"
6. Xcode will offer to rename targets - **accept all**
7. Manage Schemes → Delete old schemes → Create new schemes
8. Build Settings → Search "VoiceInk" → Update any remaining paths (Info.plist, Prefix Header, Development Assets)

**Phase 3: Folder Renames (Medium Risk)**
9. In Xcode Navigator, select `VoiceInk/` folder → File Inspector → Rename to `WhisperVillage/`
10. Repeat for `VoiceInkTests/` → `WhisperVillageTests/`
11. Repeat for `VoiceInkUITests/` → `WhisperVillageUITests/`
12. **Test build** - `Cmd+B`

**Phase 4: Root Folder (Low Risk)**
13. Quit Xcode
14. In Finder, rename `VoiceInk.xcodeproj` → `WhisperVillage.xcodeproj`
15. Reopen project
16. **Test build**

**Phase 5: Code Cleanup (Low Risk)**
17. Global find/replace in Swift files: `VoiceInk` → `WhisperVillage`
18. Rename specific files:
    - `VoiceInk.swift` → `WhisperVillage.swift`
    - `VoiceInk.entitlements` → `WhisperVillage.entitlements`
    - `VoiceInkCSVExportService.swift` → `WhisperVillageCSVExportService.swift`
19. Update markdown files (README, CLAUDE.md, etc.)
20. Update scripts (ship-it.sh)
21. **Test build**

**Phase 6: Verification**
22. Full clean build: `Cmd+Shift+K` then `Cmd+B`
23. Run tests
24. Test Dev app launch
25. Grep for any remaining "VoiceInk" references

### Rollback Plan

If anything breaks irreparably:
```bash
git checkout pre-rename-backup
git branch -D main
git checkout -b main
```

### Critical Warning

**DO NOT change Bundle Identifier** (`town.mullet.WhisperVillage`) - this is how Apple identifies the app. Changing it would:
- Create a "new" app on App Store
- Break existing user installs
- Lose all existing permissions/settings

### Sources

- [Safely Renaming Your Xcode Project](https://www.createwithswift.com/safely-renaming-your-xcode-project/)
- [How to Rename Xcode Project - GitHub Gist](https://gist.github.com/jyshnkr/23cf9c470e129f417940f32924cfb481)
- [SwiftLee Xcode Refactoring](https://www.avanderlee.com/swift/xcode-refactoring/)

---

## NEXT: Spec Browser HUD (`/hud spec`)

**Goal:** Terminal-based navigator for spec-driven projects. Replaces PLAN.md + STATE.md with a visual interface for browsing spec files.

**Tech Stack:**
- **Ink** (React for terminal) - component-based TUI
- Global Claude Code command: `/hud spec`

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

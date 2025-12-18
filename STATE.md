# Whisper Village State - What We Know

**Purpose:** Knowledge base of accomplished work, lessons learned, and current facts. Always add new entries at the top with full timestamps (date + time).

---

## [2025-12-18 23:15] Smart Capitalization (Context-Aware) - WORKING

**Achievement:** Transcriptions now respect cursor context - lowercases first character when pasting mid-sentence.

### The Problem (Solved)
Whisper always capitalizes the first word. But if user types "I was thinking " then dictates "hello there", it would paste as "I was thinking Hello there" instead of "I was thinking hello there".

### The Solution
Use Accessibility API to read focused text field and determine if we're mid-sentence.

### How It Works
1. On paste, get `kAXFocusedUIElementAttribute` (focused element)
2. Read `kAXValueAttribute` (full text) and `kAXSelectedTextRangeAttribute` (cursor position)
3. Extract text before cursor
4. Check last non-whitespace character:
   - `.!?` or newline → CAPITALIZE (sentence/paragraph start)
   - `:;,` or letter/digit or whitespace → lowercase (mid-sentence)

### Files Created
| File | Purpose |
|------|---------|
| `VoiceInk/Services/TextContextService.swift` | Accessibility API wrapper + capitalization logic |

### Files Modified
| File | Changes |
|------|---------|
| `VoiceInk/CursorPaster.swift` | Calls `TextContextService.applySmartCapitalization()` before paste |
| `VoiceInk/Views/Settings/ExperimentalFeaturesSection.swift` | Added toggle (default ON) |

### Key Fix
`UserDefaults.standard.bool()` returns `false` for non-existent keys, but `@AppStorage` defaults to `true`. Fixed by using `UserDefaults.standard.object() as? Bool ?? true` in CursorPaster.

### Sample Log Output
```
[SmartCap] Text before cursor: "Can you see me, Claude? Test me "
[SmartCap] Last non-ws char: 'e' (unicode: 101)
[SmartCap] Decision: lowercase (letter/digit)
[SmartCap] Result: lowercased first char → "here is a test..."
```

---

## [2025-12-18 21:15] Live Transcribe Speed Optimization - SUCCESS

**Achievement:** Stop→paste with live transcribe ON is now instant instead of 1-2s delay.

### The Problem (Solved)
When live transcribe was enabled, stopping would take 1-2 seconds because we transcribed TWICE:
1. Wait for in-flight streaming transcription to finish (500ms-1s)
2. Do ANOTHER full transcription of the same audio (500ms-1s)

### The Fix
Use `interimTranscription` as the final result instead of re-transcribing. The streaming loop already transcribes the FULL audio buffer each pass - no need to do it again.

### Code Change
In `WhisperState.swift`, Jarvis mode path (~line 267-291):
```swift
// OPTIMIZATION: Use interim transcription instead of re-transcribing
let interimText = interimTranscription.trimmingCharacters(in: .whitespacesAndNewlines)
if !interimText.isEmpty {
    // Use the interim transcription (skip re-transcription - saves 500ms-1s!)
    var allChunks = finalTranscribedChunks
    allChunks.append(interimText)
    textToPaste = allChunks.joined(separator: " ")
} else {
    // Fallback: interim was empty, do full transcription
    // ... original code path ...
}
```

### Other Fixes Applied in Same Session
- **Double-tap fix**: `recordStopTime()` moved BEFORE async Task (was being called after await)
- **Debug logging removed**: File I/O on every keypress was causing lag
- **Sound delays removed**: Two 150ms sleeps after sounds were unnecessary

---

## [2025-12-18 13:50] Sparkle Auto-Updates WORKING

**Achievement:** Sparkle auto-updates now work with EdDSA signatures. No Developer ID required.

### The Problem (Solved)
Sparkle rejected updates with "The update is improperly signed and could not be validated." Our self-signed codesign certificate handled macOS permissions, but Sparkle has its own signature validation system requiring EdDSA.

### The Solution
1. Generated EdDSA key pair using Sparkle's `generate_keys` tool (stored in Keychain)
2. Added `SUPublicEDKey` to Info.plist: `dRMep/v3XE3XMuKRBM6xYjefAOs3XxcjtZj1JRKLg0k=`
3. Updated `ship-it.sh` to sign DMGs with EdDSA and add `sparkle:edSignature` to appcast.xml

### Key Files
| File | What it does |
|------|--------------|
| `scripts/ship-it.sh` | Automated release script with EdDSA signing |
| `VoiceInk/Info.plist` | Contains `SUPublicEDKey` |
| `appcast.xml` | Each `<enclosure>` now has `sparkle:edSignature` attribute |

### The Ship-It Pipeline (Final)
```bash
./scripts/ship-it.sh 1.8.9 "Release notes here"
```
Handles: version bump → build → codesign → DMG → EdDSA sign → GitHub release → appcast.xml → commit/push

### One-Time Bootstrap
First EdDSA-signed release (v1.8.7) required manual install. After that, Sparkle auto-updates work (v1.8.7 → v1.8.8 confirmed working).

---

## [2025-12-18 14:10] Permissions Persistence VERIFIED

**Achievement:** Self-signed certificate workflow fully tested and working.

### Test Results
- v1.8.2 → v1.8.3 update completed via `install.sh`
- **Permissions persisted** - no re-granting required for Mic or Accessibility
- App continued to function normally after update

### The Working Pipeline
1. Build with ad-hoc signing: `CODE_SIGN_IDENTITY="-"`
2. Re-sign with self-signed cert: `codesign --force --deep --sign "Whisper Village Signing"`
3. Create DMG with `create-dmg`
4. Upload to GitHub release
5. Update `appcast.xml` with new version and file size
6. Users update via Sparkle or `install.sh`

### Key Lesson
The initial v1.8.2 build failed to persist permissions because we forgot the codesign step after building. Must ALWAYS re-sign with "Whisper Village Signing" after ad-hoc build.

---

## [2025-12-18 12:45] Self-Signed Certificate Setup Complete

**Achievement:** Created self-signed code signing certificate to ensure permissions persist across updates.

### The Problem (Solved)
With ad-hoc signing, each build had a unique signature. macOS treated each update as a "new app" requiring users to re-grant Mic and Accessibility permissions.

### The Solution
Self-signed certificate "Whisper Village Signing" - same certificate = same signature = **permissions persist**.

### What Was Created

| File | Purpose |
|------|---------|
| `certs/codesign.conf` | OpenSSL config for code signing extensions |
| `certs/whisper-village.crt` | The certificate |
| `certs/whisper-village.key` | Private key |
| `certs/whisper-village.p12` | PKCS12 bundle (password: "whisper") |

### Certificate Details
- **CN:** Whisper Village Signing
- **O:** Mullet Town
- **C:** US
- **Validity:** 10 years (expires 2035-12-16)
- **Key Usage:** digitalSignature, codeSigning

### Commands Used (CLI-only, no GUI)
```bash
# Generate certificate and key
openssl req -x509 -newkey rsa:2048 -keyout whisper-village.key -out whisper-village.crt \
  -days 3650 -nodes -config codesign.conf

# Create PKCS12 bundle
openssl pkcs12 -export -out whisper-village.p12 -inkey whisper-village.key \
  -in whisper-village.crt -passout pass:whisper -legacy

# Import to keychain
security import whisper-village.p12 -k ~/Library/Keychains/login.keychain-db \
  -P "whisper" -T /usr/bin/codesign

# Add trust for code signing (REQUIRED - without this, cert doesn't show as valid identity)
security add-trusted-cert -d -r trustRoot -p codeSign \
  -k ~/Library/Keychains/login.keychain-db whisper-village.crt
```

### Key Insight
After importing to keychain, the certificate didn't appear in `security find-identity -v -p codesigning`. The fix was adding explicit trust for code signing with `security add-trusted-cert -d -r trustRoot -p codeSign`.

### Files Modified
- `CLAUDE.md` - Updated Step 2 of Ship It Pipeline to use self-signed certificate
- `.gitignore` - Added `certs/` to protect private key

### What's Next
Test the full workflow: build → sign → ship → update → verify permissions persist.

---

## [2025-12-18] v1.8.0 Released - Unified Recorder UI & Live Transcription Ticker

**Release:** https://github.com/joshua-mullet-town/whisper-village/releases/tag/v1.8.0

### What Shipped

| Feature | Description |
|---------|-------------|
| **Live Transcription Ticker** | Compact scrolling ticker replaces bulky chat bubble preview |
| **Unified Button Layout** | Both notch and mini recorder share same controls: cancel+timer | waveform | peek+eyeball |
| **Peek Transcription** | New button shows full transcription as toast |
| **Simplified Settings** | Removed confusing "Streaming Mode" toggle, now auto-enabled |
| **Shared Ticker Component** | `NotchTranscriptionTicker.swift` used by both recorder modes |

### Live Transcription Ticker Design

```
┌─────────────────────────────────────────────────┐
│  ← older text slides out   |   **newest text** │
└─────────────────────────────────────────────────┘
```

- Single-line, scrolling display (~10-12 words visible)
- New words appear from right, slide left as more come
- Semi-transparent background matching recorder aesthetic
- Shared between notch and mini recorder modes

### Files Created

| File | Purpose |
|------|---------|
| `NotchTranscriptionTicker.swift` | Shared ticker component for both recorder modes |

### Files Modified

| File | Changes |
|------|---------|
| `MiniRecorderView.swift` | Replaced chat bubble with ticker, unified button layout |
| `MiniRecorderPanel.swift` | Reduced window size (450→300 width) |
| `NotchRecorderView.swift` | Added peek button, uses shared ticker |
| `ExperimentalFeaturesSection.swift` | Removed streaming toggle, auto-enables, flattened hierarchy |

### Settings Simplification

**Before:** Streaming Mode was a toggle with child features nested under it
**After:** Streaming mode auto-enables when experimental features is on, no user decision needed

The "Inline Loading Placeholder" was moved to top level since it's not actually dependent on streaming mode.

---

## [2025-12-17] Persistent Notch Recorder (Always-On Mode) Complete

**Achievement:** Notch recorder can now stay visible at all times, with state-based visual feedback.

### What Was Built

| Feature | Description |
|---------|-------------|
| **Always Visible Mode** | Setting toggle keeps notch visible even when not recording |
| **Idle State** | Very subtle gray (~15% opacity), brightens on hover |
| **Recording State** | Full orange/red gradient with audio-reactive glow |
| **Transcribing State** | Blue processing indicator |
| **Click to Start** | Clicking idle notch starts recording |

### Visual States

- **Idle:** `Color.gray.opacity(0.15)` → hover brightens to `0.35`
- **Hover:** Shows interactivity, cursor changes
- **Recording:** Orange/red gradient with audio-reactive highlight extension and inner glow
- **Transcribing:** Blue gradient indicating processing

### Implementation Details

- Added `@AppStorage("NotchAlwaysVisible")` setting
- `isIdleState` computed property: `isAlwaysVisible && recordingState == .idle`
- X button and eyeball hidden in idle state
- Timer hidden in idle state
- Tap gesture starts recording when idle
- NotchWindowManager respects always-visible setting

### Files Modified

| File | Changes |
|------|---------|
| `NotchRecorderView.swift` | Idle/hover states, click-to-start, conditional UI elements |
| `NotchWindowManager.swift` | Don't hide when always-visible enabled |
| `AppearanceSettingsView.swift` | "Always visible" toggle under Notch recorder |

### Also Completed

- **Double-tap threshold increased:** 500ms → 1000ms for easier triggering
- **VAD Audio Preprocessing:** Added `AudioPreprocessor.swift` that uses VAD to extract speech segments before transcription, removing silence to reduce Whisper hallucinations

---

## [2025-12-16] Double-Tap Send Feature - Quick Message Sending

**Achievement:** Double-tap the hotkey within 500ms of stopping to auto-send (paste + Enter).

### How It Works

1. **Tap** → Start recording
2. **Speak** → Transcription happens
3. **Tap** → Stop recording, text pastes
4. **Quick tap again** (within 500ms) → Plays send sound + presses Enter

### The Problem (State Lag)

Initial implementation checked `recordingState` to decide action. But `recordingState` doesn't update instantly after stop - it can lag for 500+ ms. So the double-tap was hitting the `.recording` case and trying to stop again.

**Log evidence:**
```
[20:13:53] KEY DOWN | state=recording | lastStop=0ms      ← First tap (stop)
[20:13:54] KEY DOWN | state=recording | lastStop=588ms    ← Second tap - state STILL recording!
           → STOPPING recording                            ← Wrong! Should be double-tap send
```

### The Fix

**Check double-tap window FIRST, before checking state:**

```swift
// In processKeyPress() - KEY DOWN handling:
if isWithinDoubleTapWindow() {
    // Double-tap send! Set flag for WhisperState to handle
    whisperState.doubleTapSendPending = true
    return  // Don't check state at all
}
// Only check recordingState if NOT within double-tap window
```

**Order of operations matters:**
- Wrong: Check state → then check double-tap (state hasn't caught up)
- Right: Check double-tap → then check state (timing is authoritative)

### The Ordering Fix (Paste Before Enter)

Initial fix triggered Enter immediately on double-tap, but transcription paste was async. Result: Enter fired before paste.

**Solution:** Don't press Enter in HotkeyManager. Set a flag (`doubleTapSendPending`) and let WhisperState press Enter AFTER the paste completes:

```swift
// In WhisperState paste code:
CursorPaster.pasteAtCursor(finalText)
if shouldSend {
    SoundManager.shared.playSendSound()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        CursorPaster.pressEnter()
    }
}
```

### Files Modified

| File | Changes |
|------|---------|
| `HotkeyManager.swift` | Double-tap detection with `lastStopTime` tracking, check window before state |
| `WhisperState.swift` | `doubleTapSendPending` flag, Enter press after paste |
| `SoundManager.swift` | Added send sound support |

### Key Insight

**When dealing with async state, use timing as the source of truth.** The `lastStopTime` timestamp is set synchronously when stop is triggered, so it's reliable. The `recordingState` enum is set asynchronously after transcription completes, so it lags.

---

## [2025-12-16] v1.7.0 Released - Native ML Cleanup

**Release:** https://github.com/joshua-mullet-town/whisper-village/releases/tag/v1.7.0

### What Shipped

| Feature | Description |
|---------|-------------|
| **Native CoreML ML Cleanup** | Filler/repetition removal runs on-device via CoreML |
| **Escape Key Fix** | No longer blocks escape from reaching other apps |
| **Cleaner Settings UI** | Removed abandoned experimental features |

### Escape Key Fix Details

**Problem:** Global hotkey capture via KeyboardShortcuts library was blocking escape key from reaching other apps (like Slack) while recording.

**Solution:** Switched from `KeyboardShortcuts.setShortcut()` to local/global NSEvent monitors:
- `NSEvent.addLocalMonitorForEvents()` - handles escape when app is focused
- `NSEvent.addGlobalMonitorForEvents()` - handles escape when recording but another app is focused
- Neither blocks the event from propagating to other apps

**File Modified:** `MiniRecorderShortcutManager.swift`

---

## [2025-12-16] Native CoreML ML Cleanup - Python Server No Longer Needed

**Goal:** Ship ML cleanup functionality as part of the app bundle, no external dependencies.

### What Shipped (CoreML Native)

| Model | Purpose | Accuracy | Size | Status |
|-------|---------|----------|------|--------|
| Filler Remover | "uh", "um", "er" removal | 99.7% F1 | 126 MB | ✅ Shipped |
| Repetition Remover | "I I I" → "I" | 86.9% F1 | 126 MB | ✅ Shipped |

### Files Created for Native Inference

| File | Purpose |
|------|---------|
| `VoiceInk/Services/BertTokenizer.swift` | BERT WordPiece tokenizer in Swift |
| `VoiceInk/Services/CoreMLCleanupService.swift` | Native CoreML inference wrapper |
| `VoiceInk/Resources/MLModels/vocab.txt` | Tokenizer vocabulary |
| `VoiceInk/Resources/MLModels/filler_remover.mlpackage` | CoreML filler model |
| `VoiceInk/Resources/MLModels/repetition_remover.mlpackage` | CoreML repetition model |
| `ml/export/convert_to_coreml.py` | PyTorch → CoreML conversion script |

### What Was Attempted But Abandoned

| Feature | Why Abandoned |
|---------|---------------|
| **Repair Removal** | 54.6% F1 - too many false positives, removed words that should stay |
| **List Formatting** | Required T5 model + Python server - not portable |
| **Truecasing/Capitalization** | Made sentences worse during testing |

### Architecture Change

**Before:** Swift → HTTP POST → Python server (localhost:8000) → Response
**After:** Swift → CoreMLCleanupService.shared.cleanup() → Native inference

### Key Technical Details

- Models converted from PyTorch (DistilBERT) using `coremltools`
- WordPiece tokenization reimplemented in Swift
- Token-to-word mapping preserves original text structure
- Falls back to HTTP if CoreML unavailable (macOS < 13)
- 100% prediction match between PyTorch and CoreML versions

### Settings Location

Settings → Experimental Features → ML Cleanup (Beta):
- **Filler Removal** (default ON): removes "uh", "um", "er"
- **Repetition Removal** (default ON): removes word repetitions

---

## [2025-12-15 20:00] ML Cleanup Integration Complete - Swift + Python Server

**Goal:** Integrate ML disfluency removal models into Whisper Village app for real-time transcript cleanup.

### Architecture

```
Whisper Village (Swift) → HTTP POST → localhost:8000 → ML Pipeline (Python)
                        ← cleaned text ←
```

### Files Created

| File | Purpose |
|------|---------|
| `ml/server.py` | Flask server on localhost:8000, serves all 4 models |
| `VoiceInk/Services/MLCleanupService.swift` | HTTP client to call Python server |

### Files Modified

| File | Changes |
|------|---------|
| `WhisperState.swift` | Added ML cleanup step after word replacements (2 locations) |
| `ExperimentalFeaturesSection.swift` | Added 4 individual model toggles in UI |

### User Settings

Settings → Experimental Features → ML Cleanup (Beta):
- **Filler Removal** (default ON): uh, um, er → removed
- **Repetition Removal** (default ON): I I I think → I think
- **Self-Correction Removal** (default OFF): experimental, can have false positives
- **List Formatting** (default OFF): one X two Y → bullet points

### Key Findings

- **Model interference**: Running filler+list works well, but repetition/repair models can cause false positives on list-style text (they remove list indicators like "one finish report")
- **Solution**: Individual toggles with safe defaults (filler+repetition ON, repair+list OFF)
- **Pipeline order matters**: filler → repetition → repair → list (disfluency cleanup before structure transformation)

### How to Use

1. Start Python server: `python ml/server.py` (runs on localhost:8000)
2. Enable in app: Settings → Experimental → Streaming Mode → ML Cleanup → Toggle ON
3. Select models to enable
4. Dictate - text is cleaned before pasting

### Test Results

Input: "So the other day I was thinking I I I I had this idea..."
Output: "So the other day I was thinking I had this idea..."

---

## [2025-12-15 18:15] List Formatter Model Trained - 100% Content Accuracy

**Goal:** Auto-format spoken list indicators ("one, two, three" or "first, second, third") into bullet points - Wispr Flow style.

### Results

| Metric | Score |
|--------|-------|
| Content Match | **100%** |
| Exact Match | 21.3% (newline formatting difference) |

### What It Does

```
Input:  "my goals are one finish report two send email"
Output: "my goals are - Finish report - Send email"

Input:  "first call mom second pick up groceries third schedule appointment"
Output: "- Call mom - Pick up groceries - Schedule appointment"

Input:  "I spoke with the client about the proposal"
Output: "I spoke with the client about the proposal"  (unchanged - no list)
```

### Model Details

- **Model:** T5-small (~60MB)
- **Training data:** 1,500 synthetic examples (1,200 train / 150 val / 150 test)
- **Training:** 5 epochs, ~3 min on Mac M-series
- **Location:** `ml/models/list-formatter/`

### Key Finding

Model outputs bullets inline (`- item - item`) instead of with newlines (`- item\n- item`). Easy post-processing fix: `text.replace(" - ", "\n- ")`. The content detection is perfect.

### Files Created

- `ml/training/generate_list_data.py` - Synthetic data generator
- `ml/training/train_list_formatter.py` - T5 training script
- `ml/data/list-formatting/*.json` - Generated datasets

---

## [2025-12-15 18:00] Split Models Complete - RepetitionRemover + RepairRemover

**Goal:** Separate disfluency handling into modular, toggleable models.

### What We Built

| Model | F1 Score | Training Data | What It Catches |
|-------|----------|---------------|-----------------|
| FillerRemover | 99.7% | DisfluencySpeech | "uh", "um" |
| RepetitionRemover | 86.9% | Switchboard (≥50% word overlap) | "I I" → "I" |
| RepairRemover | 54.6% | Switchboard (<50% word overlap) | "store → mall" |

**New Pipeline:**
```
Raw → [FillerRemover] → [RepetitionRemover] → [RepairRemover] → Clean
```

### Data Split Heuristic

Analyzed Switchboard: if reparandum words overlap ≥50% with repair words → repetition, else → repair.
- 74% of data = repetitions (15,680 examples)
- 26% of data = repairs (5,649 examples)

### Test Suite Expanded

From ~15 handcrafted tests to **81 total tests**:
- repetition_tests: 5 → 18 (sampled from Switchboard)
- repair_tests: 4 → 15 (sampled from Switchboard)
- All 81 tests passing

### Files Created/Modified

- `ml/training/train_repetition_only.py` - filters for repetitions
- `ml/training/train_repair_only.py` - filters for repairs
- `ml/pipeline/models.py` - added RepairRemover class
- `ml/pipeline/pipeline.py` - added `enable_repairs` flag (default: False)
- `ml/tests/test_repair.py` - new test file
- `ml/tests/fixtures.json` - expanded with real Switchboard examples

### Key Insight

Repairs (54% F1) are much harder than repetitions (87% F1). The RepairRemover is experimental - disabled by default. Users can toggle each model independently.

---

## [2025-12-15 14:30] ML Pipeline Formalized - Production-Ready Structure

**Goal:** Organize ML models with proper structure, testing, and documentation for iteration.

### What We Built

```
ml/
├── models/                    # Trained models (~265MB each, gitignored)
│   ├── filler-remover/        # 99.7% F1 filler removal
│   └── repetition-remover/    # 79.4% F1 repetition removal
├── pipeline/                  # Python module
│   ├── __init__.py           # Public API
│   ├── models.py             # FillerRemover, RepetitionRemover classes
│   ├── pipeline.py           # TranscriptPipeline orchestration
│   └── server.py             # HTTP server for Whisper Village integration
├── training/                  # Training scripts (rescued from /tmp/)
│   ├── train_filler.py
│   └── train_repetition.py
├── tests/                     # 48 tests, all passing
│   ├── fixtures.json
│   ├── test_filler.py
│   ├── test_repetition.py
│   └── test_pipeline.py
├── README.md                  # Documentation for future agents
├── requirements.txt
└── .gitignore                 # Excludes models/
```

### Usage

```python
from ml.pipeline import TranscriptPipeline
pipeline = TranscriptPipeline()
clean = pipeline.process("i uh think um we we should go")
# Returns: "i think we should go"
```

### HTTP Server

```bash
python -m ml.pipeline.server  # Runs on localhost:8765
curl -X POST http://localhost:8765/cleanup -d '{"text": "i uh think"}'
```

### Key Decisions

- **Models gitignored**: ~265MB each, stored locally, retrain from scripts if needed
- **HTTP server approach**: Clean integration with Swift app via network calls
- **BaseModel pattern**: Easy to add new models (just inherit and set MODEL_DIR)

### Critical Fix

**Rescued models from /tmp/** - repetition model was in `/tmp/disfluency-tagger-combined/` which would be deleted on reboot. Now safely in `ml/models/`.

---

## [2025-12-15 11:10] Specialized Model Pipeline for Transcript Cleanup - SUCCESS

**Goal:** Build small, specialized BERT models for disfluency removal (instead of using LLMs).

### What We Built

| Model | Task | F1 Score | Size | Speed |
|-------|------|----------|------|-------|
| **Filler Remover** | "uh", "um" | **99.7%** | 265MB | ~10ms |
| **Repetition Remover** | "I I" → "I" | **79.4%** | 265MB | ~10ms |

### Key Insight: Specialized Models Beat Combined

Training one model on both fillers AND repetitions degraded performance. When we mixed:
- Switchboard (153K examples of repetitions/repairs)
- DisfluencySpeech (4.5K examples including fillers)

The massive Switchboard data drowned out filler learning. **Solution:** Train separate specialized models.

### Datasets Used

- **DisfluencySpeech** (HuggingFace) - 4,500 examples with `{F}` filler tags
- **Switchboard** (GitHub) - 153K examples with BIO disfluency tags

### Training Facts

- Base model: `distilbert-base-uncased`
- Filler training: ~2 min on Mac M-series (4.5K examples)
- Repetition training: ~45 min on Mac M-series (157K examples)
- Tag scheme: BIO format (B-FILL, I-FILL, B-REP, I-REP, O)

### Pipeline Architecture

```
Raw transcript → [Filler Remover] → [Repetition Remover] → Clean
```

Each model only removes what it's trained for. Discourse markers ("well", "you know") are deliberately KEPT.

### Model Locations

- Filler: `./filler-remover-model/`
- Repetition: `/tmp/disfluency-tagger-combined/`
- Training scripts: `/tmp/train_filler_model_colab.py`, `/tmp/train_disfluency_bert_combined.py`

### Comparison to LLM Approach

| Aspect | BERT Pipeline | LLM (Mistral 7B) |
|--------|---------------|------------------|
| Accuracy | 99.7% filler, 79% rep | ~70% overall |
| Speed | ~20ms | 800-1200ms |
| Hallucination | Never | Sometimes |
| Model Size | 265MB x2 | 4.5GB |

**Winner:** BERT pipeline for disfluency removal. Use LLM only for semantic tasks (self-correction).

---

## [2025-12-14 16:00] LLM Transcription Correction - Model Evaluation

**Goal:** Clean up voice transcriptions using local LLM before pasting.

**Test Cases:**
1. Filler words: "This is um a test of the uh cleanup like feature you know"
2. Stuttering: "I I I think we should do this"
3. Self-correction: "Lets meet at 2pm, no wait, 4pm tomorrow"

**Model Comparison:**

| Model | Filler | Stuttering | Self-Correction | Notes |
|-------|--------|------------|-----------------|-------|
| llama3.2:3b | ✓ | ⚠️ Removes "I think" | ⚠️ Rewrites too much | Too aggressive |
| gemma2:2b | ✓ | ✓ | ✗ Keeps both times | Better but can't do corrections |
| **mistral:7b** | ✓ | ✓ | ✓ | **Winner - all tests pass** |

**Mistral 7B Results:**
- Filler: "This is a test of the cleanup feature" ✓
- Stuttering: "I think we should do this" ✓
- Self-correction: "Meet at 4pm tomorrow" ✓

**Implementation:**
- `LLMCorrectionService.swift` (new) - Calls Ollama for cleanup
- Toggle in Settings → Experimental Features → LLM Correction
- Applied after Whisper transcription, before word replacements
- 10-second timeout (skip if LLM slow)
- Sanity check: reject empty or 2x longer results

**Key Insight:** Larger models (7B) handle instruction-following better than small models (2-3B). Mistral 7B is the sweet spot for local transcription correction.

---

## [2025-12-14 14:30] Peek Toast + Keyboard Shortcut Fix

**Peek Toast Improvements:**
- New `PeekToastView` for showing transcription previews
- Dynamic height: expands to fit content (up to 350px max)
- Hover-to-pause: hovering pauses the auto-dismiss countdown
- Shows "Paused" indicator when hovered
- Eyeball button now works in Simple Mode (triggers peek)

**Keyboard Shortcut Conflict Fixed:**
- **Problem:** Cmd+1-9 (prompt selection) was registered as global hotkeys, blocking browser/terminal tab switching
- **Root Cause:** KeyboardShortcuts library registers system-wide hotkeys that capture events before other apps
- **Fix:** Changed prompt shortcuts from `Cmd+1-9` → `Ctrl+Cmd+1-9`
- Tab switching in Chrome/iTerm now works while recording

**Files Modified:**
- `PeekToastView.swift` (new) - Dynamic height toast with hover-to-pause
- `NotificationManager.swift` - Added `showPeekToast()` method
- `MiniRecorderView.swift` - Eyeball triggers peek in Simple Mode
- `WhisperState.swift` - `peekTranscription()` uses new toast
- `MiniRecorderShortcutManager.swift` - Changed Cmd+1-9 to Ctrl+Cmd+1-9

**Key Insight:** Global hotkeys capture key events system-wide. Use uncommon modifier combinations to avoid conflicts with standard app shortcuts.

---

## [2025-12-14 12:00] Simple Mode + Recording Action Shortcuts

**Achievement:** Added Simple Mode (no live transcription) and configurable recording action shortcuts.

**Simple Mode (Live Preview OFF):**
- Toggle: Settings → Experimental Features → Streaming Mode → Live Preview
- When OFF: Records audio only, no transcription loop running
- On stop: Transcribes full buffer once → pastes
- Preview box and eyeball toggle hidden in Simple Mode
- Much simpler code path, no background CPU usage

**Recording Action Shortcuts:**
- `sendRecorder` - Stop + Transcribe + Paste + Enter (configurable in Settings → Recording Shortcuts)
- `peekTranscription` - On-demand transcription without stopping (configurable)

**Peek in Simple Mode:**
- Does single transcription of current buffer
- Shows result via notification (preview box stays hidden)
- Recording continues after peek

**Files Modified:**
- `WhisperState.swift` - `isLivePreviewEnabled` property, Simple Mode paths in `toggleRecord()` and `performInterimTranscription()`, new `stopRecordingAndSend()` and `peekTranscription()` functions
- `MiniRecorderShortcutManager.swift` - Added `sendRecorder` and `peekTranscription` shortcut handlers
- `MiniRecorderView.swift` - Preview box and eyeball toggle only show when `isLivePreviewEnabled`
- `ExperimentalFeaturesSection.swift` - Live Preview toggle UI with "Simple Mode" label
- `SettingsView.swift` - Recording Actions shortcuts section

**Key Insight:** Simple Mode eliminates streaming transcription entirely - just audio capture → single transcription on demand. Much more reliable for users who don't need live preview.

---

## [2025-12-12 11:00] v1.6.2 - Graceful Stop & Jarvis Bypass

**Problem:** Final transcription could differ from live preview ("2010" bug). Root cause: stopping triggered a SEPARATE re-transcription of the same audio, and Parakeet model is non-deterministic.

**The Fix - Graceful Stop:**
1. Added `shouldStopStreamingGracefully` flag
2. Stop signals loop to finish current iteration + do ONE final pass
3. `stopStreamingTranscriptionGracefully()` waits for task completion
4. Returns `interimTranscription` directly - no separate re-transcription

**Key Insight:** The live transcription and "final" transcription were using identical code paths but being called separately. Model non-determinism meant same audio could produce different results. Solution: don't call it twice.

**Jarvis Bypass:**
- Toggle already existed: `@AppStorage("JarvisEnabled")`
- Added early guards in `performInterimTranscription()` and `toggleRecord()`
- When Jarvis OFF: simple path with no command detection, no chunks, no complexity

**Files Modified:**
- `WhisperState.swift` - Graceful stop + Jarvis bypass guards
- `JarvisCommandService.swift` - Minimum command length check (reject "." as command)

**Lesson Learned:** If live preview works well, use its result directly. Don't re-transcribe.

---

## [2025-12-11 10:30] Streaming Transcription Simplification - One Pipeline

**Problem:** App crashed with EXC_BAD_ACCESS in TdtDecoderState. Root cause: two transcription paths racing on a non-thread-safe decoder:
- Streaming preview: Timer-based, transcribed chunks every 1s, committed every 30s
- Final transcription: Transcribed full buffer at stop

**The Fix - One Pipeline:**
Simplified to always transcribe the FULL audio buffer. Preview = Final.

**Changes Made:**
1. **Removed chunk tracking variables:**
   - `currentChunkStartSample`, `chunkStartTime`, `chunkCommitIntervalSeconds`, `committedChunks`
   - `streamingTranscriptionTimer` (timer-based approach)

2. **New Task-based streaming loop:**
   - `streamingTranscriptionTask` replaces Timer
   - Runs continuously while recording, with 100ms delay between transcriptions
   - Completion-based, not interval-based

3. **Simplified `performInterimTranscription()`:**
   - Always calls `streamingRecorder.getCurrentSamples()` (full buffer)
   - No more chunk logic - preview IS the full transcription
   - `interimTranscription` = `jarvisTranscriptionBuffer` (same thing now)

4. **Preserved user-boundary chunks:**
   - `finalTranscribedChunks` still exists for "Jarvis pause" feature
   - Only populated when USER initiates a pause, not timer-based

**Benefits:**
- Preview = Final: What you see is what you get
- One code path: No race conditions
- ~50-70 lines of code deleted
- Natural rate limiting: Short recording = fast updates, long recording = slower (acceptable)

**Files Modified:**
- `WhisperState.swift` - Core simplification
- `WhisperState+UI.swift` - Removed committedChunks reference

---

## [2025-12-10 16:30] Transcription Architecture Fix - Full Audio Output

**Problem:** Two bugs caused by using live streaming preview as actual output:
1. **Last words cut off** - Preview buffer only updated every 1 second, so words spoken in the last second were missed
2. **30-second chunking artifacts** - Timer-based chunks could split words at boundaries

**Root Cause:** The code used `jarvisTranscriptionBuffer` (continuously updated preview text) for final output instead of transcribing the complete audio.

**The Fix - New Architecture:**
- **Live transcription = PREVIEW ONLY** (visual feedback in UI, never used for output)
- **On pause/send:** Transcribe the FULL audio buffer from `StreamingRecorder`
- **Store chunks only at USER pause boundaries** (not timer-based 30-second commits)
- **Final output = concatenated chunks from user actions**

**Key Changes:**
1. Added `finalTranscribedChunks: [String]` array - only populated on "Jarvis pause"
2. Added `transcribeFullAudioBuffer()` helper - transcribes complete audio in one shot
3. Added `voiceCommandSetFinalText` flag - distinguishes voice command stops from hotkey stops
4. Updated pause/send handlers to use full audio transcription
5. Updated `toggleRecord()` to transcribe full buffer on Option+Space (not use preview)

**Bonus - Trailing Words Capture:**
- Added configurable "linger" delay (0-1500ms) after hotkey stop
- Audio keeps recording during delay to capture any trailing words
- Setting in: Experimental Features → Jarvis Commands → Trailing Words Capture
- Default: 750ms (though the architecture fix made this mostly unnecessary)

**Files Modified:**
- `WhisperState.swift` - Core architecture changes
- `JarvisCommandService.swift` - Added `stripCommand()` helper
- `ExperimentalFeaturesSection.swift` - Added linger slider UI
- `StreamingRecorder.swift` - Added `audioEngine = nil` to release mic

---

## [2025-12-10 08:30] History Recording Fixed for Streaming Mode

**Problem:** Transcriptions weren't being saved to history when using streaming/Jarvis mode. Option+Cmd+V (paste last message) showed "No transcription available" and History view was empty.

**Root Cause:** The Jarvis `sendAndContinue` and `sendAndStop` actions pasted text directly via `CursorPaster.pasteAtCursor()` but never saved to `modelContext`. The original non-streaming code path went through `transcribeAndPaste()` which creates a `Transcription` object and inserts it into the database.

**Fix:** Added `saveStreamingTranscriptionToHistory()` helper function in WhisperState.swift that creates a `Transcription` object and saves to modelContext. Called from both `sendAndContinue` and `sendAndStop` cases.

**Files Modified:** `VoiceInk/Whisper/WhisperState.swift` (lines 824-839, 948-949, 970-971)

---

## [2025-12-10] User Stories & Mode Switching Complete

**User Stories - All Working:**
1. **Multi-Terminal Flip-Flop** ✓ - dictate → send → go to terminal 2 → dictate → send → go to terminal 1
2. **Terminal + Browser Validation** ✓ - dictate → go to terminal → send → go to browser → go to terminal → dictate
3. **Accidental Trigger Prevention** ✓ - Solved with "Jarvis" wake word prefix

**Phase 7 (Seamless Mode Switching) - Solved:**
The wake word approach ("Jarvis X") provides clear command/dictation separation without LLM latency overhead. User explicitly signals intent - no ambiguity, no false triggers, predictable behavior.

---

## [2025-12-10] Debug Log UI Polish Complete

**Achievement:** Polished the streaming preview into a proper timeline with visual states and smart scrolling.

**Features Implemented:**

1. **Unified Bubble Design** - All entries use consistent bubble styling with state indicators:
   - **Active**: Orange background + orange waveform (currently transcribing)
   - **Pending**: Gray background + gray waveform (will be sent)
   - **Sent**: Green-tinted background + checkmark (already sent)
   - **Command Pills**: Colored capsules for pause/listen/navigate/send actions
   - **Listening**: Green waveform pill after resume

2. **Duplicate Command Prevention** - Commands now use time-based debounce:
   - Compares `commandPart` (not full phrase) to handle transcription variations
   - 3-second window to prevent re-executing similar commands
   - Fixes "go to terminal" showing twice due to streaming re-detection

3. **Smart Scroll Behavior** - Using `defaultScrollAnchor(.bottom)`:
   - Starts at bottom, stays anchored when content changes
   - If user scrolls up, respects their position (no auto-pull-back)
   - When user scrolls back to bottom, auto-scroll resumes
   - Much simpler than manual scroll tracking attempts

4. **Visual Polish**:
   - Larger font (15pt) for live transcription bubble
   - Bottom padding (24px) for breathing room
   - Command pills with contextual icons and colors

**Key Learning:** SwiftUI's `defaultScrollAnchor(.bottom)` (macOS 14+) handles "stick to bottom" chat behavior automatically. Manual scroll position tracking via GeometryReader/PreferenceKey doesn't work because those only fire on layout changes, not scroll events.

**Files Modified:**
- `MiniRecorderView.swift` - Simplified scroll view with `defaultScrollAnchor(.bottom)`, visual state bubbles
- `WhisperState.swift` - Time-based command debounce with `lastExecutedJarvisCommandPart` and `lastJarvisCommandTime`

---

## [2025-12-09] Jarvis Command System - Full Debug & Polish

**Major Fixes Completed:**

1. **Debug Log Preview** - Transformed streaming preview into a persistent debug log showing all events (transcriptions, commands, actions, state changes). Nothing disappears during recording session.

2. **Cancel Flow Fixed** - Double-escape and X button now properly clear ALL state:
   - Stop streaming transcription timer FIRST (prevents race conditions)
   - Clear StreamingRecorder audio buffer (was causing old audio to re-transcribe)
   - Clear debug log, committed chunks, interim transcription, command mode
   - Added `clearBuffer()` method to StreamingRecorder

3. **"Jarvis listen" Resume Fixed** - Two issues resolved:
   - Added fuzzy matching for common transcription errors: "lake", "lists", "listing", "liston", "lesson" all map to "listen"
   - Built-in commands can now interrupt slow LLM calls (previously would skip with "already executing")

4. **Duplicate Entry Prevention** - Added `isExecutingJarvisCommand` flag and `lastExecutedJarvisCommand` tracking to prevent same command executing multiple times.

**Key Insight:** The cancel flow was clearing the debug log, but the StreamingRecorder still had old audio samples. When new recording started, it immediately transcribed the OLD audio and added it back to the log. Fix: Clear the audio buffer explicitly on dismiss.

**Files Modified:**
- `WhisperState.swift` - Debug log model, duplicate prevention, logging
- `WhisperState+UI.swift` - Proper cleanup in dismissMiniRecorder
- `StreamingRecorder.swift` - Added `clearBuffer()` method
- `JarvisCommandService.swift` - Fuzzy matching for listen, `isBuiltInCommand()` method
- `MiniRecorderView.swift` - Debug log entry rendering

---

## [2025-12-08] Jarvis Command Mode - Visual Indicator + Command Stripping

**Completed:**
1. **Pause state indicator** - Orange "⏸ Paused - say 'Jarvis listen' to resume" shows in preview box when in command mode
2. **Command stripping** - "Jarvis pause", "Jarvis send it", etc. are now stripped from transcription using `command.textBefore`

**Files Modified:**
- `WhisperState.swift` - Made `isInJarvisCommandMode` published, added command stripping in `executeJarvisCommand`
- `MiniRecorderView.swift` - Added pause indicator UI

---

## [2025-12-08] Jarvis Command System Implemented

**Achievement:** Voice-controlled command system with wake word detection and local LLM interpretation.

**How It Works:**
- Say "Jarvis" followed by any command
- Built-in commands: send it, stop, cancel, pause, listen, go to [app]
- LLM interprets natural language for app/tab navigation
- Enters "command mode" after most commands (stop transcribing)
- "Jarvis listen" resumes transcription

**Files Created:**
- `VoiceInk/Services/JarvisCommandService.swift` - Command detection and execution
- `VoiceInk/Services/OllamaClient.swift` - Local LLM client (Ollama + llama3.2:3b)

**Files Modified:**
- `WhisperState.swift` - Jarvis integration, command mode tracking
- `ExperimentalFeaturesSection.swift` - Jarvis settings UI (wake word, status)

---

## [2025-12-08] Local LLM App Switching Proof of Concept

**Achievement:** Proved local LLM (Ollama + Llama 3.2 3B) can interpret voice commands and choose correct app/tab.

**Test Results:** 11/12 passing

**Key Findings:**
- **Latency:** 600-700ms for basic commands, 1-1.8s for tab switching
- **Accuracy:** Correctly interprets "terminal" → iTerm2, "browser" → Chrome
- **Smart:** Can find tabs by content (e.g., "commander tab" finds tab with "commander" in name)
- **Natural:** Handles variations like "pull up", "switch to", "show me"

**What Works:**
```bash
# Get open apps
osascript -e 'tell app "System Events" to get name of every process whose background only is false'

# Get iTerm tabs with names
osascript (script that enumerates windows/tabs/session names)

# Get Chrome tabs with titles
osascript (script that enumerates windows/tabs/titles)
```

**LLM Setup:**
- Ollama as local server
- Model: llama3.2:3b (2GB)
- Few-shot prompting with examples in prompt

**Files Created:**
- `tests/test_llm_app_switching.py` - Unit tests proving LLM choices

---

## [2025-12-08] Voice Navigation Proof of Concept Working

**Achievement:** Proved two key capabilities for hands-free workflow:

### 1. Send & Continue
- Say "next" → pastes current transcription, hits Enter, **keeps recording**
- Can dictate multiple messages in one recording session
- Buffer clears after send, ready for next dictation

### 2. Focus App (Navigation)
- Say "go to chrome" → focuses Chrome, keeps recording
- Say "go to terminal" → focuses iTerm, keeps recording
- AppleScript runs via `Process` to activate apps
- Recording continues seamlessly after app switch

**Test Flow That Works:**
1. Start recording
2. "Hello this is message one" → "next" → pastes to current app
3. "go to chrome" → Chrome focuses
4. "Here's message two" → "next" → pastes in Chrome
5. "go to terminal" → iTerm focuses
6. "Final message" → "send it" → pastes, stops recording

**Key Insight:** The pieces work individually. Next challenge is making them seamless without accidental triggers.

**Files Modified:**
- `WhisperState.swift` - Added `.sendAndContinue` and `.focusApp` actions, targetApp field

---

## [2025-12-08] Streaming Transcription Feature Complete (Phases 1-5)

**Summary of what was built:**
- Phase 1: AVAudioEngine captures audio samples
- Phase 2: Buffer accumulates at 16kHz mono
- Phase 3: Timer-based streaming transcription (every 1s)
- Phase 4: Chat bubble UI with chunk-commit (30s commits)
- Phase 5: Voice Commands (stop, stop+send, user-configurable)
- Parakeet V3 streaming support
- Streaming preview polish (eyeball toggle, transparency, resize)
- Window position persistence (capsule-based)

**Releases:**
- v1.3.0: Initial streaming preview
- v1.4.0: Voice commands + polish

**Key Files:**
- `StreamingRecorder.swift` - AVAudioEngine capture
- `WhisperState.swift` - Streaming logic, voice commands
- `MiniRecorderView.swift` - Chat bubble UI
- `MiniRecorderPanel.swift` - Window positioning
- `ExperimentalFeaturesSection.swift` - Settings UI

---

## [2025-12-08] v1.4.0 Released

**Achievement:** Voice Commands shipped to GitHub.

**Release URL:** https://github.com/joshua-mullet-town/whisper-village/releases/tag/v1.4.0

---

## [2025-12-08] Phase 5 Complete - Voice Commands

**Achievement:** Full voice command system with user-configurable phrases.

**What Works:**
- Say trigger phrases to stop recording hands-free
- Two actions: "Stop & Paste" or "Stop, Paste & Send" (hits Enter)
- User-configurable phrases in Settings → Experimental Features
- Case-insensitive detection, handles trailing punctuation
- Trigger phrase stripped from final pasted text
- Window position remembers capsule location (not window center)

**Default Triggers:**
- `"send it"` → Stop, Paste & Send
- `"stop recording"` → Stop & Paste
- `"execute"` → Stop, Paste & Send

**Implementation:**
- `VoiceCommand` struct with `phrase` and `action`
- Stored in UserDefaults as JSON (`VoiceCommands` key)
- Settings UI to add/delete/reset commands
- `MiniRecorderPanel` saves capsule position for consistent placement

**Files Modified:**
- `WhisperState.swift` - VoiceCommand model, detection, execution
- `ExperimentalFeaturesSection.swift` - Voice commands settings UI
- `MiniRecorderPanel.swift` - Capsule-based position persistence

---

## [2025-12-08] Streaming Preview Polish Complete

**Achievement:** Polished streaming preview UI with eyeball toggle, transparency controls, resizable box.

**Features Added:**
- Eyeball toggle on orange bar (right side near timer) - show/hide preview
- Transparency +/- controls on preview box - affects background AND bubbles
- Resizable preview box with drag handle (WindowDragBlocker prevents window movement)
- Preview shows immediately when recording starts with "Listening..." placeholder
- Old content cleared when new recording starts

**Key Code:**
- `WindowDragBlocker` - NSViewRepresentable that overrides `mouseDownCanMoveWindow` to block window drag
- `@AppStorage` used for persisting visibility, opacity, width, height

---

## [2025-12-07] Phase 4 Complete - Streaming Preview UI with Parakeet Support

**Achievement:** Real-time chat-bubble streaming preview with chunk-commit system. Parakeet V3 works best.

**What Works:**
- Chat bubble UI shows transcription as you speak
- 1-second updates for responsive feedback
- 30-second commits lock bubbles in place (nothing disappears)
- Parakeet V3 streaming support added - faster than local Whisper
- Toggle moved to Settings → Experimental Features

**Key Parameters:**
- `streamingIntervalSeconds = 1.0` - update every second
- `chunkCommitIntervalSeconds = 30.0` - commit bubble every 30 seconds

**Recommendation:** Make Parakeet V3 the default model. It's fast enough for real-time streaming and produces excellent results.

**Files Modified:**
- `WhisperState.swift` - chunk-commit logic, Parakeet streaming support
- `MiniRecorderView.swift` - chat bubble UI
- `MiniRecorderPanel.swift` - larger window for bubbles
- `ParakeetTranscriptionService.swift` - added `transcribeSamples()` for streaming
- `ExperimentalFeaturesSection.swift` - streaming toggle moved here

---

## [2025-12-07] Streaming Transcription Working (Phase 1-3)

**Achievement:** Real-time streaming transcription every 3 seconds while recording.

**What Works:**
- AVAudioEngine captures audio → 16kHz mono buffer
- Timer fires every 3 seconds → runs whisper on last 10 seconds
- Interim results in ~1.7-1.9 seconds
- Sliding window keeps context rolling

**Sample Output:**
```
[12:10:43] Starting interim transcription with 54400 samples (3.40s)
[12:10:45] Interim result (1.67s): "Oh, right. Having a pants-pooping kind of time..."
[12:10:55] Starting interim transcription with 160000 samples (10.00s)
[12:10:57] Interim result (1.93s): "...Oh man, I'm actually seeing it. Yeah, it's really cool..."
```

**Key Parameters:**
- `streamingIntervalSeconds = 3.0` - transcribe every 3 seconds
- `streamingMaxAudioMs = 10000` - max 10 seconds of audio context

**Next:** Phase 4 (UI) or Phase 5 (voice commands)

---

## [2025-12-07] Streaming Audio Capture Working (Phase 1-2)

**Achievement:** AVAudioEngine captures real-time audio samples for streaming transcription.

**What We Built:**
- `StreamingRecorder.swift` - captures audio via AVAudioEngine instead of file-based AVAudioRecorder
- `StreamingLogger.swift` - file-based logging to `~/Library/Logs/WhisperVillage/streaming.log`
- Settings toggle in Audio Input → "Real-Time Streaming Mode"

**Key Technical Details:**
- Input: 48kHz (system mic) → Output: 16kHz mono Float32 (Whisper format)
- Resampling via linear interpolation
- Buffer accumulates samples with audio level detection
- Runs alongside existing Recorder (non-destructive)

**Proof It Works:**
```
Input format: 48000.0Hz → Target format: 16000.0Hz ✓
Buffer: 16000 samples (1.0s), level: 0.44  ← speaking detected
Buffer: 32000 samples (2.0s), level: 0.00  ← silence
Stopped. Returning 435200 samples (27.20 seconds) ✓
```

**Files Created:**
- `VoiceInk/Services/StreamingRecorder.swift`
- `VoiceInk/Services/StreamingLogger.swift`
- Modified `VoiceInk/Views/Settings/AudioInputSettingsView.swift` (toggle)
- Modified `VoiceInk/Whisper/WhisperState.swift` (integration)

**Next:** Phase 3 - run whisper_full() every 3 seconds on the buffer.

---

## [2025-12-07] Ship It Pipeline Working

**Achievement:** Figured out the complete release workflow with ad-hoc signing.

**The Problem:**
- "Apple Development" certificates only work on registered devices
- No Developer ID certificate exists
- Apps wouldn't run on other Macs

**The Solution:**
Ad-hoc signing removes provisioning profile requirements:
```bash
xcodebuild ... CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

**User Installation Requirement:**
Users must run after downloading:
```bash
xattr -cr /Applications/Whisper\ Village.app
```

**Full pipeline documented in CLAUDE.md under "Ship It Pipeline".**

---

## [2025-12-05] Word Replacement Regex Bug Fixed + Built-in I' Fix

**Achievement:** Fixed word replacements not matching patterns ending in apostrophes, and added permanent auto-fix for `I'` -> `I'm`.

**The Problem:**
- User configured word replacement `I'` -> `I'm` but it never worked
- Every user encounters this Whisper transcription error

**Root Cause:**
The regex `\bI'\b` fails because `\b` (word boundary) doesn't work after apostrophes.
- `\b` matches transition between word char (`[a-zA-Z0-9_]`) and non-word char
- `'` is non-word, space after is also non-word - no boundary exists
- So `\bI'\b` never matches `I' ` in actual text

**The Fix (2 parts):**

1. **Regex fix in `WordReplacementService.swift:22-29`:**
   - Detect when pattern ends with non-word char
   - Use lookahead `(?=\s|$)` instead of `\b` at end

2. **Built-in fixes in `WordReplacementService.swift:10-33`:**
   - Added `builtInFixes` array for common Whisper errors
   - Added `applyBuiltInFixes()` method that always runs
   - Currently fixes: `I'` -> `I'm`

**Key Insight:** To add more built-in fixes, just add patterns to the `builtInFixes` array.

---

## Project Facts

**App Name:** Whisper Village (rebranded from VoiceInk)
**Current Version:** v1.8.0
**Platform:** macOS
**Distribution:** GitHub Releases + Sparkle auto-updates
**DMG Size:** ~254MB (includes ~126MB CoreML models per model)

---

#!/bin/bash
# Test script for iTerm pane splitting
# Creates 4 terminal panes beneath HUD

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ============================================
# STEP 1: Blocking command test
# ============================================
echo "Running blocking command (sleep 2 seconds)..."
sleep 2
echo "Blocking command complete! Now creating panes..."

# ============================================
# STEP 2: Create terminal layout
# ============================================
# Layout:
# ┌─────────────────────────────────────────────┐
# │                    HUD                       │
# ├──────────┬──────────┬──────────┬────────────┤
# │ Pane 1   │ Pane 2   │ Pane 3   │  Pane 4    │
# └──────────┴──────────┴──────────┴────────────┘

osascript <<APPLESCRIPT
tell application "iTerm2"
    tell current session of current tab of current window
        -- Split horizontally (creates pane below)
        set pane1 to (split horizontally with default profile)
    end tell

    -- Pane 1
    tell pane1
        write text "cd '$REPO_DIR'"
        write text "echo '=== PANE 1 ==='"

        -- Split vertically to create pane 2
        set pane2 to (split vertically with default profile)
    end tell

    -- Pane 2
    tell pane2
        write text "cd '$REPO_DIR'"
        write text "echo '=== PANE 2 ==='"

        -- Split vertically to create pane 3
        set pane3 to (split vertically with default profile)
    end tell

    -- Pane 3
    tell pane3
        write text "cd '$REPO_DIR'"
        write text "echo '=== PANE 3 ==='"

        -- Split vertically to create pane 4
        set pane4 to (split vertically with default profile)
    end tell

    -- Pane 4
    tell pane4
        write text "cd '$REPO_DIR'"
        write text "echo '=== PANE 4 ==='"
    end tell
end tell
APPLESCRIPT

echo "Terminal layout created!"

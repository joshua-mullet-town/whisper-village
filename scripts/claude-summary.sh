#!/bin/bash

# Claude Summary Viewer - Shows the latest session summary for current project

# Check if we're in a project directory
if [ ! -f "CLAUDE.md" ] && [ ! -f ".claude/SUMMARY.txt" ]; then
    echo "❌ Not in a Claude Code project directory"
    echo "   (No CLAUDE.md or .claude/SUMMARY.txt found)"
    exit 1
fi

# Check if summary exists
if [ ! -f ".claude/SUMMARY.txt" ]; then
    echo "📝 No summary found for this project"
    echo "   (Summary hooks might not be installed or no sessions completed yet)"
    exit 1
fi

# Show the summary with nice formatting
echo "🧠 Latest Claude Code Session Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
cat .claude/SUMMARY.txt
echo ""

# Show file stats
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📅 Last updated: $(stat -f "%Sm" .claude/SUMMARY.txt)"
echo "📁 Project: $(basename "$PWD")"
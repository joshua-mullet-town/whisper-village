#!/usr/bin/env python3
"""
List all iTerm2 sessions and identify Claude Code instances.
Requires: iTerm2 → Preferences → General → Magic → Enable Python API
"""

import asyncio
import iterm2


async def main(connection):
    """List all sessions and identify Claude Code instances."""
    app = await iterm2.async_get_app(connection)

    print("\n" + "=" * 60)
    print("iTerm2 Session Discovery")
    print("=" * 60)

    claude_sessions = []
    all_sessions = []

    for window in app.terminal_windows:
        window_id = window.window_id
        print(f"\n📁 Window: {window_id}")

        for tab_idx, tab in enumerate(window.tabs):
            tab_id = tab.tab_id
            print(f"  📑 Tab {tab_idx}: {tab_id}")

            for session in tab.sessions:
                session_id = session.session_id

                # Get session variables
                try:
                    name = await session.async_get_variable("name") or "(unnamed)"
                    # Get the current command/job name
                    job_name = await session.async_get_variable("jobName") or ""
                    # Get terminal title
                    title = await session.async_get_variable("terminalTitle") or ""
                    # Get the path
                    path = await session.async_get_variable("path") or ""
                except Exception as e:
                    name = "(error getting name)"
                    job_name = ""
                    title = ""
                    path = ""

                session_info = {
                    "id": session_id,
                    "name": name,
                    "job": job_name,
                    "title": title,
                    "path": path,
                    "session": session
                }
                all_sessions.append(session_info)

                # Check if this looks like a Claude Code session
                # Claude Code sessions typically:
                # 1. Have "✳" in the name (Claude's task indicator)
                # 2. Run as python with descriptive task names
                # 3. May have "claude" in the name/title
                is_claude = False
                search_text = f"{name} {job_name} {title} {path}".lower()

                if "claude" in search_text:
                    is_claude = True
                elif "✳" in name:
                    # Claude Code uses ✳ prefix for active tasks
                    is_claude = True
                elif job_name in ["python", "python3", "python3.12", "python3.13"] and "(" in name:
                    # Pattern: "Task Name (python)" - typical Claude Code naming
                    is_claude = True

                if is_claude:
                    claude_sessions.append(session_info)

                marker = "🤖" if is_claude else "  "
                print(f"    {marker} Session: {session_id[:20]}...")
                print(f"       Name: {name}")
                if job_name:
                    print(f"       Job: {job_name}")
                if title:
                    print(f"       Title: {title}")
                if path:
                    print(f"       Path: {path}")

    print("\n" + "=" * 60)
    print(f"Total sessions: {len(all_sessions)}")
    print(f"Claude Code sessions detected: {len(claude_sessions)}")
    print("=" * 60)

    if claude_sessions:
        print("\n🤖 Claude Code Sessions:")
        for i, s in enumerate(claude_sessions):
            print(f"  [{i+1}] {s['name']} - {s['path']}")
    else:
        print("\n⚠️  No Claude Code sessions detected.")
        print("   Make sure you have 'claude' in the session name or title.")

    return claude_sessions


if __name__ == "__main__":
    print("Connecting to iTerm2...")
    print("(Make sure Python API is enabled: Preferences → General → Magic)")
    try:
        iterm2.run_until_complete(main)
    except Exception as e:
        print(f"\n❌ Error: {e}")
        print("\nTroubleshooting:")
        print("1. Is iTerm2 running?")
        print("2. Is Python API enabled? (Preferences → General → Magic)")
        print("3. Did you approve the connection dialog in iTerm2?")

#!/usr/bin/env python3
"""
Stream content from a Claude Code session in real-time.
Also supports sending input to the session.
"""

import asyncio
import sys
import iterm2


async def find_claude_sessions(app):
    """Find all Claude Code sessions."""
    sessions = []
    for window in app.terminal_windows:
        for tab in window.tabs:
            for session in tab.sessions:
                try:
                    name = await session.async_get_variable("name") or ""
                    path = await session.async_get_variable("path") or ""
                    job = await session.async_get_variable("jobName") or ""

                    # Detect Claude Code sessions
                    if "✳" in name or "claude" in name.lower():
                        sessions.append({
                            "session": session,
                            "name": name,
                            "path": path,
                            "job": job
                        })
                except:
                    pass
    return sessions


async def stream_session_content(session, duration=10):
    """Stream session content for a given duration."""
    print(f"\n📺 Streaming session content for {duration} seconds...")
    print("=" * 60)

    try:
        async with session.get_screen_streamer() as streamer:
            end_time = asyncio.get_event_loop().time() + duration

            while asyncio.get_event_loop().time() < end_time:
                content = await asyncio.wait_for(
                    streamer.async_get(),
                    timeout=1.0
                )

                if content:
                    # Print all lines
                    lines = []
                    for i in range(content.number_of_lines):
                        line = content.line(i)
                        lines.append(line.string)

                    # Clear and print current screen state
                    print("\033[2J\033[H", end="")  # Clear terminal
                    print(f"📺 Session: {await session.async_get_variable('name')}")
                    print("=" * 60)
                    for line in lines[-20:]:  # Show last 20 lines
                        print(line)
                    print("=" * 60)
                    print(f"⏱️  Streaming... {int(end_time - asyncio.get_event_loop().time())}s remaining")

    except asyncio.TimeoutError:
        pass
    except Exception as e:
        print(f"Streaming error: {e}")


async def get_session_snapshot(session):
    """Get a snapshot of the current session content."""
    try:
        line_info = await session.async_get_line_info()
        contents = await session.async_get_contents(
            line_info.first_visible_line_number,
            line_info.height
        )
        lines = [line.string for line in contents]
        return lines
    except Exception as e:
        print(f"Error getting snapshot: {e}")
        return []


async def send_text_to_session(session, text):
    """Send text to a session as if typed."""
    try:
        await session.async_send_text(text)
        print(f"✅ Sent: {repr(text)}")
        return True
    except Exception as e:
        print(f"❌ Error sending text: {e}")
        return False


async def main(connection):
    """Main entry point."""
    app = await iterm2.async_get_app(connection)

    # Find Claude Code sessions
    sessions = await find_claude_sessions(app)

    if not sessions:
        print("❌ No Claude Code sessions found.")
        return

    print("\n🤖 Claude Code Sessions:")
    for i, s in enumerate(sessions):
        print(f"  [{i+1}] {s['name']}")
        print(f"      Path: {s['path']}")

    # If only one session, use it
    if len(sessions) == 1:
        selected = sessions[0]
    else:
        # Let user pick
        try:
            choice = int(input("\nSelect session number: ")) - 1
            selected = sessions[choice]
        except (ValueError, IndexError):
            print("Invalid selection")
            return

    session = selected["session"]
    print(f"\n✅ Selected: {selected['name']}")

    # Demo: Get snapshot
    print("\n📸 Current screen snapshot:")
    print("-" * 40)
    lines = await get_session_snapshot(session)
    for line in lines[-15:]:  # Show last 15 lines
        print(line)
    print("-" * 40)

    # Demo: Stream for 5 seconds
    # await stream_session_content(session, duration=5)

    # Demo: Interactive mode
    print("\n💬 Interactive mode (type 'quit' to exit)")
    print("   Your input will be sent to the session")
    print("-" * 40)

    while True:
        try:
            user_input = input("Send> ")
            if user_input.lower() == "quit":
                break
            # Send with newline to execute
            await send_text_to_session(session, user_input + "\n")
            # Wait a moment for response
            await asyncio.sleep(0.5)
            # Show updated snapshot
            lines = await get_session_snapshot(session)
            print("\n--- Session output ---")
            for line in lines[-10:]:
                print(line)
            print("----------------------\n")
        except KeyboardInterrupt:
            break
        except EOFError:
            break

    print("\n👋 Done!")


if __name__ == "__main__":
    print("Connecting to iTerm2...")
    try:
        iterm2.run_until_complete(main)
    except Exception as e:
        print(f"\n❌ Error: {e}")

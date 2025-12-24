#!/usr/bin/env python3
"""
iTerm2 Bridge Daemon

JSON-based daemon for Swift app communication.
Accepts commands via stdin, responds via stdout.

Commands:
  {"cmd": "list_sessions"}
  {"cmd": "select_session", "session_id": "..."}
  {"cmd": "get_content"}
  {"cmd": "send_input", "text": "..."}
  {"cmd": "quit"}
"""

import asyncio
import json
import sys
import iterm2

# Global state
connection = None
app = None
selected_session = None
sessions_cache = {}


async def find_claude_sessions():
    """Find all Claude Code sessions."""
    global app, sessions_cache
    sessions_cache = {}
    result = []

    for window in app.terminal_windows:
        for tab in window.tabs:
            for session in tab.sessions:
                try:
                    name = await session.async_get_variable("name") or ""
                    path = await session.async_get_variable("path") or ""
                    job = await session.async_get_variable("jobName") or ""

                    # Detect Claude Code sessions
                    if "✳" in name or "claude" in name.lower():
                        session_id = session.session_id
                        sessions_cache[session_id] = session
                        result.append({
                            "id": session_id,
                            "name": name,
                            "path": path,
                            "job": job
                        })
                except:
                    pass
    return result


async def get_session_content():
    """Get current content from selected session."""
    global selected_session
    if not selected_session:
        return {"error": "No session selected"}

    try:
        line_info = await selected_session.async_get_line_info()
        num_lines = getattr(line_info, 'mutable_area_height', 24)
        first_line = getattr(line_info, 'first_visible_line_number', 0)

        contents = await selected_session.async_get_contents(first_line, num_lines)
        lines = []
        for line in contents:
            text = line.string if hasattr(line, 'string') else str(line)
            lines.append(text)

        return {
            "lines": lines,
            "num_lines": len(lines),
            "first_line": first_line
        }
    except Exception as e:
        return {"error": str(e)}


async def send_input(text):
    """Send text input to selected session."""
    global selected_session
    if not selected_session:
        return {"error": "No session selected"}

    try:
        await selected_session.async_send_text(text)
        return {"success": True}
    except Exception as e:
        return {"error": str(e)}


async def handle_command(cmd_data):
    """Handle a single command."""
    global selected_session, sessions_cache

    cmd = cmd_data.get("cmd", "")

    if cmd == "list_sessions":
        sessions = await find_claude_sessions()
        return {"sessions": sessions}

    elif cmd == "select_session":
        session_id = cmd_data.get("session_id", "")
        if session_id in sessions_cache:
            selected_session = sessions_cache[session_id]
            name = await selected_session.async_get_variable("name") or ""
            return {"success": True, "name": name}
        else:
            return {"error": f"Session not found: {session_id}"}

    elif cmd == "get_content":
        return await get_session_content()

    elif cmd == "send_input":
        text = cmd_data.get("text", "")
        return await send_input(text)

    elif cmd == "quit":
        return {"quit": True}

    else:
        return {"error": f"Unknown command: {cmd}"}


def send_response(data):
    """Send JSON response to stdout."""
    json_str = json.dumps(data)
    print(json_str, flush=True)


async def read_stdin_lines():
    """Async generator to read lines from stdin."""
    loop = asyncio.get_event_loop()
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)

    while True:
        line = await reader.readline()
        if not line:
            break
        yield line.decode().strip()


async def main_loop(conn):
    """Main daemon loop."""
    global connection, app
    connection = conn
    app = await iterm2.async_get_app(connection)

    send_response({"status": "ready", "message": "iTerm2 bridge daemon started"})

    async for line in read_stdin_lines():
        if not line:
            continue

        try:
            cmd_data = json.loads(line)
        except json.JSONDecodeError as e:
            send_response({"error": f"Invalid JSON: {e}"})
            continue

        response = await handle_command(cmd_data)
        send_response(response)

        if response.get("quit"):
            break


def main():
    """Entry point."""
    try:
        iterm2.run_until_complete(main_loop)
    except Exception as e:
        send_response({"error": f"Fatal error: {e}"})
        sys.exit(1)


if __name__ == "__main__":
    main()

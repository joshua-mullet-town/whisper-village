#!/usr/bin/env python3
"""
Test the daemon by sending commands and reading responses.
"""

import subprocess
import json
import sys
import time
import os

# Path to the daemon
DAEMON_PATH = os.path.join(os.path.dirname(__file__), "daemon.py")
VENV_PYTHON = os.path.join(os.path.dirname(__file__), "venv", "bin", "python")


def test_daemon():
    """Test the daemon with a sequence of commands."""
    print("Starting daemon...")

    # Start daemon as subprocess
    proc = subprocess.Popen(
        [VENV_PYTHON, DAEMON_PATH],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1
    )

    def send_cmd(cmd):
        """Send command and get response."""
        json_cmd = json.dumps(cmd)
        print(f"\n→ Sending: {json_cmd}")
        proc.stdin.write(json_cmd + "\n")
        proc.stdin.flush()

        response_line = proc.stdout.readline()
        if response_line:
            response = json.loads(response_line)
            print(f"← Response: {json.dumps(response, indent=2)}")
            return response
        return None

    try:
        # Wait for ready
        ready = proc.stdout.readline()
        print(f"Daemon ready: {ready.strip()}")

        # Test 1: List sessions
        print("\n" + "=" * 50)
        print("TEST 1: List sessions")
        print("=" * 50)
        result = send_cmd({"cmd": "list_sessions"})

        if result and result.get("sessions"):
            sessions = result["sessions"]
            print(f"\nFound {len(sessions)} Claude Code sessions")

            # Test 2: Select first session
            if sessions:
                print("\n" + "=" * 50)
                print("TEST 2: Select session")
                print("=" * 50)
                session_id = sessions[0]["id"]
                send_cmd({"cmd": "select_session", "session_id": session_id})

                # Test 3: Get content
                print("\n" + "=" * 50)
                print("TEST 3: Get content")
                print("=" * 50)
                content = send_cmd({"cmd": "get_content"})
                if content and content.get("lines"):
                    print(f"\nGot {len(content['lines'])} lines")
                    print("Last 5 lines:")
                    for line in content["lines"][-5:]:
                        print(f"  | {line[:60]}")

        # Test 4: Quit
        print("\n" + "=" * 50)
        print("TEST 4: Quit")
        print("=" * 50)
        send_cmd({"cmd": "quit"})

        proc.wait(timeout=2)
        print("\n✅ All tests passed!")

    except Exception as e:
        print(f"\n❌ Error: {e}")
        proc.kill()
        raise
    finally:
        if proc.poll() is None:
            proc.kill()


if __name__ == "__main__":
    test_daemon()

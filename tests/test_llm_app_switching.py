#!/usr/bin/env python3
"""
Test LLM-based application switching.
Proves that a local LLM can correctly interpret voice commands and choose the right app/tab.
"""

import subprocess
import json
import time
import urllib.request
import urllib.error

# Ollama API endpoint
OLLAMA_URL = "http://localhost:11434/api/generate"
MODEL = "llama3.2:3b"

def get_open_apps():
    """Get list of running foreground applications."""
    result = subprocess.run(
        ["osascript", "-e",
         'tell application "System Events" to get name of every process whose background only is false'],
        capture_output=True, text=True
    )
    apps = [app.strip() for app in result.stdout.split(",")]
    return apps

def get_iterm_tabs():
    """Get iTerm windows and tabs."""
    script = '''tell application "iTerm2"
        set output to ""
        set winNum to 1
        repeat with w in windows
            set tabNum to 1
            repeat with t in tabs of w
                set output to output & "Window " & winNum & ", Tab " & tabNum & ": " & (name of current session of t) & linefeed
                set tabNum to tabNum + 1
            end repeat
            set winNum to winNum + 1
        end repeat
        return output
    end tell'''
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    return result.stdout.strip()

def get_chrome_tabs():
    """Get Chrome windows and tabs."""
    script = '''tell application "Google Chrome"
        set output to ""
        set winNum to 1
        repeat with w in windows
            set tabNum to 1
            repeat with t in tabs of w
                set output to output & "Window " & winNum & ", Tab " & tabNum & ": " & (title of t) & linefeed
                set tabNum to tabNum + 1
            end repeat
            set winNum to winNum + 1
        end repeat
        return output
    end tell'''
    result = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    return result.stdout.strip()

def build_context():
    """Build the context string for the LLM."""
    apps = get_open_apps()
    iterm = get_iterm_tabs()
    chrome = get_chrome_tabs()

    context = f"""Available applications: {', '.join(apps)}

iTerm2 tabs:
{iterm}

Chrome tabs:
{chrome}"""
    return context

def ask_llm(user_command: str, context: str) -> dict:
    """Ask the LLM to interpret a voice command and return the action."""

    prompt = f"""You interpret voice commands to switch Mac applications.

CONTEXT:
{context}

EXAMPLES:
Command: "go to chrome" -> {{"action": "focus_app", "app_name": "Google Chrome"}}
Command: "switch to terminal" -> {{"action": "focus_app", "app_name": "iTerm2"}}
Command: "open finder" -> {{"action": "focus_app", "app_name": "Finder"}}
Command: "second terminal tab" -> {{"action": "focus_tab", "app_name": "iTerm2", "window": 1, "tab": 2}}
Command: "third chrome tab" -> {{"action": "focus_tab", "app_name": "Google Chrome", "window": 1, "tab": 3}}

RULES:
- "terminal" means iTerm2
- "browser" or "chrome" means Google Chrome
- Use exact app names from the list
- "second" = 2, "third" = 3

Command: "{user_command}"
JSON:"""

    start_time = time.time()

    data = json.dumps({
        "model": MODEL,
        "prompt": prompt,
        "stream": False,
        "options": {
            "temperature": 0.1,  # Low temperature for consistent output
            "num_predict": 100   # Short response
        }
    }).encode('utf-8')

    req = urllib.request.Request(OLLAMA_URL, data=data, headers={'Content-Type': 'application/json'})
    with urllib.request.urlopen(req) as response:
        result = json.loads(response.read().decode('utf-8'))

    elapsed = time.time() - start_time
    raw_response = result.get("response", "")

    # Try to parse JSON from response
    try:
        # Find JSON in response
        json_start = raw_response.find("{")
        json_end = raw_response.rfind("}") + 1
        if json_start >= 0 and json_end > json_start:
            json_str = raw_response[json_start:json_end]
            parsed = json.loads(json_str)
            parsed["_latency_ms"] = int(elapsed * 1000)
            parsed["_raw"] = raw_response
            return parsed
    except json.JSONDecodeError:
        pass

    return {"action": "error", "error": "Failed to parse", "_raw": raw_response, "_latency_ms": int(elapsed * 1000)}


def run_test(command: str, expected_action: str, expected_app: str = None, expected_tab: int = None):
    """Run a single test case."""
    context = build_context()
    result = ask_llm(command, context)

    latency = result.get("_latency_ms", 0)
    actual_action = result.get("action")
    actual_app = result.get("app_name")
    actual_tab = result.get("tab")

    # Check results
    passed = True
    issues = []

    if actual_action != expected_action:
        passed = False
        issues.append(f"action: got '{actual_action}', expected '{expected_action}'")

    if expected_app and actual_app != expected_app:
        passed = False
        issues.append(f"app_name: got '{actual_app}', expected '{expected_app}'")

    if expected_tab and actual_tab != expected_tab:
        passed = False
        issues.append(f"tab: got '{actual_tab}', expected '{expected_tab}'")

    status = "✓ PASS" if passed else "✗ FAIL"
    print(f"{status} [{latency}ms] \"{command}\"")
    if not passed:
        print(f"       Issues: {', '.join(issues)}")
        print(f"       Raw: {result.get('_raw', '')[:100]}")

    return passed


def main():
    print("=" * 60)
    print("LLM App Switching Tests")
    print("=" * 60)
    print()

    # First, show the context
    print("Current Context:")
    print("-" * 40)
    context = build_context()
    print(context[:500] + "..." if len(context) > 500 else context)
    print("-" * 40)
    print()

    # Run tests
    tests = [
        # Basic app switching
        ("go to chrome", "focus_app", "Google Chrome", None),
        ("open the browser", "focus_app", "Google Chrome", None),
        ("switch to terminal", "focus_app", "iTerm2", None),
        ("go to finder", "focus_app", "Finder", None),

        # Tab switching
        ("go to the second terminal tab", "focus_tab", "iTerm2", 2),
        ("focus the third iTerm tab", "focus_tab", "iTerm2", 3),

        # Ambiguous (should pick the most likely)
        ("open my email", "focus_app", "Google Chrome", None),  # Gmail is in Chrome

        # Natural language variations
        ("can you switch to slack", "focus_app", "Slack", None),
        ("pull up spotify", "focus_app", "Spotify", None),
        ("show me the notes app", "focus_app", "Notes", None),

        # Edge cases
        ("first terminal tab", "focus_tab", "iTerm2", 1),
        ("go to the commander tab", "focus_tab", "iTerm2", 2),  # Tab 2 has "commander" in name
    ]

    passed = 0
    failed = 0

    print("Running tests...")
    print()

    for command, expected_action, expected_app, expected_tab in tests:
        if run_test(command, expected_action, expected_app, expected_tab):
            passed += 1
        else:
            failed += 1

    print()
    print("=" * 60)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 60)


if __name__ == "__main__":
    main()

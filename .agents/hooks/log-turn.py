#!/usr/bin/env python3
"""Keeps this turn's log for the Stop hooks (turn.py), in Claude Code
and Antigravity alike.

- Claude Code UserPromptSubmit, or Antigravity PreInvocation whose
  lastUserInput differs from the logged prompt: starts a new turn. In
  Antigravity it also runs the vault's wiki reminder, which Claude Code
  runs as its own UserPromptSubmit hook; Antigravity has no per-prompt event.
- PostToolUse in either app: logs the call. Claude Code's subagents' calls
  are left out, as the transcript the hooks read before left them out.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import turn  # noqa: E402  (found through the line above)

WIKI_REMINDER = os.path.join(turn.REPO, "notes", ".tools", "wiki-reminder.sh")


def main():
    payload = json.load(sys.stdin)
    e = turn.Event(payload)
    if e.antigravity:
        if e.ours:
            if "toolCall" in payload:
                e.record(e.tool_call())
            elif payload.get("lastUserInput") != e.prompt():
                e.start_turn(payload.get("lastUserInput"))
                subprocess.run([WIKI_REMINDER], stdin=subprocess.DEVNULL)
        print("{}")
    elif payload.get("hook_event_name") == "UserPromptSubmit":
        e.start_turn(payload.get("prompt"))
    elif "agent_id" not in payload:
        e.record(e.tool_call())


main()

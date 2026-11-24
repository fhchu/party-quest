#!/usr/bin/env python3
"""Claude Code PostToolUse hook (matcher SubagentHandback) for party-quest.
Records which commit the reviewer subagent reviewed, for the reviewer gate in
before-bash.py. The reviewer ends its report with a last line

    REVIEWED <branch> <full sha> <base>

and this hook writes one file, named by the sha, holding "<branch> <base>"
in ~/.local/state/party-quest/reviewed/. The reviewer never writes the record
itself: auto mode blocks an agent signing off its own work. Anything that is
not the reviewer's report, or has no such last line, records nothing and the
gate keeps asking for a review.
"""
import json
import os
import re
import sys

STATE = os.path.expanduser("~/.local/state/party-quest/reviewed")
LAST_LINE = re.compile(r"REVIEWED (\S+) ([0-9a-f]{40}) (\S+)")


def main():
    payload = json.load(sys.stdin)
    if payload.get("agent_type") != "reviewer" or payload.get("tool_name") != "SubagentHandback":
        return
    message = payload.get("tool_input", {}).get("message", "")
    lines = [line.strip() for line in message.strip().splitlines()]
    found = LAST_LINE.fullmatch(lines[-1]) if lines else None
    if not found:
        print(json.dumps({"systemMessage": "Reviewer's report has no last line "
                          "'REVIEWED <branch> <full sha> <base>'; nothing recorded."}))
        return
    branch, sha, base = found.groups()
    os.makedirs(STATE, exist_ok=True)
    with open(os.path.join(STATE, sha), "w") as f:
        f.write(f"{branch} {base}\n")


main()

#!/usr/bin/env python3
"""Claude Code PostToolUse hook (Edit|Write) for party-quest: after an edit
to game/project.godot, reminds Claude that the owner's open Godot editor
won't pick it up and may save its own copy over it."""
import json
import os
import sys

payload = json.load(sys.stdin)
path = payload.get("tool_input", {}).get("file_path", "")
project = os.environ.get("CLAUDE_PROJECT_DIR", payload.get("cwd", "."))
project_godot = os.path.realpath(os.path.join(project, "game", "project.godot"))
if path and os.path.realpath(path) == project_godot:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": (
            "You edited game/project.godot. The owner's open Godot editor keeps project "
            "settings in memory and may write its copy back over this edit. Ask the owner "
            "to use Project → Reload Current Project, and check git diff on the file before "
            "committing."),
    }}))

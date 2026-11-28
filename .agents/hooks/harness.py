"""What a PreToolUse hook needs from either app that runs it: the shell
command it was handed, and a way to let it through or block it. Claude Code
(.claude/settings.json) and Antigravity (.agents/hooks.json) send different
JSON and read a block differently; the hooks here call this module instead.
"""
import json
import os
import sys


class ShellCall:
    """A shell command an agent is about to run."""

    def __init__(self, payload):
        # Antigravity sends toolCall; Claude Code sends tool_input.
        self.antigravity = "toolCall" in payload
        if self.antigravity:
            args = payload["toolCall"].get("args", {})
            if not payload.get("workspacePaths") or "CommandLine" not in args:
                # Unchecked, the command would pass every guard.
                self.block("Blocked: the guard hook couldn't find workspacePaths and "
                           "toolCall.args.CommandLine in Antigravity's hook input. Tell the "
                           "owner; .agents/hooks/harness.py needs updating.")
            workspace = payload["workspacePaths"][0]
            self.command = args["CommandLine"]
            # A run_command without Cwd runs in the workspace.
            self.cwd = args.get("Cwd") or workspace
            self.project = workspace
        else:
            self.command = payload.get("tool_input", {}).get("command", "")
            self.cwd = payload.get("cwd") or os.getcwd()
            self.project = os.environ.get("CLAUDE_PROJECT_DIR", self.cwd)

    def block(self, reason):
        """Stop the command and show the agent why."""
        if self.antigravity:
            print(json.dumps({"decision": "deny", "reason": reason}))
            sys.exit(0)
        print(reason, file=sys.stderr)
        sys.exit(2)

    def allow(self, note=None):
        """Let the command run, with an optional note for the agent."""
        if self.antigravity:
            print(json.dumps({"decision": "allow", **({"reason": note} if note else {})}))
        elif note:
            print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                     "additionalContext": note}}))
        sys.exit(0)


def shell_call():
    return ShellCall(json.load(sys.stdin))

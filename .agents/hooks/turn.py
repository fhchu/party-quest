"""This turn's tool calls, kept the same way under Claude Code and
Antigravity, for the Stop hooks. log-turn.py writes the log from
each app's prompt and tool hooks; the Stop hooks read it here and answer
through Stop. Antigravity's transcript format isn't documented, so the
hooks read this log in both apps instead of either transcript.

A call is {"tool": "edit" | "read" | "shell" | <the app's own name>,
"path": ..., "command": ..., "text": <its whole input as JSON>}.
"""
import json
import os
import subprocess
import sys
import time


def _main_checkout():
    """The repo's main checkout, found from this file's own checkout, which
    may be a worktree."""
    common = subprocess.run(
        ["git", "-C", os.path.dirname(os.path.abspath(__file__)), "rev-parse",
         "--path-format=absolute", "--git-common-dir"],
        capture_output=True, text=True, check=True).stdout.strip()
    return os.path.dirname(common)


REPO = _main_checkout()
LOGS = os.path.expanduser("~/.local/state/party-quest/turns")
# The app's own tool names for an edit, a read and a shell command, and the
# input field each keeps the path or command in.
EDITS = {"Edit": "file_path", "Write": "file_path", "MultiEdit": "file_path",
         "NotebookEdit": "file_path", "write_to_file": "TargetFile",
         "replace_file_content": "TargetFile", "multi_replace_file_content": "TargetFile"}
READS = {"Read": "file_path", "view_file": "AbsolutePath"}
SHELLS = {"Bash": "command", "run_command": "CommandLine"}


class Event:
    """One hook call from either app."""

    def __init__(self, payload):
        self.payload = payload
        # Antigravity sends conversationId; Claude Code sends session_id.
        self.antigravity = "conversationId" in payload
        if self.antigravity:
            self.session = payload["conversationId"]
            self.cwd = payload["workspacePaths"][0]
            self.project = self.cwd
        else:
            self.session = payload.get("session_id", "")
            self.cwd = payload.get("cwd", "")
            self.project = os.environ.get("CLAUDE_PROJECT_DIR", self.cwd or ".")
        self.log = os.path.join(LOGS, self.session + ".jsonl")
        # Antigravity runs its global hooks in every workspace; Claude Code
        # runs these only from this repo's local settings.
        self.ours = not self.antigravity or in_repo(self.cwd)

    def tool_call(self):
        """The call a PostToolUse hook reports, as a log entry."""
        if self.antigravity:
            name = self.payload["toolCall"]["name"]
            args = self.payload["toolCall"].get("args", {})
        else:
            name = self.payload.get("tool_name", "")
            args = self.payload.get("tool_input", {})
        entry = {"tool": name, "text": json.dumps(args)}
        for kind, fields, key in (("edit", EDITS, "path"), ("read", READS, "path"),
                                  ("shell", SHELLS, "command")):
            if name in fields:
                entry.update({"tool": kind, key: args.get(fields[name], "")})
        return entry

    def start_turn(self, prompt):
        os.makedirs(LOGS, exist_ok=True)
        with open(self.log, "w") as f:
            f.write(json.dumps({"start": time.time(), "prompt": prompt}) + "\n")

    def record(self, entry):
        if os.path.exists(self.log):
            with open(self.log, "a") as f:
                f.write(json.dumps(entry) + "\n")

    def _entries(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log) as f:
            return [json.loads(line) for line in f if line.strip()]

    def turn(self):
        """(when the owner's last message came, as a Unix time, or None;
        the tool calls since, in order)."""
        entries = self._entries()
        if not entries:
            return None, []
        return entries[0]["start"], [e for e in entries[1:] if "tool" in e]

    def prompt(self):
        entries = self._entries()
        return entries[0]["prompt"] if entries else None

    def stop_blocked_before(self):
        """True when a Stop hook already kept this turn going once."""
        if not self.antigravity:
            return bool(self.payload.get("stop_hook_active"))
        return any(e.get("kept_going") for e in self._entries())

    def keep_going(self, reason):
        """End the hook, telling the agent to carry on and why."""
        if self.antigravity:
            self.record({"kept_going": True})
            print(json.dumps({"decision": "continue", "reason": reason}))
            sys.exit(0)
        print(reason, file=sys.stderr)
        sys.exit(2)

    def let_stop(self, message=None):
        """End the hook, letting the turn end. Claude Code shows the owner
        message; Antigravity's Stop has no way to."""
        if self.antigravity:
            print(json.dumps({"decision": "stop"}))
        elif message:
            print(json.dumps({"systemMessage": message}))
        sys.exit(0)


def in_repo(path):
    """True when path is in the repo's main checkout or one of its worktrees."""
    common = ["rev-parse", "--path-format=absolute", "--git-common-dir"]
    out = [subprocess.run(["git", "-C", p, *common], capture_output=True, text=True).stdout
           for p in (path, REPO)]
    return bool(out[0].strip()) and out[0] == out[1]


def event():
    """The Stop hook's event; lets the turn end at once outside this repo."""
    e = Event(json.load(sys.stdin))
    if not e.ours:
        e.let_stop()
    return e

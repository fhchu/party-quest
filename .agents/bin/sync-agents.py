"""Writes Claude Code's copy of each agent in .agents/agents/ to
.claude/agents/. The .agents/ file is the one to edit: Antigravity reads it
as is, and Claude Code needs its own tool and model names.

    python3 .agents/bin/sync-agents.py          write the copies
    python3 .agents/bin/sync-agents.py --check  fail if a copy is out of date
"""
import os
import re
import sys

SOURCE = ".agents/agents"
TARGET = ".claude/agents"
# Antigravity's tool names, and Claude Code's for the same tool.
TOOLS = {
    "view_file": "Read",
    "grep_search": "Grep",
    "find_by_name": "Glob",
    "list_dir": "Glob",
    "run_command": "Bash",
}
FRONTMATTER = re.compile(r"---\n(.*?)\n---\n", re.DOTALL)


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def claude_copy(name, text):
    """The Claude Code agent file for the Antigravity agent file text."""
    found = FRONTMATTER.match(text)
    if not found:
        fail(f"{SOURCE}/{name} has no frontmatter")
    lines = [f"# Written by .agents/bin/sync-agents.py from {SOURCE}/{name}; edit that."]
    for line in found.group(1).splitlines():
        key, _, value = line.partition(": ")
        if key == "tools":
            names = [tool.strip() for tool in value.strip("[]").split(",")]
            unknown = [tool for tool in names if tool not in TOOLS]
            if unknown:
                fail(f"{SOURCE}/{name}: no Claude Code tool for {', '.join(unknown)}")
            value = ", ".join(dict.fromkeys(TOOLS[tool] for tool in names))
        elif key == "model":
            # Antigravity's other models have no Claude Code counterpart.
            if value != "inherit":
                fail(f"{SOURCE}/{name}: no Claude Code model for {value}")
        elif key not in ("name", "description"):
            fail(f"{SOURCE}/{name}: no Claude Code key for {key}")
        lines.append(f"{key}: {value}")
    return "---\n" + "\n".join(lines) + "\n---\n" + text[found.end():]


def main():
    check = sys.argv[1:] == ["--check"]
    stale = []
    for name in sorted(os.listdir(SOURCE)):
        with open(os.path.join(SOURCE, name)) as f:
            want = claude_copy(name, f.read())
        path = os.path.join(TARGET, name)
        try:
            with open(path) as f:
                have = f.read()
        except FileNotFoundError:
            have = None
        if have == want:
            continue
        if check:
            stale.append(path)
            continue
        os.makedirs(TARGET, exist_ok=True)
        with open(path, "w") as f:
            f.write(want)
    if stale:
        fail(f"out of date: {', '.join(stale)}. Run python3 .agents/bin/sync-agents.py")
    print("agents in sync")


main()

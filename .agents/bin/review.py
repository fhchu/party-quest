"""Runs the reviewer agent (.agents/agents/reviewer.md) on one branch and
records the review for the reviewer gate in .agents/hooks/before-bash.py.

    python3 .agents/bin/review.py WORKTREE BRANCH BASE [PREVIOUS_SHA]

PREVIOUS_SHA makes it a re-review of the changes since that review. The
reviewer runs headless in the app that runs this script: Claude Code's
claude when called from Claude Code, else Antigravity's agy. Its report
goes to stdout. A report whose last line is LINE_FORMAT, naming BRANCH and
BASE, is recorded in STATE as one file named by the sha, holding
"<branch> <base>", and the whole report beside it, named by the sha plus
REPORT_SUFFIX. Anything else records nothing and exits non-zero.

The record comes from the reviewer's own output, so neither the reviewer
nor the session that wants the review writes it.
"""
import os
import re
import subprocess
import sys

STATE = os.path.expanduser("~/.local/state/party-quest/reviewed")
REPORT_SUFFIX = ".md"
# The reviewer's instructions (.agents/agents/reviewer.md) quote it.
LINE_FORMAT = "REVIEWED <branch> <full sha> <base>"
LAST_LINE = re.compile(LINE_FORMAT
                       .replace("<branch>", r"(\S+)")
                       .replace("<full sha>", r"([0-9a-f]{40})")
                       .replace("<base>", r"(\S+)"))


def fail(message):
    print(message, file=sys.stderr)
    sys.exit(1)


def reviewer_command(worktree, prompt):
    """The headless reviewer run for the app this script was called from."""
    if os.environ.get("CLAUDECODE"):
        # Headless runs get no permission prompts, so the reviewer's reads
        # are allowed up front.
        allowed = ["Read", "Grep", "Glob", "Bash(git *)", "Bash(grep *)",
                   f"Bash({worktree}/.agents/bin/review-context.sh *)"]
        return [os.environ.get("CLAUDE_CODE_EXECPATH", "claude"), "-p", prompt,
                "--agent", "reviewer", "--allowedTools", *allowed]
    # Antigravity's headless runs read their allowed commands from the
    # user's settings.
    return ["agy", "-p", prompt, "--agent", "reviewer"]


def main():
    if len(sys.argv) not in (4, 5):
        fail("Usage: review.py WORKTREE BRANCH BASE [PREVIOUS_SHA]")
    worktree, branch, base = os.path.abspath(sys.argv[1]), sys.argv[2], sys.argv[3]
    prompt = f"Review branch {branch} against base {base} in the worktree {worktree}."
    if len(sys.argv) == 5:
        previous = sys.argv[4]
        prompt += (f" This is a re-review: the previous review is {previous}, its report "
                   f"{os.path.join(STATE, previous + REPORT_SUFFIX)}.")
    run = subprocess.run(reviewer_command(worktree, prompt), cwd=worktree,
                         capture_output=True, text=True)
    report = run.stdout.strip()
    print(report)
    if run.returncode != 0:
        fail(f"The reviewer exited {run.returncode}; nothing recorded.\n{run.stderr}")
    lines = report.splitlines()
    found = LAST_LINE.fullmatch(lines[-1].strip()) if lines else None
    if not found or found.group(1) != branch or found.group(3) != base:
        fail(f"The report's last line isn't '{LINE_FORMAT}' for {branch} and {base}; "
             "nothing recorded.")
    sha = found.group(2)
    os.makedirs(STATE, exist_ok=True)
    with open(os.path.join(STATE, sha + REPORT_SUFFIX), "w") as f:
        f.write(report + "\n")
    with open(os.path.join(STATE, sha), "w") as f:
        f.write(f"{branch} {base}\n")


main()

#!/usr/bin/env python3
"""PreToolUse hook on shell commands for party-quest, run by Claude Code and
Antigravity alike (harness.py speaks each one's JSON).

- Blocks pkill and killall: matching by pattern also kills the owner's dev.sh.
- Blocks git commit on main in this repo (any worktree of it).
- Blocks `gh pr create`, and a `git push` to a branch with an open PR,
  until the reviewer agent has reviewed the branch's tip. A tip whose
  changes since the last review only fix that review's nits, inside the
  spans it gave, passes. After MAX_REVIEWS_PER_BRANCH reviews of a branch
  the gate lets it through and tells the agent to list the open findings in
  the PR. Blocks `git push --all` and `--mirror`, which would get past
  that check.
- Before any other commit in this repo: blocks the commit unless
  scripts/check.sh last passed on exactly these files, with its size check
  measured from the same commit and SIZE_OK the same: what it recorded
  then against what `scripts/check.sh --pass-record` prints now. The size check's
  base is a `BASE=<ref>` in the command if there is one, else the base of
  the branch's open PR, else check.sh's own default. A `SIZE_OK=1` in the
  command means the run must have had it too (mechanical changes only; the
  PR description says why).
  Skipped when every changed file in the checkout is a .md file.

Commits in other repos pass untouched.

The checks catch an agent's ordinary commands, not ones written to get
past them. They don't look inside `bash -c "..."`, `eval`, a script file
or a function. A command can also slip past them when:
- a quote spanning lines holds a `<<WORD`, or hides a heredoc start or a
  command;
- a heredoc is opened inside backticks within double quotes;
- a `#` comment holds a `<<WORD`;
- an ANSI-C string (`$'...'`) holds an escaped quote;
- a heredoc's delimiter isn't a single word (`<<'EOF-1'`).
"""
import datetime
import json
import os
import re
import shlex
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import harness  # noqa: E402  (found through the line above)

CALL = harness.shell_call()


def block(reason):
    CALL.block(reason)


def git(path, *args, must_succeed=False):
    """git's output, stripped; "" when it fails, or a block when
    must_succeed."""
    out = subprocess.run(["git", "-C", path, *args], capture_output=True, text=True)
    if out.returncode != 0 and must_succeed:
        block(f"Blocked: git {' '.join(args)} failed.\n{out.stderr}")
    return out.stdout.strip() if out.returncode == 0 else ""


def docs_only(path):
    """True when the checkout at path changes only .md files: staged,
    unstaged and untracked ones all count, since the command may add them
    before it commits. False when nothing changed."""
    changed = (git(path, "diff", "HEAD", "--name-only", "--no-renames").split("\n")
               + git(path, "ls-files", "--others", "--exclude-standard").split("\n"))
    changed = [name for name in changed if name]
    return bool(changed) and all(name.endswith(".md") for name in changed)


HEREDOC_START = re.compile(r"<<(-?)\s*\\?(['\"]?)(\w+)\2")


def heredoc_starts(line):
    """(strip_tabs, delimiter) for each heredoc line opens: a `<<` where the
    shell reads commands (outside quotes, or inside a $(...) even within
    double quotes), not inside $((...)) and not a `<<<` here-string. Quotes
    are tracked within the line only."""
    # Each entry is a context the scan is inside: a quote character, "$("
    # for a command, "((" for arithmetic, or "a(" for a bracket within it.
    starts, stack, i = [], [], 0
    while i < len(line):
        top = stack[-1] if stack else None
        c = line[i]
        if top == "'":
            if c == "'":
                stack.pop()
            i += 1
            continue
        if c == "\\":
            i += 2
            continue
        if line.startswith("$((", i) or (top != '"' and line.startswith("((", i)):
            stack.append("((")
            i += 3 if c == "$" else 2
            continue
        if line.startswith("$(", i):
            stack.append("$(")
            i += 2
            continue
        if top == '"':
            if c == '"':
                stack.pop()
            i += 1
            continue
        if top in ("((", "a("):
            if c == "(":
                stack.append("a(")
            elif top == "a(" and c == ")":
                stack.pop()
            elif top == "((" and line.startswith("))", i):
                stack.pop()
                i += 1
            i += 1
            continue
        # Where the shell reads commands: top level or inside $(...).
        if c in "'\"":
            stack.append(c)
        elif c == ")" and top == "$(":
            stack.pop()
        elif line.startswith("<<<", i):
            i += 3
            continue
        elif m := HEREDOC_START.match(line, i):
            starts.append((m.group(1) == "-", m.group(3)))
            i = m.end()
            continue
        i += 1
    return starts


def without_heredocs(command):
    """command with every heredoc's body left out. A body is text, not shell:
    an apostrophe in it (a commit message's "it's") would otherwise make
    shlex fail on the whole command."""
    out, delimiters = [], []
    for line in command.split("\n"):
        if delimiters:
            strip_tabs, word = delimiters[0]
            if (line.lstrip("\t") if strip_tabs else line) == word:
                delimiters.pop(0)
            continue
        out.append(line)
        delimiters = heredoc_starts(line)
    return "\n".join(out)


BASE_IN_COMMAND = re.compile(r"(?:^|[\s;&|])BASE=([^\s;&|]+)")
SIZE_OK_IN_COMMAND = re.compile(r"(?:^|[\s;&|])SIZE_OK=1(?=[\s;&|]|$)")


def size_base(command, target):
    """The ref check.sh's size check should measure against, or None for
    its default. A stacked branch's PR has its parent as its base."""
    given = BASE_IN_COMMAND.search(command)
    if given:
        return given.group(1)
    out = subprocess.run(["gh", "pr", "view", "--json", "baseRefName", "-q", ".baseRefName"],
                         cwd=target, capture_output=True, text=True)
    base = out.stdout.strip()
    if out.returncode != 0 or not base:
        return None
    return "origin/" + base


# The shell's operators, longest first: shlex returns a run of punctuation
# as one token (`&&>`), which split_operators breaks back into these.
OPERATORS = sorted(["&&", "||", ";;", "|&", "<<<", "<<-", "<<", ">>", "&>>", "&>", ">&",
                    "<&", ">|", "<>", ";", "&", "|", "(", ")", "\n", "<", ">"],
                   key=len, reverse=True)


def split_operators(run):
    """run, a token of punctuation only, as the operators it holds."""
    out = []
    while run:
        op = next((o for o in OPERATORS if run.startswith(o)), run[0])
        out.append(op)
        run = run[len(op):]
    return out


def shell_tokens(command):
    """command split into words, with newlines, ;, &&, | and the like as
    tokens of their own even with no space around them, and redirections
    left out (`2>&1`, `> log`): the operator, its target, and a number just
    before it, read as its file descriptor. A quoted lone operator (`'>'`)
    is read as a redirection too, since shlex drops the quotes. None for
    unbalanced quotes, which the shell refuses too."""
    # A backslash before a newline continues the line, and a backtick
    # starts or ends a command of its own.
    command = command.replace("\\\n", " ").replace("`", " ; ")
    lex = shlex.shlex(command, posix=True,
                      punctuation_chars="();<>|&\n")
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    try:
        raw = [piece for tok in lex
               for piece in (split_operators(tok) if set(tok) <= set("();<>|&\n") else [tok])]
    except ValueError:
        return None
    tokens, skip_target = [], False
    for tok in raw:
        if skip_target:
            skip_target = False
            # A redirection with no target before the next command.
            if not control(tok):
                continue
        if set(tok) <= set("<>&|") and set(tok) & set("<>"):
            if tokens and tokens[-1].isdigit():
                tokens.pop()
            skip_target = True
        else:
            tokens.append(tok)
    return tokens


def command_words(tokens):
    """The program name of each simple command in tokens (after a newline,
    ;, &&, | and the like, skipping sudo and VAR=value)."""
    words, expect = [], True
    for tok in tokens:
        if control(tok):
            expect = True
        elif expect and (tok == "sudo" or re.fullmatch(r"\w+=.*", tok)):
            continue
        elif expect:
            words.append(os.path.basename(tok))
            expect = False
    return words


def in_repo(path, ours):
    rel = git(path, "rev-parse", "--git-common-dir")
    return bool(rel) and os.path.realpath(os.path.join(path, rel)) == ours


REVIEWED_DIR = os.path.expanduser("~/.local/state/party-quest/reviewed")
REPORT_SUFFIX = ".md"
# Bounds what one branch can spend on reviews; past it, the owner reads the
# open findings in the PR instead.
MAX_REVIEWS_PER_BRANCH = 5
# The reviewer's instructions (.agents/agents/reviewer.md) quote both.
BLOCKING_TAG = "[blocking]"
NIT_FORMAT = "[nit] <path>:<first line>-<last line>"
NIT_LINE = re.compile(re.escape(NIT_FORMAT)
                      .replace(re.escape("<path>"), r"(?P<path>\S+)")
                      .replace(re.escape("<first line>"), r"(?P<first>\d+)")
                      .replace(re.escape("<last line>"), r"(?P<last>\d+)"))
# A -U0 hunk header: the old side's first line and line count (1 if left
# out; 0 for lines added after that line).
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? ")
# Options before the verb that need a separate value: git's. gh has none
# of these before its verb.
OPTIONS_WITH_VALUE = ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env")
MAIN_REFS = ("main", "origin/main")


def control(token):
    """True for a token that ends a simple command (a newline, ;, &&, | and
    the like)."""
    return bool(token) and set(token) <= set("\n;&|()")


def run_dir(tokens, here, program, verb):
    """(directory, tokens after verb up to the end of that command) for the
    first `<program> <verb>` in tokens, following cd and git -C on the way
    and skipping other options before the verb; None if there isn't one.
    program matches by name, so a full path to it counts."""
    for i, tok in enumerate(tokens):
        if tok == "cd" and i + 1 < len(tokens) and not control(tokens[i + 1]):
            here = os.path.join(here, os.path.expanduser(tokens[i + 1]))
        if os.path.basename(tok) == program:
            j, target = i + 1, here
            while j < len(tokens) and tokens[j].startswith("-"):
                if tokens[j] == "-C" and j + 1 < len(tokens):
                    target = os.path.join(here, os.path.expanduser(tokens[j + 1]))
                j += 2 if tokens[j] in OPTIONS_WITH_VALUE else 1
            if tuple(tokens[j:j + len(verb)]) == verb:
                rest = tokens[j + len(verb):]
                end = next((k for k, tok in enumerate(rest) if control(tok)), len(rest))
                return target, rest[:end]
    return None


def has_open_pr(target, branch):
    """True unless gh says the branch has no open PR. A lookup that fails
    any other way counts as open, so the gate asks for a review."""
    out = subprocess.run(["gh", "pr", "view", branch, "--json", "state", "-q", ".state"],
                         cwd=target, capture_output=True, text=True)
    if out.returncode == 0:
        return out.stdout.strip() == "OPEN"
    return "no pull requests found" not in out.stderr.lower()


def push_branches(args, target):
    """The branches a `git push` with args pushes, or None for a push the
    gate lets through (tags, deleting a branch)."""
    flags = [a for a in args if a.startswith("-")]
    if {"--delete", "-d"} & set(flags):
        return None
    if {"--all", "--mirror"} & set(flags):
        block("Blocked: git push --all and --mirror skip the reviewer gate. "
              "Push each branch by name.")
    positional = [a for a in args if not a.startswith("-")]
    current = git(target, "branch", "--show-current")
    refspecs = positional[1:]
    if not refspecs:
        return [current] if current else []
    branches = []
    for spec in refspecs:
        if spec.startswith(":") or spec.startswith("refs/tags/") or spec.startswith("+:"):
            continue
        name = spec.lstrip("+").split(":")[-1] if ":" in spec else spec.lstrip("+")
        name = name.removeprefix("refs/heads/")
        branches.append(current if name == "HEAD" else name)
    return branches


def records():
    """(sha, branch, base) for each review record."""
    if not os.path.isdir(REVIEWED_DIR):
        return []
    found = []
    for sha in os.listdir(REVIEWED_DIR):
        if not re.fullmatch(r"[0-9a-f]{40}", sha):
            continue
        try:
            branch, base = open(os.path.join(REVIEWED_DIR, sha)).read().split()
        except ValueError:
            continue
        found.append((sha, branch, base))
    return found


def reviewed(target, branch):
    """True if a recorded review covers the tip of branch: the reviewed commit
    is the tip itself, or contains it and was reviewed against main (so the
    review's diff included the tip's changes)."""
    tip = git(target, "rev-parse", "--verify", "-q", branch + "^{commit}")
    if not tip:
        return False
    for sha, _, base in records():
        if sha == tip:
            return True
        contains = subprocess.run(["git", "-C", target, "merge-base", "--is-ancestor", tip, sha],
                                  capture_output=True).returncode == 0
        if contains and base in MAIN_REFS:
            return True
    return False


def branch_records(branch):
    """The shas of branch's recorded reviews, oldest first."""
    shas = [sha for sha, reviewed_branch, _ in records() if reviewed_branch == branch]
    return sorted(shas, key=lambda sha: os.path.getmtime(os.path.join(REVIEWED_DIR, sha)))


# Each PR of a branch name, with the last time it closed (a merge closes
# it too). GitHub clears a reopened PR's closedAt, so it comes from the
# timeline instead.
LAST_CLOSES = """query($owner: String!, $name: String!, $branch: String!) {
  repository(owner: $owner, name: $name) {
    pullRequests(headRefName: $branch, first: 100) {  # GitHub's largest page; more PRs of one name are unlikely
      nodes { timelineItems(itemTypes: [CLOSED_EVENT], last: 1) {
        nodes { ... on ClosedEvent { createdAt } } } }
    }
  }
}"""


def drop_stale_records(target, branch):
    """Deletes branch's records written before any PR of that name last
    closed or merged: they belong to an earlier branch with the same name,
    or to a PR closed and reopened since, whose count starts over."""
    out = subprocess.run(["gh", "api", "graphql", "-F", "owner={owner}", "-F", "name={repo}",
                          "-f", f"branch={branch}", "-f", f"query={LAST_CLOSES}"],
                         cwd=target, capture_output=True, text=True)
    if out.returncode != 0:
        block(f"Blocked: gh couldn't list {branch}'s PRs, so its review count is unknown.\n"
              + out.stderr)
    prs = json.loads(out.stdout)["data"]["repository"]["pullRequests"]["nodes"]
    closed = [datetime.datetime.fromisoformat(event["createdAt"].replace("Z", "+00:00")).timestamp()
              for pr in prs for event in pr["timelineItems"]["nodes"]]
    if not closed:
        return
    for sha in branch_records(branch):
        path = os.path.join(REVIEWED_DIR, sha)
        if os.path.getmtime(path) < max(closed):
            os.remove(path)
            if os.path.exists(path + REPORT_SUFFIX):
                os.remove(path + REPORT_SUFFIX)


def nit_fixes_only(target, sha, tip):
    """True when the review of sha found nothing blocking and every line
    changed since sha lies inside a span one of its nits gave. The diff's
    old-side line numbers are sha's own, the ones the spans name."""
    report_path = os.path.join(REVIEWED_DIR, sha + REPORT_SUFFIX)
    if not os.path.isfile(report_path):
        return False
    report = open(report_path).read()
    if BLOCKING_TAG in report:
        return False
    spans = {}
    for nit in NIT_LINE.finditer(report):
        spans.setdefault(nit["path"], []).append((int(nit["first"]), int(nit["last"])))
    changed = set(git(target, "diff", "--name-only", "--no-renames", sha, tip,
                      must_succeed=True).split("\n"))
    changed.discard("")
    covered, old_path = set(), None
    diff = git(target, "diff", "-U0", "--no-renames", "--no-ext-diff", sha, tip, must_succeed=True)
    for line in diff.split("\n"):
        if line.startswith("--- "):
            old_path = line.removeprefix("--- a/") if line.startswith("--- a/") else None
        elif hunk := HUNK.match(line):
            first = int(hunk[1])
            last = first + max(int(hunk[2] or 1), 1) - 1
            if not any(start <= first and last <= end for start, end in spans.get(old_path, [])):
                return False
            covered.add(old_path)
    # A changed file with no hunk (binary, mode only) is never covered.
    return changed <= covered


def reviewer_gate(tokens, cwd, ours):
    """Blocks `gh pr create` and a `git push` to a branch with an open PR
    until the reviewer has reviewed the branch's tip. Commits aren't gated:
    a review needs the commit to exist."""
    creating = run_dir(tokens, cwd, "gh", ("pr", "create"))
    pushing = None if creating else run_dir(tokens, cwd, "git", ("push",))
    found = creating or pushing
    if not found:
        return
    target, args = found
    if not os.path.isdir(target) or not in_repo(target, ours):
        return
    if creating:
        head = next((args[i + 1] for i, a in enumerate(args[:-1]) if a in ("--head", "-H")), "")
        branches = [head.split(":")[-1] or git(target, "branch", "--show-current")] if head \
            else [git(target, "branch", "--show-current")]
    else:
        branches = [b for b in (push_branches(args, target) or [])
                    if has_open_pr(target, b)]
    capped = []
    for branch in branches:
        if not branch or reviewed(target, branch):
            continue
        drop_stale_records(target, branch)
        review_shas = branch_records(branch)
        if len(review_shas) >= MAX_REVIEWS_PER_BRANCH:
            capped.append((branch, review_shas[-1]))
            continue
        tip = git(target, "rev-parse", branch)
        previous = next((sha for sha in reversed(review_shas) if subprocess.run(
            ["git", "-C", target, "merge-base", "--is-ancestor", sha, tip],
            capture_output=True).returncode == 0), None)
        if previous and nit_fixes_only(target, previous, tip):
            continue
        count = f"This will be review {len(review_shas) + 1} of {MAX_REVIEWS_PER_BRANCH}."
        if previous:
            block(f"Blocked: {branch} at {tip[:7]} changed since its last review "
                  f"({previous[:7]}). Run `python3 .agents/bin/review.py <worktree> {branch} "
                  f"<base> {previous}` in the background (a review runs for minutes), wait "
                  f"for its report, fix every finding, then run this again. {count}")
        block(f"Blocked: {branch} at {tip[:7]} hasn't been through the reviewer. Run "
              f"`python3 .agents/bin/review.py <worktree> {branch} <base>` in the background "
              "(a review runs for minutes), wait for its report, fix every finding, then run "
              "this again. For a stack, review the top branch against main: that one review "
              f"covers every branch beneath it. {count}")
    if capped:
        notes = [f"{branch} has had {MAX_REVIEWS_PER_BRANCH} reviews, so this goes through "
                 "without another. Add a \"Findings left open\" section to its PR description "
                 "(gh pr edit) listing what its last review found that is still open: report "
                 f"{os.path.join(REVIEWED_DIR, last + REPORT_SUFFIX)}." for branch, last in capped]
        return " ".join(notes)
    return None


def main():
    """None, or a note for the agent when the command may run."""
    command = without_heredocs(CALL.command)
    cwd = CALL.cwd

    tokens = shell_tokens(command)
    if tokens is None:
        return

    if {"pkill", "killall"} & set(command_words(tokens)):
        block("Blocked: pkill/killall match by pattern and also kill the owner's "
              "dev.sh. Stop only processes you started, with kill <PID>.")

    project = CALL.project
    ours = os.path.realpath(os.path.join(project, git(project, "rev-parse", "--git-common-dir")))

    note = reviewer_gate(tokens, cwd, ours)

    committing = run_dir(tokens, cwd, "git", ("commit",))
    if not committing:
        return note
    target, _ = committing
    if not os.path.isdir(target) or not in_repo(target, ours):
        return note

    if git(target, "branch", "--show-current") == "main":
        block("Blocked: never commit to main. Create a branch for this task "
              "(git switch -c <name>) and commit there.")

    if docs_only(target):
        return note

    top = git(target, "rev-parse", "--show-toplevel")
    base = size_base(command, target)
    size_ok = bool(SIZE_OK_IN_COMMAND.search(command))
    recorded = os.path.join(top, git(top, "rev-parse", "--git-path", "check-passed"))
    try:
        with open(recorded) as f:
            passed = f.read().split()
    except OSError:
        passed = None
    env = {name: value for name, value in os.environ.items() if name not in ("BASE", "SIZE_OK")}
    if base:
        env["BASE"] = base
    if size_ok:
        env["SIZE_OK"] = "1"
    now = subprocess.run(["scripts/check.sh", "--pass-record"], cwd=top, env=env,
                         capture_output=True, text=True)
    if now.returncode != 0:
        block(f"Blocked: `scripts/check.sh --pass-record` failed in {top}:\n{now.stderr}")
    if passed != now.stdout.split():
        run = (f"BASE={base} " if base else "") + ("SIZE_OK=1 " if size_ok else "") + "scripts/check.sh"
        block(f"Blocked: scripts/check.sh hasn't passed on these files. Run `{run}` in {top}, "
              "fix what it reports, then commit again.")


CALL.allow(main())

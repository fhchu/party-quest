#!/usr/bin/env python3
"""Claude Code PreToolUse hook (Bash) for party-quest. Exit 2 blocks the
command and hands stderr back to Claude.

- Blocks pkill and killall: matching by pattern also kills the owner's dev.sh.
- Blocks git commit on main in this repo (any worktree of it).
- Blocks `gh pr create`, and a `git push` to a branch with an open PR,
  until the reviewer subagent has reviewed the branch's tip. Blocks
  `git push --all` and `--mirror`, which would get past that check.
- Before any other commit in this repo: runs ./check.sh and blocks the
  commit if it fails. check.sh's size check measures against BASE: a
  `BASE=<ref>` in the command if there is one, else the base of the branch's
  open PR, else check.sh's own default (origin/main).
  A `SIZE_OK=1` in the command skips that check, as it does for check.sh
  itself (mechanical changes only; the PR description says why).
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
import json
import os
import re
import shlex
import subprocess
import sys

CHECK_TIMEOUT_SEC = 480
# Most characters of check.sh's output a blocked commit hands back: the end
# of it, where the failures are.
BLOCK_OUTPUT_CHARS = 6000


def block(reason):
    print(reason, file=sys.stderr)
    sys.exit(2)


def git(path, *args):
    out = subprocess.run(["git", "-C", path, *args], capture_output=True, text=True)
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
    before it, taken as its file descriptor. A quoted lone operator (`'>'`)
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
# Options before the verb that take a separate value: git's. gh takes none
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


def reviewed(target, branch):
    """True if a recorded review covers the tip of branch: the reviewed commit
    is the tip itself, or contains it and was reviewed against main (so the
    review's diff included the tip's changes)."""
    tip = git(target, "rev-parse", "--verify", "-q", branch + "^{commit}")
    if not tip:
        return False
    if not os.path.isdir(REVIEWED_DIR):
        return False
    for sha in os.listdir(REVIEWED_DIR):
        if not re.fullmatch(r"[0-9a-f]{40}", sha):
            continue
        try:
            _, base = open(os.path.join(REVIEWED_DIR, sha)).read().split()
        except ValueError:
            continue
        if sha == tip:
            return True
        contains = subprocess.run(["git", "-C", target, "merge-base", "--is-ancestor", tip, sha],
                                  capture_output=True).returncode == 0
        if contains and base in MAIN_REFS:
            return True
    return False


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
    for branch in branches:
        if branch and not reviewed(target, branch):
            tip = git(target, "rev-parse", "--short", branch)
            block(f"Blocked: {branch} at {tip} hasn't been through the reviewer. Start the "
                  "reviewer subagent (Agent tool, subagent_type reviewer) with the branch, its "
                  "base and the worktree path, wait for its report, fix what it finds, then run "
                  "this again. Every new commit needs a new review. For a stack, review the top "
                  "branch against main: that one review covers every branch beneath it.")


def main():
    payload = json.load(sys.stdin)
    command = without_heredocs(payload.get("tool_input", {}).get("command", ""))
    cwd = payload.get("cwd") or os.getcwd()

    tokens = shell_tokens(command)
    if tokens is None:
        return

    if {"pkill", "killall"} & set(command_words(tokens)):
        block("Blocked: pkill/killall match by pattern and also kill the owner's "
              "dev.sh. Stop only processes you started, with kill <PID>.")

    project = os.environ.get("CLAUDE_PROJECT_DIR", cwd)
    ours = os.path.realpath(os.path.join(project, git(project, "rev-parse", "--git-common-dir")))

    reviewer_gate(tokens, cwd, ours)

    committing = run_dir(tokens, cwd, "git", ("commit",))
    if not committing:
        return
    target, _ = committing
    if not os.path.isdir(target) or not in_repo(target, ours):
        return

    if git(target, "branch", "--show-current") == "main":
        block("Blocked: never commit to main. Create a branch for this task "
              "(git switch -c <name>) and commit there.")

    if docs_only(target):
        return

    top = git(target, "rev-parse", "--show-toplevel")
    env = dict(os.environ)
    base = size_base(command, target)
    if base:
        env["BASE"] = base
    if SIZE_OK_IN_COMMAND.search(command):
        env["SIZE_OK"] = "1"
    try:
        result = subprocess.run(["./check.sh"], cwd=top, capture_output=True, text=True,
                                timeout=CHECK_TIMEOUT_SEC, env=env)
    except subprocess.TimeoutExpired:
        block(f"Blocked: check.sh ran longer than {CHECK_TIMEOUT_SEC} s.")
    if result.returncode != 0:
        block("Blocked: ./check.sh failed; fix it before committing.\n"
              + (result.stdout + result.stderr)[-BLOCK_OUTPUT_CHARS:])


main()

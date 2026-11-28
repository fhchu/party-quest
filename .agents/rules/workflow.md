---
trigger: always_on
---
# Workflow

`game/` is one Godot 4 project that runs as both the browser client and
the game server. `relay/` is a Go WebTransport relay in front of it.
`backend/` is the Go backend (players and their logins, items and
inventories, finished runs and a ledger).

After changing code (any file but `.md`), run `./check.sh`: every linter
(gdstyle, golangci-lint, ShellCheck), then every test suite. Fix what it
reports. It must pass before you finish. A change to `.md` files alone
skips it, here and in the commit hook; CI still runs it.

Once `./check.sh` passes, or once the edit is done for `.md` files alone,
commit finished work to a branch off `main` and push it right away. Push
every commit, and open the branch's PR once the session has no work left
and nothing waits on the owner; you don't need to ask for either. Never
commit to `main` and never merge: the owner reviews each branch on GitHub
and merges it.

Work on a task in its own worktree, so the owner's open checkout stays on
the branch it is on: `.agents/bin/worktree.sh new <branch> [<base>]` makes
it under `.claude/worktrees/` and prints its path. Once the branch is
pushed, remove it with `.agents/bin/worktree.sh done <branch>`, which
refuses while anything is uncommitted or unpushed. In a session the app
started in its own worktree, remove it with the app's own worktree tool
instead (`ExitWorktree` with removal in Claude Code), which also moves the
session back to the main checkout; check first that
`git status` is clean and the branch is on `origin`. If either way can't
remove it, leave it and say why. The branch stays. Remove only worktrees
you created, never another session's.

When you edit files from a python heredoc, use `edit(path, old, new)`
from `.agents/bin/replace.py` instead of reading, replacing and writing by
hand: run the heredoc with `PYTHONPATH=<checkout>/.agents/bin` and
`from replace import edit`. It stops with an error when the old text isn't
in the file exactly once, instead of leaving the file unchanged without a
word.

Right before committing GDScript, check `git diff` for every edit you
made. After editing `project.godot`, ask the owner to use Project →
Reload Current Project.

Never stop dev servers with `pkill` and a pattern. Stop only processes
you started, by PID.

If `docker` can't reach its daemon, start it with `open -a Docker` and
wait for `docker info` to answer; don't treat Docker as unavailable.

Don't silence a lint rule to get past it. If a rule is wrong for this
code, turn it off in `.golangci.yml` or `game/gdstyle.toml` with a comment
saying why, or use a `//nolint:<rule> // reason` on the line in Go.

## Branch size

`./check.sh` fails a branch that changes more than 400 lines against
`main`, added plus deleted. Tests, `.tscn`/`.tres`, Godot's `.uid` and
`.import` files, `game/addons/`, lockfiles, binaries and files deleted
whole don't count. CI skips this check.

If `./check.sh` says a branch is too big, split it along the seams in the
sketch; don't raise the limit. `SIZE_OK=1` is only for mechanical changes
(a rename, a generated-file or version bump), and the PR description says
why.

When work is split across branches, each builds and passes `./check.sh`
on its own (a branch changing `.md` files alone skips it), and is cut
from the one before it, its PR based on the one below. For a stacked
branch, run `./check.sh` with `BASE=<parent branch>`.
The `stacked-prs` skill has the steps for opening, linking and updating
the stack. Name a stack's branches rather than numbering them.

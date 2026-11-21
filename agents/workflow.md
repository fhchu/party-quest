# Workflow

`game/` is one Godot 4 project that runs as both the browser client and
the game server. `relay/` is a Go WebTransport relay in front of it.
`server/` is the Go backend (players and their logins, items and
inventories, finished runs and a ledger).

After writing code, run `./check.sh`: every linter (gdstyle, golangci-lint,
ShellCheck), then every test suite. Fix what it reports. It must pass before
you finish.

Once `./check.sh` passes, commit finished work to a branch and push it
right away: one branch per milestone or task (for example `phase2-m1`), off
`main`. Push every commit, and open the branch's PR once the session has
no work left and nothing waits on the owner; you don't need to ask for
either. Never commit to `main` and never merge: the owner reviews each
branch on GitHub and merges it.

Work on a task in its own worktree, so the owner's open checkout stays on
the branch it is on. Once the branch is pushed, remove the worktree
(`ExitWorktree` with removal, or `git worktree remove <path>`). The branch
stays. Remove it only when `git status` is clean and the branch is on
`origin`; otherwise leave it and say why. Remove only worktrees you
created, never another session's.

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

Keep each branch to one logical change. `./check.sh` fails a branch that
changes more than 400 lines against `main`, added plus deleted. Tests,
`.tscn`/`.tres`, Godot's `.uid` and `.import` files, `game/addons/`,
lockfiles and binaries don't count. CI skips this check.

If `./check.sh` says a branch is too big, split it along the seams in the
sketch; don't raise the limit. `SIZE_OK=1` is only for mechanical changes
(a rename, a generated-file or version bump), and the PR description says
why.

When work is split across branches, each builds and passes `./check.sh`
on its own, and is cut from the one before it, its PR based on the one
below. For a stacked branch, run `./check.sh` with `BASE=<parent branch>`.
The `stacked-prs` skill has the steps for opening, linking and updating
the stack.

## The private notes

`notes/` is the owner's private wiki: an Obsidian vault in iCloud,
symlinked into the repo and kept out of it (`.git/info/exclude`). Never
commit it to this repo. Start at `notes/Home.md`; its rules are in
`notes/3 Working on it/Agent workflow.md`.

- `notes/4 Plan/Now.md` is the way back in: the owner's to-do, the phase's
  status, then the agents' part. Read it for any code, plan or status work.
  "Try it in Chrome" there is for the owner; agent work never waits on it.
- Don't edit topic or plan pages while a branch is open. Write what the
  wiki needs in the session's pending page (the `pending-page` skill);
  after a merge, start the `wiki` subagent when the reminder hook says so.
  The wiki subagent doesn't run git: a hook commits exactly the pages it
  lists.
- The vault has its own git repo, only as a backup. Commit on its `main`,
  no branches, and stage only the files you changed: other sessions may
  have unsaved edits there.
- Read `notes/2 How it works/Hosting.md` before any AWS work; the account,
  profile and region facts are there.

## This laptop

- The default browser is Firefox, so Godot's Run in Browser opens Firefox.
  For a Chrome check, open `http://localhost:8060` in Chrome.
- The desktop app doesn't read `~/.zshrc`, so it can't find `uvx` for the
  AWS MCP server.

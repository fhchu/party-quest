# Workflow

Read before any code change.

`game/` is one Godot 4 project that runs as both the browser client and
the game server. `relay/` is a Go WebTransport relay in front of it.
`server/` is the Go backend (accounts, match results, stats).

After writing code, run `./check.sh`: every linter (gdstyle, golangci-lint,
ShellCheck), then every test suite. Fix what it reports. It must pass before
you finish. The backend's database tests need Docker running; without it they
skip (`open -a Docker` on macOS).

`./check.sh` also fails a branch that changes more than 400 lines against
`main`, added plus deleted. Tests, `.tscn`/`.tres`, Godot's `.uid` and
`.import` files, `game/addons/`, lockfiles and binaries don't count. For a
stacked branch, run it with `BASE=<parent branch>`. CI skips this check.

Once `./check.sh` passes, commit finished work to a branch and push it
right away: one branch per milestone or task (for example `phase2-m1`), off
`main`. Push every commit; you don't need to ask. Never commit to `main` and
never merge: the owner reviews each branch on GitHub and merges it.

Work on a task in its own worktree, so the owner's open checkout stays on
the branch it is on. Once the branch is pushed, remove the worktree
(`ExitWorktree` with removal, or `git worktree remove <path>`). The branch
stays. Remove it only when `git status` is clean and the branch is on
`origin`; otherwise leave it and say why. Remove only worktrees you
created, never another session's.

The owner often has the Godot editor open, and it can save its own copy
of a script over your edit. Right before committing GDScript, check
`git diff` for every edit you made. After editing `project.godot`, ask the
owner to use Project → Reload Current Project.

Never stop dev servers with `pkill` and a pattern: it also kills the
owner's running `dev.sh`. Stop only processes you started, by PID.

Don't silence a lint rule to get past it. If a rule is wrong for this
code, turn it off in `.golangci.yml` or `game/gdstyle.toml` with a comment
saying why, or use a `//nolint:<rule> // reason` on the line in Go.

## Working with the owner

- Design calls (controls, aiming, UI, game rules) are the owner's. Offer
  the options and what each costs; don't present one as the obvious
  choice.
- Build what was asked and nothing beside it. If a change seems to want a
  fallback, a compatibility path or behavior nobody mentioned, ask first,
  or do the narrow thing and say what you left out.
- Before calling something standard or common practice ("most Godot
  projects do X", another game's tick rate), check sources or sample real
  projects. Otherwise say it's an impression and offer to check.

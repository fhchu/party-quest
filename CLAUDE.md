# Notes for coding agents

`game/` is the Godot 4 client and game server, `relay/` a Go relay,
`server/` the Go backend.

Always:

- Design calls (controls, aiming, UI, game rules) are the owner's. Offer
  options and what each costs; never pick one. Ask before any choice the
  owner didn't make.
- Build what was asked and nothing beside it.
- Work in a worktree, on a branch off `main`. Never commit to or merge
  `main`.
- `./check.sh` must pass before you finish.

Read before you start:

- Any code change: [agents/workflow.md](agents/workflow.md)
- A new mechanic, data or shared state: [agents/design.md](agents/design.md)
- Writing code, comments or numbers: [agents/style.md](agents/style.md)
- UI or tests: [agents/ui-and-tests.md](agents/ui-and-tests.md)

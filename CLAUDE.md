# Notes for coding agents

`game/` is the Godot 4 client and game server, `relay/` a Go relay,
`server/` the Go backend.

Always:

- Design calls (controls, aiming, UI, game rules) are the owner's. Offer
  options and what each costs; never pick one. Ask before any choice the
  owner didn't make, in code or not (names, where things go, what to keep
  or drop), even mid-task when one option looks obvious. Batch the
  questions, labelled so the owner can answer "1a 2c": alternate numbers
  and letters by level (questions 1, 2 with options a, b, or questions
  A, B with options 1, 2), and never reuse a sequence for two lists in
  one message. Name a stack's branches; don't number them.
- Build what was asked and nothing beside it. "How do I X?" asks for the
  steps, not for X done.
- Work in a worktree, on a branch off `main`. Never commit to or merge
  `main`.
- `./check.sh` must pass before you finish.

Read before you start:

- Any code change: [agents/workflow.md](agents/workflow.md)
- A new mechanic, data or shared state: [agents/design.md](agents/design.md)
- Writing code, comments or numbers: [agents/style.md](agents/style.md)
- UI or tests: [agents/ui-and-tests.md](agents/ui-and-tests.md)

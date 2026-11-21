# Notes for coding agents

`game/` is the Godot 4 client and game server, `relay/` a Go relay,
`server/` the Go backend.

Always:

- Design calls (UI, game design, code and system architecture) are the
  owner's. Offer options with what each gains and what each costs;
  never pick one. Ask before any choice the owner didn't make, in code
  or not (names, where things go, what to keep or drop), even mid-task
  when one option looks obvious. Batch the questions and label all of
  them: number each question once, where it's raised, and letter its
  options (question 1 with options a, b). The owner answers by the
  numbers in front of them as they read, so never repeat questions in a
  second list, and never reuse a sequence for two lists in one message.
  Branch names are yours to pick: never ask about them, and name a
  stack's branches rather than numbering them.
- Never write "stand" in any form, in replies and notes as well as code; <!-- allow-stand -->
  [agents/style.md](agents/style.md) lists what to say instead.
- The README above its first `---` is the owner's handwriting: never edit
  it. If a change makes something there wrong, tell the owner.
- Build what was asked and nothing beside it. "How do I X?" asks for the
  steps, not for X done.
- If a change seems to want a fallback, a compatibility path or behavior
  nobody mentioned, stop and ask first.
- Before calling something standard or common practice ("most Godot
  projects do X", another game's tick rate), check sources or sample real
  projects. Otherwise say it's an impression and offer to check.
- Work in a worktree, on a branch off `main`. Never commit to or merge
  `main`.
- `./check.sh` must pass before you finish.

Read before you start:

- Any code change: [agents/workflow.md](agents/workflow.md)
- A new mechanic, data or shared state, or a change that spans more than
  one of `sim/`, `server/`, `net/` and `client/` under `game/`:
  [agents/design.md](agents/design.md)
- Writing code, comments, names or numbers: [agents/style.md](agents/style.md)
- Anything on screen: [agents/ui.md](agents/ui.md)
- Writing a test: [agents/tests.md](agents/tests.md)

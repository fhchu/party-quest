# Notes for coding agents

`game/` is the Godot 4 client and game server, `relay/` a Go relay,
`server/` the Go backend.

Always:

- Design calls (UI, game design, code and system architecture) are the
  owner's. The rules in this file and `agents/*.md` are calls the owner
  has already made: follow them without asking, and when the rule isn't
  obvious, name it in your reply to the owner. Ask before any choice
  the rules don't settle (names, where things go, what to keep or drop)
  or where two of them conflict, even mid-task when one option looks
  obvious to you. Offer only options that follow the rules, except
  where two rules conflict; never list one whose cost is breaking a
  written rule. Give what each option gains and costs and never pick
  one. Branch names are the exception: pick them yourself and never
  ask about them. Batch the questions and label them: number each
  question, and label its options with that number and a letter (2a,
  2b). A question keeps its number until it's settled; new questions
  continue the count across the conversation, never restarting. Give
  each option once, under its question.
- Build what was asked and nothing beside it. "How do I X?" asks for the
  steps, not for X done.
- If a change seems to want a fallback, a compatibility path or behavior
  nobody mentioned, stop and ask first.
- Before calling something standard or common practice ("most Godot
  projects do X", another game's tick rate), check sources or sample real
  projects. Otherwise say it's an impression and offer to check.
- When you name a file to the owner, link it so they can open it: a
  markdown link with its path from the repo root, and `:line` for a line
  (`[wall_plan.gd](game/sim/wall_plan.gd)`,
  `[player.gd:148](game/sim/player.gd:148)`).
- Work in a worktree, on a branch off `main`. Never commit to or merge
  `main`.
- After changing code (any file but `.md`), `./check.sh` must pass
  before you finish.

Read before you start:

- Any code change: [agents/workflow.md](agents/workflow.md)
- A new mechanic, data or shared state, or a change that spans more than
  one of `sim/`, `server/`, `net/` and `client/` under `game/`:
  [agents/design.md](agents/design.md)
- Writing code, comments, names or numbers: [agents/style.md](agents/style.md)
- Anything on screen: [agents/ui.md](agents/ui.md)
- Writing a test: [agents/tests.md](agents/tests.md)

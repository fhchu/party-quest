# Notes for coding agents

`game/` is one Godot 4 project that runs as both the browser client and
the game server. `relay/` is a Go WebTransport relay in front of it.
`server/` is the Go backend (accounts, match results, stats).

After writing code, run `./check.sh`: every linter (gdstyle, golangci-lint,
ShellCheck), then every test suite. Fix what it reports. It must pass before
you finish. The backend's database tests need Docker running; without it they
skip (`open -a Docker` on macOS).

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

## Design

### Before writing code

- For a new mechanic, data type or piece of shared state, or a change that
  spans more than one of `sim/`, `server/`, `net/` and `client/`, post a
  short sketch and wait for the owner's OK: the data, who owns each piece
  of state, what's an attribute and what's a type, and the names. Small
  changes inside one file skip this.
- Look for existing code that already does something similar, and extend
  or generalize it. Never write a parallel version: players and dummies
  are pushed the same way, so they share one knockback.
- If the existing structure fights your change, stop and say what's in
  the way, and propose the fix. Don't restructure unasked, and don't bolt
  the change on around it.

### Principles

- **Behavior comes from attributes, not from what a thing is.** A dummy
  that can't be pushed has `pushed_by_swings = false`; code doesn't check
  `kind == READY`. A type says what something is for (which dummy readies,
  how to draw it), never how it behaves.
- **State lives on the thing it describes.** "Can't be hurt again yet" is
  the player's: one timer on the player covers every damage source, not a
  per-enemy list of who was hurt when.
- **Make invalid states hard to express.** One enum instead of two bools
  that must agree; one timer instead of a per-source list.
- **Narrow interfaces.** Pass what a function uses, not the bag it came
  from. Don't thread an option through layers that only forward it (a
  load-test flag doesn't belong in every World constructor); deliver it
  to the one place that uses it, or ask.
- **Names say what and who.** Booleans read as predicates, functions as
  verbs, and a name never promises more or less than the code does:
  `_add_dummy_in_reach`, not `_in_reach` (which reads as a check);
  `_advance(ticks)`, not `_steps` (which reads as a count). Never a bare
  `hit` that could mean either side: a dummy is `flashing`, a player is
  `invulnerable`, a swing's contact has an `attacker_id`. Avoid `data`,
  `info`, `handle`, `process` and bare `flag` or `done`.
- **No speculative generality.** Don't add options or abstractions for a
  second use that doesn't exist yet.
- **Fail loudly at boundaries.** Don't swallow errors. Validate what comes
  off the network; don't add defensive checks for states your own code
  can't produce.
- **Delete what your change made dead**: code, parameters, settings. No
  commented-out code, no shims for callers that don't exist.

### Before you finish

Reread your diff as a reviewer would. Look for anything duplicated, any
new parameter that only forwards, any state two places must keep in sync,
and any name you'd have to explain.

## Style

Follow each language's own guide. Where this file is silent, the guide wins.

- **GDScript:** the [official style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).
  The parts most often missed:
  - Names: `snake_case` for files, functions, variables and signals
    (signals in the past tense: `door_opened`); `PascalCase` for classes,
    nodes and enum names; `CONSTANT_CASE` for constants and enum members,
    one enum member per line. A leading `_` marks private functions and
    variables. Preloaded scripts are constants named like the class
    (`const World := preload(...)`).
  - Order within a file: signals, enums, constants, static variables,
    variables, static methods, engine callbacks (`_init`, `_ready`,
    `_process`, `_physics_process`, then the rest, including
    `MultiplayerPeerExtension`'s `_poll` and friends), other methods, and
    inner classes last.
  - Lines under 100 characters, 80 where easy. Continuation lines get two
    extra indents; `and`/`or` start the continued line.
  - Comments go on their own line, not after code.
  - Type everything; `:=` when the type is plain from the right-hand side.
  - Before writing a helper or a bit of maths, look for a built-in in the
    [class reference](https://docs.godotengine.org/en/stable/classes/)
    (`is_zero_approx`, `inverse_lerp`, `StreamPeerBuffer`, `String`'s
    `trim_prefix`, `Array.assign` ...). Hand-rolled versions bring their
    own magic numbers.
  - Give records a small class with named fields, not an array read by
    index: `p.swing_ticks`, not `p[3]`. Index magic is still magic. The
    exception is Godot APIs that return arrays (`[error, bytes]`); name
    what they hold in a comment.
- **Go:** `gofmt`, [Effective Go](https://go.dev/doc/effective_go), [Go Code
  Review Comments](https://go.dev/wiki/CodeReviewComments) and [Go doc
  comments](https://go.dev/doc/comment). Names are `MixedCaps`, never
  underscores. Initialisms keep one case (`playerID`, `peerURL`,
  `HTTPServer`, never `playerId`). Receivers get short names, the same on
  every method of a type. An exported name doesn't repeat its package
  (`matches.New`, not `matches.NewMatches`).
- **Shell:** must pass [ShellCheck](https://www.shellcheck.net/).

## UI

The owner reviews UI as pictures, never as `.tscn` or `.tres` text.

- After changing anything on screen, run `game/ui-gallery.sh` and look at
  the shots in `game/build/ui-gallery/` yourself before calling it done.
  Fix what looks wrong; report design problems you notice (they're the
  owner's to decide).
- A new screen or state gets a shot in `game/tools/ui_gallery/shots.gd`.
- When describing a UI change to the owner, show the shots and say in
  words what's where and what changes between states.

## Tests

A test checks behavior: given these inputs, the code does this. It must
not be a copy of the code under test in another form, a
[change-detector test](https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html).
Such a test breaks on every edit, right or wrong, and catches no bugs.

- Don't assert that a constant, default, config value or project
  setting equals its current literal (`assert MAX_PLAYERS == 4`, a key
  prompt equal to today's bindings). Assert the rule it must keep
  (`PLAYER_COLORS.size() == MAX_PLAYERS`), or set the input in the test
  and check the output follows it.
- Don't mock collaborators to check which calls were made, in what
  order. Check the result: state, output, what reached the other side.
  Fakes that stand in for the network or database are fine.
- Expected values come from the test's own setup or from the rule
  (`start + speed * DT`), never from re-running the code's own steps.
- A refactor that keeps behavior should leave the tests passing. If it
  doesn't, fix the test so it checks the behavior, not the old code.
- Prefer a test in the suite to a smoke test (a headless `--bot` client).
  Smoke-test only what the suite can't easily reach, or temporary code
  whose test would soon be deleted.
- Placeholder design stays easy to replace: test the rule other code relies
  on, not the placeholder's details (where a dummy stands, how many enemies
  a match has).

## Comments

A comment earns its place by telling the reader something the code can't.
Most of the time that's why: why this approach, why this value, why the
obvious alternative is wrong. If a comment explains what the code does,
first try to make the code say it (a better name, a named constant, a
smaller function), and drop the comment.

There are two kinds, and they have different jobs:

- **Doc comments** (`##` in GDScript; in Go, the comment right above a
  declaration) describe a thing for someone using it: what it's for, its
  units, what it returns, what callers must know. That's "what", and it's
  the right content here, because it shows in editor hovers and generated
  docs. In Go they're full sentences starting with the name (`readFrame
  reads ...`). Don't restate the name ("The player speed." on
  `player_speed`); say what the name can't (units, range, who sets it).
  - In GDScript, `##` attaches to the one declaration below it. A comment
    about a group of constants is a plain `#` comment.
- **Inline comments** (`#` or `//` inside code) are for why: a constraint,
  a workaround, an engine quirk, a non-obvious consequence.

Keep them short and true:

- One or two plain sentences. Cut anything the reader can see from the
  line itself.
- Never put history in a comment. A comment describes the code as it is:
  not what it used to do, what was removed or replaced, or who decided it
  and when ("used to", "no longer", "X is gone", "the owner's call
  (2026-11-05)"). History goes in commit messages. If a choice needs
  explaining, give the reason, not who made it.
- A comment that's only true because of code elsewhere is a hidden
  dependency. Either remove the dependency or name the other place ("must
  match relay/frames.go").
- When you change code, fix or delete the comments it makes wrong.
- Say so when a value is a guess: `Untuned.` For undecided design, art or
  hosting choices, use `PLACEHOLDER (design): ...` (or `(art)`,
  `(hosting)`), and mark throwaway debug code `DEBUG:`. Design calls belong
  to the owner; don't pick one and present it as settled.
- In tests, the test's name says what it checks. Comment only setup whose
  purpose isn't obvious.

## Numbers

- Name a number unless its meaning is plain where it's used: `0`, `1`,
  `* 1000` for milliseconds, `0xffff` next to a 16-bit write, `0.5` as the
  middle of a 0-to-1 blend. Colors and line widths get names by role
  (`TARGET_DUMMY_COLOR`, not `TAN`), so changing the look doesn't make the
  name wrong.
- One quantity, one source. If two places mean the same value (a header
  size, a port, a default option), define it once and refer to it. Derive
  related values from it (`HEADER_MAX := ORDERED_HEADER`) instead of
  writing out the result.
- If one value has to stay above or below another, derive it from the
  other (`keepAlivePeriod = idleTimeout / 3`) or check it in a test. Don't
  justify a value by another constant's current value ("the relay's limit
  plus 1 s").
- Where two languages must agree (the frame format in `game/net/frames.gd`
  and `relay/frames.go`, the ports in `game/net/protocol.gd` and
  `relay/main.go`), name the value on both sides and point each at the
  other. GDScript that builds JavaScript fills its numbers in from GDScript
  constants (see `game/net/web_transport_peer.gd`).
- Gameplay values go in `game/sim/balance.json`, in seconds, so they can
  be tuned without touching code and don't depend on the tick rate.

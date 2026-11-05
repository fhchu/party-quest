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

Don't silence a lint rule to get past it. If a rule is wrong for this
code, turn it off in `.golangci.yml` or `game/gdstyle.toml` with a comment
saying why, or use a `//nolint:<rule> // reason` on the line in Go.

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
- Describe the code as it is. History ("used to", "now", "changed to")
  goes in commit messages, not comments.
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

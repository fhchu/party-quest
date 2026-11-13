# Style

Read before writing code, comments or numbers.

## Languages

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
  constants (see `game/client/web_transport_peer.gd`).
- Gameplay values go in Godot resources in `game/shared/data/`, in px and
  seconds, so they can be tuned without touching code and don't depend on
  the tick rate. Global values are in `balance.tres`; each dummy kind, map
  and run has its own file. A value that stops being global moves out of
  `balance.tres` to the resource it belongs to.

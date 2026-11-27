---
trigger: glob
globs: "game/**, server/**, relay/**, **/*.sh, .github/**"
paths:
  - "game/**"
  - "server/**"
  - "relay/**"
  - "**/*.sh"
  - ".github/**"
---

# Design

### Before writing code

- Name every new file by its path and say why it belongs in that folder,
  in the sketch. Name every dependency the change adds, removes or moves
  (a new `preload`, import or call into another script) and the scripts
  at both ends, in the sketch and again in the PR description, even for
  a change too small to need a sketch. A reference from one game folder's
  file to another's also needs its line in `game/tests/dependencies.txt`,
  added only after the owner's OK; the tests fail without it, and CI fails
  a PR whose description doesn't quote each line it adds. A line whose
  target ends in `/` allows every file under that folder.
- Keep dependencies few. Put a value or function with the scripts that
  use it, and reach another folder only through the script that already
  does: before adding a line to `game/tests/dependencies.txt`, find the
  script that already holds that reference and do the work there, passing
  on its results rather than its constants. A new line is the last
  resort: design the change to need none (for example, `server.gd` and
  `client.gd` already reference `net/protocol.gd`, so they read its
  values and hand the results on). Propose a new line only when no such
  route exists.
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
  that must agree.
- **Narrow interfaces.** Pass what a function uses, not the bag it came
  from. Don't thread an option through layers that only forward it (a
  load-test flag doesn't belong in every World constructor); deliver it
  to the one place that uses it, or ask.
- **A script exposes only what it owns.** Don't pass on another script's
  constants or functions for others to use (`static var tick_sec :=
  GameTime.TICK_SEC`); a script that needs them preloads that script
  itself, so its dependency shows. A wrapper that does real work, or
  hides a lower layer on purpose, is fine. `dependencies_test.gd`
  catches a preload used through inheritance or as `A.B`, not this.
- **No speculative generality.** Don't add options or abstractions for a
  second use that doesn't exist yet.
- **Fail loudly at boundaries.** Don't swallow errors. Validate what comes
  off the network; don't add defensive checks for states your own code
  can't produce. Our own data files are checked by tests (see
  `.agents/rules/tests.md`), not at runtime: no `assert` in game code
  (`./check.sh` fails on one).
- **Gameplay values are data.** They go in Godot resources in
  `game/shared/data/`, in px and seconds, so they can be tuned without
  touching code and don't depend on the tick rate. Global values are in
  `balance.tres`; each dummy kind, map and run has its own file. A value
  that stops being global moves out of `balance.tres` to the resource it
  belongs to.

### Before you finish

Reread your diff as a reviewer would. Look for anything duplicated, any
new parameter that only forwards, any state two places must keep in sync,
and any name you'd have to explain.

# Design

Read before a new mechanic, data type or piece of shared state, or a
change that spans more than one of `sim/`, `server/`, `net/` and `client/`.

### Before writing code

- For a new mechanic, data type or piece of shared state, or a change that
  spans more than one of `sim/`, `server/`, `net/` and `client/`, post a
  short sketch and wait for the owner's OK: the data, who owns each piece
  of state, what's an attribute and what's a type, and the names. Small
  changes inside one file skip this.
- Name every new file by its path and say why it belongs in that folder.
  Name every dependency the change adds, removes or moves (a new
  `preload`, import or call into another script) and the scripts at both
  ends. Both go in the sketch, and again in the PR description, even for
  a change too small to need a sketch.
- Keep each branch to one logical change, under the 400 lines `check.sh`
  enforces. When the work will be bigger, the sketch also lists the
  branches in order and what each holds: groundwork (types, data,
  interfaces) first, then the behavior that uses it. Each branch builds and
  passes `./check.sh` on its own, and is cut from the one before it so
  GitHub shows a stack.
- If `./check.sh` says a branch is too big, split it along those seams;
  don't raise the limit. `SIZE_OK=1` is only for mechanical changes (a
  rename, a generated-file or version bump), and the PR description says
  why.
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
- **Never "stand" in any form** (`standing`, `stands`, `stood`, `stand-in`),
  in names, comments or tests: it could mean alive, located, not moving or
  a substitute. Say which: `alive` or `living` (not downed), is or are
  (where something is), stops or doesn't move, `PLACEHOLDER` (a temporary
  stopgap, so it shows up in placeholder greps) or substitute (a test
  double).
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

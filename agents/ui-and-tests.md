# UI and tests

Read before changing anything on screen, or writing a test.

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

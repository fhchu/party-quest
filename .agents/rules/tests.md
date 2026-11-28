---
trigger: glob
globs: "game/tests/**, **/*_test.go"
paths:
  - "game/tests/**"
  - "**/*_test.go"
---

# Tests

A test checks behavior: given these inputs, the code does this. Before
you call one done, name the bug that would make it fail, and make sure
it would: break the code that way and run it. Don't write a
[change-detector test](https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html),
one that copies the code under test.

- Test our code, not Godot's. A test whose outcome only the engine
  decides (that `rand_weighted` picks a heavier weight more often) can't
  catch a bug of ours. Test what our code does with the engine's
  answer: which value it passes in, what it does with the result.
- Write an expected value as a literal, with the formula it comes from
  in a comment: `# MAX_HEALTH 3, less ENEMY_CONTACT_DAMAGE 1.` above
  `is_equal(2)`. A formula in the test can make the code's own mistake. A
  value the test can't set, such as the real data's arena, a tuning
  constant in the code under test or the tick rate, is named rather than
  copied, even in a short formula (`GameTime.ticks(0.3)`,
  `walk_step * GameTime.TICK_RATE`): a copy breaks when it's tuned. For
  expected values this rule wins over style.md's "one quantity, one
  source": the copy in the test is the point. Never
  get an expected value from the code under test, including by reading
  it back from the object you're testing: a snapshot's health checked
  against the player's own health passes when the snapshot sends max
  health instead. Don't assert that a constant, default or setting
  equals its current literal (`assert MAX_PLAYERS == 4`) either: assert
  the rule it keeps (`PLAYER_COLORS.size() == MAX_PLAYERS`).
- The values a test's outcome depends on show in its body. Shared setup
  may build what the test needs, but a value the test checks against is
  set or named in the test (`MAX_HEALTH`, `_pin({...})`), not left in a
  fixture for the reader to find. No generic check run at the end of
  many tests; a helper that asserts one named fact
  (`_assert_tile_the_arena`) is fine.
- No logic in a test's body: no `if`, no loop that computes or checks,
  no arithmetic that works out an expected value. Nothing tests a test,
  so it has to be plainly right. A loop that drives the code (step until
  a state) goes in a helper named for what it does (`_step_until`). A
  loop over a table of cases, or over everything in the real data, is
  fine when each failure names its case (`override_failure_message`,
  `t.Errorf("%s: ...", name)`).
- Assert with the matcher for the value's type, so a failure shows what
  came and what was expected: `assert_float(x).is_equal_approx(4.0,
  0.001)`, `assert_vector(...)`, not `assert_bool(is_equal_approx(x,
  4.0)).is_true()`, which fails with only "expected true" (checked:
  `bool-asserts`).
- Give each value you check one no wrong answer shares: not its default,
  not another field's value, not the only value the data happens to
  hold. `_busy_lobby()` in `lobby_state_test.gd` sets every field off its
  default.
- Check that the setup reached the case the test is named for before
  checking the outcome. A request for `/../secret.txt` is redirected by
  the mux before the static handler's own check runs.
- The data in `shared/data/` changes as the game is tuned, so a test tied
  to today's values breaks for no bug. Build the rooms, kinds and runs a
  test needs (`DataRecords`, `_add_dummy`), and use the real data only to
  check rules every room or run must keep (`data_test.gd`). Not: town
  has one dummy, it's listed first, its door is north, the run's first
  room makes random choices. A typo in our own data (a condition name) is
  caught this way, by a test over the real file, not by a runtime check.
- Code that turns data into sim values (`world_loader.gd`, the snapshot
  codec) needs its own tests with numbers you choose, because tests that
  build sim objects by hand skip it. Today a doubled time limit passes
  the suite.
- One behavior per test, named for it, calling the code its name names:
  a test named for an empty lobby has no seats. In Go, give each step of
  a sequence its own `t.Run`, so the first failure doesn't hide the rest.
- Use the code's public methods, not its `_` members (`_receive`,
  `_conns`, `_clock_offset`). A refactor that keeps behavior should leave
  the tests passing. If the state a test needs can't be reached
  publicly, say so in the PR instead of reaching in. Overriding an engine
  virtual (`_get_packet_peer`) is public. `./check.sh` fails on any
  member not in `game/tests/private_members.txt`.
- Across the network, wait for a condition (`_until`), not a fixed time.
  To show something didn't happen, first wait for a later reply that
  proves it would have arrived by now, such as a pong (checked:
  `fixed-waits`).
- Don't mock collaborators to check which calls were made, in what
  order. Check the result: state, output, what reached the other side.
  Fakes that replace the network or database are fine (checked: `mocks`).
- Prefer a test in the suite to a smoke test. Smoke-test only what the
  suite can't easily reach, or temporary code whose test would soon be
  deleted.

---
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
- Expected values come from the test's own setup or from the rule
  (`start + speed * DT`, `GameTime.ticks(TIME_LIMIT_SEC)`), never from
  the code under test. That includes reading them back from the object
  you're testing: a snapshot's health checked against the player's own
  health passes when the snapshot sends max health instead. Don't
  assert that a constant, default or setting equals its current literal
  (`assert MAX_PLAYERS == 4`) either: assert the rule it keeps
  (`PLAYER_COLORS.size() == MAX_PLAYERS`).
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
  proves it would have arrived by now, such as a pong.
- Don't mock collaborators to check which calls were made, in what
  order. Check the result: state, output, what reached the other side.
  Fakes that replace the network or database are fine.
- Prefer a test in the suite to a smoke test. Smoke-test only what the
  suite can't easily reach, or temporary code whose test would soon be
  deleted.

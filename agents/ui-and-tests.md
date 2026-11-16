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

A test checks behavior: given these inputs, the code does this. Before
you call one done, name the bug that would make it fail, and make sure
it would: break the code that way and run it. A test that can't fail
catches nothing. A test that copies the code under test, a
[change-detector test](https://testing.googleblog.com/2015/01/testing-on-toilet-change-detector-tests.html),
fails on every edit, right or wrong.

- Expected values come from the test's own setup or from the rule
  (`start + speed * DT`, `GameTime.ticks(TIME_LIMIT_SEC)`), never from
  the code under test. That includes reading them back from the object
  you're testing: a snapshot's health checked against the player's own
  health passes when the snapshot sends max health instead, and sending
  the new world's own press count passes when the world forgot the
  client's presses. Don't assert that a constant, default or setting
  equals its current literal (`assert MAX_PLAYERS == 4`) either: assert
  the rule it keeps (`PLAYER_COLORS.size() == MAX_PLAYERS`).
- Give each value you check one no wrong answer shares: not its default,
  not another field's value, not the only value the data happens to
  hold. Town's dummies are all kind 0, so a codec round trip over town
  passes with `kind` never sent. `_busy_lobby()` in `lobby_state_test.gd`
  sets every field off its default.
- Check that the setup reached the case the test is named for before
  checking the outcome. A swing meant to un-ready a player on the tick
  the party leaves town touched nothing, so the test passed with the
  order it guards reversed; assert the player un-readied first. A request
  for `/../secret.txt` is redirected by the mux before the static
  handler's own check runs.
- Data in `shared/data/` is placeholder. Build the rooms, kinds and runs
  a test needs (`DataRecords`, `_add_dummy`), and use the real data only
  to check rules every room or run must keep (`data_test.gd`). Not: town
  has one dummy, it's listed first, its door is north, the run's first
  room makes random choices.
- Code that turns data into sim values (`world_loader.gd`, the snapshot
  codec) needs its own tests with numbers you choose, because tests that
  build sim objects by hand skip it. Today a shot speed left in px/s, a
  turn rate left in degrees and a doubled time limit all pass the suite.
- One behavior per test, named for it, calling the code its name names:
  a test named for an empty lobby has no seats; one named for a run's
  seed calls `World.run`. In Go, give each step of a sequence its own
  `t.Run`, so the first failure doesn't hide the rest.
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
- Prefer a test in the suite to a smoke test.
  Smoke-test only what the suite can't easily reach, or temporary code
  whose test would soon be deleted.

extends GdUnitTestSuite
## How a dummy picks its attack: by weight, among the usable ones or all of
## them, or in turn.

const AttackChoice := preload("res://sim/attack_choice.gd")
const DummyKind := preload("res://shared/data/dummy_kind.gd")

const VALID := DummyKind.AttackChoice.WEIGHTED_VALID
const RANDOM := DummyKind.AttackChoice.WEIGHTED_RANDOM
const CYCLE := DummyKind.AttackChoice.CYCLE
## Enough picks for each share to land near its weight.
const PICKS := 4000
## How far a share of PICKS may land from its weight's.
const SHARE_TOLERANCE := 0.05

var rng: RandomNumberGenerator


func before_test() -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = 1


func test_weights_are_shares_of_their_total() -> void:
	var shares := _shares(RANDOM, [3.0, 1.0], [true, true])
	assert_float(shares[0]).is_equal_approx(0.75, SHARE_TOLERANCE)


func test_a_weight_of_0_is_never_picked_beside_a_positive_one() -> void:
	assert_float(_shares(RANDOM, [0.0, 1.0], [true, true])[0]).is_zero()


func test_when_every_weight_is_0_each_is_as_likely() -> void:
	var shares := _shares(RANDOM, [0.0, 0.0], [true, true])
	assert_float(shares[0]).is_equal_approx(0.5, SHARE_TOLERANCE)


func test_weighted_valid_picks_only_among_usable_attacks() -> void:
	assert_float(_shares(VALID, [1.0, 1.0], [false, true])[0]).is_zero()
	assert_float(_shares(VALID, [0.0, 1.0], [true, false])[0]).is_equal_approx(1.0, SHARE_TOLERANCE)


func test_weighted_valid_with_nothing_usable_picks_none() -> void:
	assert_int(_pick(VALID, [1.0, 1.0], [false, false])).is_equal(-1)


func test_weighted_random_picks_unusable_attacks_too() -> void:
	var shares := _shares(RANDOM, [1.0, 1.0], [false, true])
	assert_float(shares[0]).is_equal_approx(0.5, SHARE_TOLERANCE)


func test_cycle_picks_the_next_in_turn_usable_or_not() -> void:
	var usable: Array[bool] = [false, false, false]
	var weights := PackedFloat32Array([1.0, 1.0, 1.0])
	assert_int(AttackChoice.pick(CYCLE, weights, usable, 2, rng)).is_equal(2)


func test_the_same_seed_picks_the_same_attacks() -> void:
	var first := _picks(RANDOM, [1.0, 1.0, 1.0], [true, true, true])
	rng.seed = 1
	assert_array(_picks(RANDOM, [1.0, 1.0, 1.0], [true, true, true])).is_equal(first)


func _pick(choice: DummyKind.AttackChoice, weights: Array, usable: Array) -> int:
	var typed: Array[bool] = []
	typed.assign(usable)
	return AttackChoice.pick(choice, PackedFloat32Array(weights), typed, 0, rng)


func _picks(choice: DummyKind.AttackChoice, weights: Array, usable: Array) -> Array[int]:
	var out: Array[int] = []
	for i in PICKS:
		out.append(_pick(choice, weights, usable))
	return out


## The share of PICKS each attack got.
func _shares(choice: DummyKind.AttackChoice, weights: Array, usable: Array) -> Array[float]:
	var out: Array[float] = []
	out.resize(weights.size())
	out.fill(0.0)
	for picked in _picks(choice, weights, usable):
		out[picked] += 1.0 / PICKS
	return out

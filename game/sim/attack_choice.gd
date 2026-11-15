extends RefCounted
## Which of a dummy's attacks it makes when its aim locks. The world sets
## each dummy's [enum Rule] from its kind's attack choice.

## How a dummy picks.
enum Rule {
	## At random by weight, among the attacks it can make now. With none, it
	## picks none.
	WEIGHTED_VALID,
	## At random by weight, among all its attacks.
	WEIGHTED_RANDOM,
	## The next in turn, whether it can make it or not.
	CYCLE,
}


## The index of the attack to make, or -1 for none. [param weights] and
## [param usable] have one entry per attack, in list order; [param usable]
## is whether each can be made now. [param next_in_cycle] is the index
## CYCLE makes next.
static func pick(rule: Rule, weights: PackedFloat32Array,
		usable: Array[bool], next_in_cycle: int, rng: RandomNumberGenerator) -> int:
	var candidates: Array[int] = []
	match rule:
		Rule.CYCLE:
			return next_in_cycle
		Rule.WEIGHTED_RANDOM:
			candidates.assign(range(weights.size()))
		Rule.WEIGHTED_VALID:
			for i in weights.size():
				if usable[i]:
					candidates.append(i)
	return _weighted(candidates, weights, rng)


## One of [param candidates] at random, each as likely as its weight
## against theirs; when their weights are all 0, each as likely as the
## others. -1 for none.
static func _weighted(candidates: Array[int], weights: PackedFloat32Array,
		rng: RandomNumberGenerator) -> int:
	if candidates.size() <= 1:
		return candidates[0] if candidates else -1
	var total := 0.0
	for i in candidates:
		total += weights[i]
	if total == 0:
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var roll := rng.randf() * total
	var last := -1
	for i in candidates:
		if weights[i] == 0:
			continue
		last = i
		roll -= weights[i]
		if roll < 0:
			return i
	# randf() can return 1.0.
	return last

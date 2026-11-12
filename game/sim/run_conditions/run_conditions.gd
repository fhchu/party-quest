extends RefCounted
## Builds run conditions from balance.json's entries, by their names.

const DataLoader := preload("res://shared/data_loader.gd")
const GameTime := preload("res://shared/game_time.gd")
const RunCondition := preload("res://sim/run_conditions/run_condition.gd")
const DefeatAll := preload("res://sim/run_conditions/defeat_all.gd")
const PartyDowned := preload("res://sim/run_conditions/party_downed.gd")
const TimeUp := preload("res://sim/run_conditions/time_up.gd")


static func from_entries(entries: Array[DataLoader.ConditionEntry]) -> Array[RunCondition]:
	var out: Array[RunCondition] = []
	for entry in entries:
		match entry.name:
			"defeat_all":
				out.append(DefeatAll.new(DataLoader.dummy_kind(entry.arg)))
			"party_downed":
				out.append(PartyDowned.new())
			"time_up_sec":
				out.append(TimeUp.new(GameTime.ticks(entry.arg)))
			_:
				push_error("no run condition named \"%s\"" % entry.name)
	return out

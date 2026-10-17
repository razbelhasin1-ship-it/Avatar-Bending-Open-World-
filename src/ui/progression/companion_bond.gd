class_name CompanionBond
extends RefCounted
## The bond with the companion, as a record of the journey shared with it: rides taken,
## distance ridden and flown together (the companions module counts these in
## GameState.stats) and time travelled side by side. Written to GameState.companion["bond"]
## (the save field the foundation reserved) so the character page and any later system can
## read one number; tiers name it.
##
##   CompanionBond.points()   # 0..MAX
##   CompanionBond.tier()     # {index, name, from, to}
##   CompanionBond.sync()     # recompute + store (the progression hook, 1 Hz)

const MAX := 1000
const TIERS: Array[Dictionary] = [
	{"name": "New Companion", "from": 0},
	{"name": "Familiar", "from": 60},
	{"name": "Trusted", "from": 160},
	{"name": "Devoted", "from": 340},
	{"name": "Kindred Spirits", "from": 600},
]


static func rides() -> int:
	return int(GameState.stats.get("companion_rides", 0))


static func ridden_km() -> float:
	return float(GameState.stats.get("companion_ridden_m", 0)) / 1000.0


static func flown_km() -> float:
	return float(GameState.stats.get("companion_flown_m", 0)) / 1000.0


static func hours_together() -> float:
	return GameState.play_time / 3600.0


static func points() -> int:
	var p := rides() * 5.0 + ridden_km() * 10.0 + flown_km() * 8.0 + hours_together() * 6.0
	return clampi(int(floor(p)), 0, MAX)


static func tier(p: int = -1) -> Dictionary:
	var pts := points() if p < 0 else p
	var idx := 0
	for i in TIERS.size():
		if pts >= int(TIERS[i]["from"]):
			idx = i
	var nxt := int(TIERS[idx + 1]["from"]) if idx + 1 < TIERS.size() else MAX
	return {"index": idx, "name": String(TIERS[idx]["name"]), "from": int(TIERS[idx]["from"]), "to": nxt}


## Progress 0..1 inside the current tier.
static func tier_progress(p: int = -1) -> float:
	var pts := points() if p < 0 else p
	var t := tier(pts)
	return clampf(float(pts - int(t["from"])) / maxf(float(int(t["to"]) - int(t["from"])), 1.0), 0.0, 1.0)


static func sync() -> void:
	GameState.companion["bond"] = points()

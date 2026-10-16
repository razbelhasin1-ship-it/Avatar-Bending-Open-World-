class_name NpcLooks
extends RefCounted
## Nation-appropriate HumanoidRig configs for crowd NPCs. Seeds come from a small fixed set per
## (preset, body, age) so a whole city shares a bounded number of mesh variants
## (CharacterMeshBuilder caches per appearance): about 25 per nation, pre-built during loading
## for the home nation (`variant_configs`). Pure data: safe on worker threads.

const SEEDS := 2

## Settlement id -> nation id.
const SETTLEMENT_NATION := {
	&"northern_water_tribe": &"water", &"arctic_villages": &"water", &"southern_air_temple": &"air",
	&"ba_sing_se": &"earth", &"omashu": &"earth", &"ek_villages": &"earth",
	&"fire_nation_capital": &"fire", &"fire_harbor": &"fire", &"fn_villages": &"fire",
}

## Per nation: preset by look family.
const PRESETS := {
	&"water": {"civilian": [&"villager_water", &"water_tribe"], "guard": &"water_warrior", "merchant": &"water_tribe", "elder": &"water_tribe", "monk": &"water_tribe"},
	&"earth": {"civilian": [&"villager_earth", &"earth_kingdom"], "guard": &"earth_soldier", "merchant": &"merchant", "elder": &"earth_kingdom", "monk": &"earth_kingdom"},
	&"fire": {"civilian": [&"villager_fire", &"fire_nation"], "guard": &"fire_soldier", "merchant": &"merchant", "elder": &"fire_nation", "monk": &"fire_nation"},
	&"air": {"civilian": [&"air_nomad", &"villager_air"], "guard": &"air_nomad", "merchant": &"villager_air", "elder": &"monk_elder", "monk": &"air_nomad"},
}

## Palette tweaks so merchants read per nation (the shared merchant preset is green-gold).
const MERCHANT_PALETTE := {
	&"fire": {"robe": Color(0.62, 0.16, 0.12), "trim": Color(0.86, 0.62, 0.22)},
}

const ROLES: Array[StringName] = [&"resident", &"child", &"elder", &"guard", &"merchant", &"monk"]


static func nation_of(settlement: StringName) -> StringName:
	return SETTLEMENT_NATION.get(settlement, &"earth")


## Look family of a role.
static func family_of(role: StringName) -> String:
	match role:
		&"guard", &"patrol":
			return "guard"
		&"merchant":
			return "merchant"
		&"elder", &"healer":
			return "elder"
		&"monk", &"student":
			return "monk"
		&"child":
			return "child"
	return "civilian"


## Crowd look for a role; `h` is a deterministic hash (anchor id) choosing body / variant.
static func crowd_look(nation: StringName, role: StringName, h: int) -> Dictionary:
	var p: Dictionary = PRESETS.get(nation, PRESETS[&"earth"])
	var fam := family_of(role)
	var hu := absi(h)
	var body := "female" if (hu >> 3) % 2 == 0 else "male"
	var age := "adult"
	var seed_v := 1 + (hu >> 9) % SEEDS
	var civ: Array = p["civilian"]
	var preset: StringName = civ[(hu >> 5) % civ.size()]
	match fam:
		"child":
			age = "child"
			preset = civ[0]
		"elder":
			age = "elder"
			preset = p["elder"]
		"guard":
			preset = p["guard"]
			if nation != &"air":
				body = "male" if (hu >> 3) % 4 != 0 else "female"
				if body == "female":
					seed_v = 1
		"merchant":
			preset = p["merchant"]
			seed_v = 1
		"monk":
			preset = p["monk"]
	var cfg := {"preset": preset, "body": body, "age": age, "seed": seed_v}
	if fam == "merchant" and MERCHANT_PALETTE.has(nation):
		cfg["palette"] = MERCHANT_PALETTE[nation]
	return cfg


## Every crowd variant of a nation (pre-built during loading so spawning rarely builds a mesh).
static func variant_configs(nation: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	for role in ROLES:
		for h in range(0, 4096, 1):
			var c := crowd_look(nation, role, h * 8)
			var key := "%s|%s|%s|%s" % [c["preset"], c["body"], c["age"], c["seed"]]
			if not seen.has(key):
				seen[key] = true
				out.append(c)
	return out

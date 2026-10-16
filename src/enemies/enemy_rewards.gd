class_name EnemyRewards
extends RefCounted
## Defeat rewards: XP (GameState.add_xp) and loot rolled from the archetype's table
## (coins go to GameState.currency, everything else to the inventory via
## GameState.add_item -> Events.item_collected), one HUD toast per defeat and a
## small sparkle at the body. Surrendering enemies hand over their loot too; fled
## enemies give half XP and no loot.

const ITEM_NAMES := {
	&"copper_coins": "Copper Coins", &"silver_coins": "Silver Coins", &"cloth_scrap": "Cloth Scrap", &"arrows": "Arrows",
	&"iron_scrap": "Iron Scrap", &"fire_nation_insignia": "Fire Nation Insignia", &"jade_shard": "Jade Shard",
	&"sea_salt": "Sea Salt", &"komodo_hide": "Komodo Rhino Hide",
}
const COIN_VALUE := {&"copper_coins": 1, &"silver_coins": 10}

## Totals granted this session (tests / debugging).
static var xp_granted := 0
static var items_granted := 0


static func item_name(id: StringName) -> String:
	return ITEM_NAMES.get(id, String(id).capitalize())


## Rolls the loot table with `rng`: [{"item", "count"}].
static func roll_loot(table: Array, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in table:
		if rng.randf() <= float(entry.get("chance", 1.0)):
			var n := rng.randi_range(int(entry.get("min", 1)), int(entry.get("max", 1)))
			if n > 0:
				out.append({"item": StringName(entry.get("item", &"")), "count": n})
	return out


static func xp_for(e: EnemyBase, how: StringName) -> int:
	var xp := float(e.archetype.get("xp", 20)) * (1.0 + 0.15 * (e.level - 1))
	if how == &"fled":
		xp *= 0.5
	return int(round(xp))


## Grants the rewards of defeating `e` (how: &"killed", &"surrendered", &"fled").
static func grant(e: EnemyBase, how: StringName) -> Dictionary:
	var xp := xp_for(e, how)
	var loot: Array[Dictionary] = []
	if how != &"fled":
		loot = roll_loot(e.archetype.get("loot", []), e.rng)
	if GameState.is_tutorial:
		return {"xp": 0, "loot": []}
	GameState.add_xp(xp, "Defeated %s" % e.display_name)
	xp_granted += xp
	var parts: PackedStringArray = ["+%d XP" % xp]
	for l: Dictionary in loot:
		var id: StringName = l["item"]
		var n := int(l["count"])
		if COIN_VALUE.has(id):
			GameState.currency += n * int(COIN_VALUE[id])
			Events.item_collected.emit(id, n)
		else:
			GameState.add_item(id, n)
		items_granted += n
		parts.append("%s ×%d" % [item_name(id), n])
	var verb: String = {&"surrendered": "surrendered", &"fled": "fled"}.get(how, "defeated")
	Events.notify.emit("%s %s  ·  %s" % [e.display_name, verb, "  ·  ".join(parts)], &"info")
	if e.is_inside_tree():
		FxBurst.spawn(e, &"sparkle", e.global_position + Vector3.UP * 0.8, {"count": 0.8, "color": Color(1.0, 0.85, 0.4)})
	return {"xp": xp, "loot": loot}

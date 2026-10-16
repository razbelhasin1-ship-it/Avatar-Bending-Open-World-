class_name TradeGoods
extends RefCounted
## Item catalog: every item id the game hands out (enemy loot, resource pickups, quest rewards,
## merchant goods, quest items) with display data, prices and use effects. The inventory UI reads
## it (`info(id)`), merchants price with it and `use_item(id, player)` applies consumables.
##
##   TradeGoods.info(&"arctic_moss")   # {name, desc, category, value, nation, color, use, sellable, stack}
##   TradeGoods.display_name(&"jade_shard")
##   TradeGoods.sell_price(&"jade_shard") / buy_price(&"jade_shard", markup)
##   TradeGoods.use_item(&"arctic_moss", player) -> bool       # consumes one when it has a `use`
##
## Categories: herb, food, drink, supply, trinket, material, goods, quest. Values are in copper
## coins (GameState.currency). `use`: {"heal": hp, "chi": amount}.

const CATEGORIES: Array[StringName] = [&"herb", &"food", &"drink", &"supply", &"trinket", &"material", &"goods", &"quest"]

const ITEMS := {
	# --- herbs (heal) ---------------------------------------------------------------------------
	&"arctic_moss": {"name": "Arctic Healing Moss", "desc": "Pale moss scraped from sheltered ice. The healers steep it for frostbite and bruises.", "category": &"herb", "value": 8, "nation": &"water", "color": Color(0.62, 0.84, 0.74), "use": {"heal": 25}},
	&"ginseng_root": {"name": "Ginseng Root", "desc": "A forked root from the Earth Kingdom hills. Chewed raw it steadies the heart.", "category": &"herb", "value": 10, "nation": &"earth", "color": Color(0.86, 0.72, 0.48), "use": {"heal": 30}},
	&"fire_lily": {"name": "Fire Lily", "desc": "A red lily that grows on warm volcanic soil. Its sap soothes burns.", "category": &"herb", "value": 12, "nation": &"fire", "color": Color(0.92, 0.34, 0.22), "use": {"heal": 30}},
	&"mountain_sage": {"name": "Mountain Sage", "desc": "Silver-leafed sage from the high terraces. The monks burn it before meditation.", "category": &"herb", "value": 9, "nation": &"air", "color": Color(0.70, 0.80, 0.66), "use": {"heal": 20, "chi": 25}},
	&"herb": {"name": "Wild Herbs", "desc": "A bundle of common healing herbs.", "category": &"herb", "value": 5, "nation": &"", "color": Color(0.48, 0.74, 0.40), "use": {"heal": 15}},
	&"spirit_blossom": {"name": "Spirit Blossom", "desc": "A flower that only grows where the spirit world brushes this one. It hums faintly.", "category": &"herb", "value": 40, "nation": &"", "color": Color(0.74, 0.86, 1.0), "use": {"heal": 60, "chi": 60}},
	&"healing_salve": {"name": "Healing Salve", "desc": "A tin of herbal salve prepared by a healer.", "category": &"herb", "value": 24, "nation": &"", "color": Color(0.88, 0.80, 0.56), "use": {"heal": 55}},
	# --- food / drink ----------------------------------------------------------------------------
	&"sea_prunes": {"name": "Stewed Sea Prunes", "desc": "A Water Tribe staple. An acquired taste, and a warm one.", "category": &"food", "value": 4, "nation": &"water", "color": Color(0.42, 0.30, 0.46), "use": {"heal": 12}},
	&"smoked_fish": {"name": "Smoked Arctic Char", "desc": "Fish smoked over seal-oil fires, wrapped for the road.", "category": &"food", "value": 6, "nation": &"water", "color": Color(0.86, 0.56, 0.36), "use": {"heal": 18}},
	&"arctic_cod": {"name": "Arctic Cod", "desc": "Fresh from the morning nets.", "category": &"goods", "value": 5, "nation": &"water", "color": Color(0.66, 0.74, 0.82), "use": {"heal": 8}},
	&"rice_ball": {"name": "Rice Ball", "desc": "Sticky rice pressed around pickled plum.", "category": &"food", "value": 3, "nation": &"earth", "color": Color(0.96, 0.95, 0.90), "use": {"heal": 10}},
	&"egg_custard": {"name": "Egg Custard Tart", "desc": "A Ba Sing Se bakery favourite, still warm.", "category": &"food", "value": 5, "nation": &"earth", "color": Color(0.98, 0.82, 0.38), "use": {"heal": 14}},
	&"fire_flakes": {"name": "Fire Flakes", "desc": "Spicy crisps sold in paper cones on every Fire Nation street.", "category": &"food", "value": 3, "nation": &"fire", "color": Color(0.90, 0.36, 0.18), "use": {"heal": 8, "chi": 10}},
	&"komodo_jerky": {"name": "Komodo Jerky", "desc": "Tough, salty and filling.", "category": &"food", "value": 6, "nation": &"fire", "color": Color(0.56, 0.30, 0.22), "use": {"heal": 18}},
	&"fruit_pie": {"name": "Fruit Pie", "desc": "Baked by the temple cooks from orchard fruit. The crust is a work of art.", "category": &"food", "value": 5, "nation": &"air", "color": Color(0.86, 0.46, 0.52), "use": {"heal": 16}},
	&"jasmine_tea": {"name": "Jasmine Tea", "desc": "Loose leaves for a calm cup. Restores focus of mind.", "category": &"drink", "value": 7, "nation": &"earth", "color": Color(0.84, 0.88, 0.62), "use": {"chi": 50}},
	&"ginseng_tea": {"name": "Ginseng Tea", "desc": "Bitter, earthy, and good for the breath.", "category": &"drink", "value": 9, "nation": &"earth", "color": Color(0.72, 0.58, 0.34), "use": {"chi": 40, "heal": 10}},
	&"warm_broth": {"name": "Seal Broth", "desc": "A flask of steaming broth for a cold watch.", "category": &"drink", "value": 5, "nation": &"water", "color": Color(0.86, 0.74, 0.56), "use": {"heal": 10, "chi": 30}},
	# --- supplies --------------------------------------------------------------------------------
	&"rope_coil": {"name": "Coil of Rope", "desc": "Braided sinew rope, strong enough to hold a canoe.", "category": &"supply", "value": 6, "nation": &"", "color": Color(0.74, 0.62, 0.42)},
	&"lamp_oil": {"name": "Lamp Oil", "desc": "A stoppered jar of clean-burning oil.", "category": &"supply", "value": 5, "nation": &"", "color": Color(0.94, 0.80, 0.36)},
	&"waterskin": {"name": "Waterskin", "desc": "Every waterbender keeps one full.", "category": &"supply", "value": 8, "nation": &"water", "color": Color(0.44, 0.58, 0.78)},
	&"fishing_line": {"name": "Fishing Line", "desc": "Fine gut line with a bone hook.", "category": &"supply", "value": 4, "nation": &"water", "color": Color(0.82, 0.86, 0.88)},
	&"travel_rations": {"name": "Travel Rations", "desc": "Dried fruit, nuts and hard bread.", "category": &"food", "value": 6, "nation": &"", "color": Color(0.72, 0.58, 0.40), "use": {"heal": 15}},
	&"arrows": {"name": "Arrows", "desc": "Fletched arrows. Of no use to a bender, but traders buy them.", "category": &"material", "value": 1, "nation": &"", "color": Color(0.70, 0.62, 0.50)},
	# --- crafted goods (stalls) -------------------------------------------------------------------
	&"clay_bowl": {"name": "Glazed Bowl", "desc": "A potter's bowl with a blue wave glaze.", "category": &"goods", "value": 7, "nation": &"", "color": Color(0.50, 0.66, 0.84)},
	&"tea_pot": {"name": "Clay Teapot", "desc": "Round-bellied and honest. Every household needs one.", "category": &"goods", "value": 14, "nation": &"earth", "color": Color(0.64, 0.42, 0.30)},
	&"seal_pelt": {"name": "Seal Pelt", "desc": "Soft, waterproof and warm.", "category": &"goods", "value": 16, "nation": &"water", "color": Color(0.56, 0.54, 0.52)},
	&"fur_mittens": {"name": "Fur-Lined Mittens", "desc": "Stitched with the moon-and-wave pattern.", "category": &"goods", "value": 12, "nation": &"water", "color": Color(0.36, 0.48, 0.74)},
	&"silk_scarf": {"name": "Silk Scarf", "desc": "Fire Nation silk, red as a sunset.", "category": &"goods", "value": 18, "nation": &"fire", "color": Color(0.82, 0.18, 0.18)},
	# --- trinkets ---------------------------------------------------------------------------------
	&"carved_whale_tooth": {"name": "Carved Whale Tooth", "desc": "Scrimshaw of a canoe under the moon.", "category": &"trinket", "value": 22, "nation": &"water", "color": Color(0.96, 0.94, 0.86)},
	&"moon_pendant": {"name": "Moon Pendant", "desc": "A carved stone on a blue ribbon. Given as a promise.", "category": &"trinket", "value": 30, "nation": &"water", "color": Color(0.70, 0.84, 0.98)},
	&"jade_figurine": {"name": "Jade Badgermole", "desc": "A palm-sized badgermole carved from green jade.", "category": &"trinket", "value": 34, "nation": &"earth", "color": Color(0.36, 0.72, 0.46)},
	&"pai_sho_tile": {"name": "White Lotus Tile", "desc": "A Pai Sho tile. Some players think it is the most important piece.", "category": &"trinket", "value": 15, "nation": &"", "color": Color(0.96, 0.92, 0.84)},
	&"flame_charm": {"name": "Bronze Flame Charm", "desc": "Worn for courage in the Fire Nation.", "category": &"trinket", "value": 20, "nation": &"fire", "color": Color(0.84, 0.58, 0.24)},
	&"dragon_scale": {"name": "Dragon Scale Pendant", "desc": "Lacquered red, not a real scale. Probably.", "category": &"trinket", "value": 38, "nation": &"fire", "color": Color(0.74, 0.12, 0.10)},
	&"prayer_beads": {"name": "Prayer Beads", "desc": "Polished wooden beads, smooth from many hands.", "category": &"trinket", "value": 14, "nation": &"air", "color": Color(0.66, 0.46, 0.30)},
	&"bison_whistle": {"name": "Bison Whistle", "desc": "A carved whistle in the shape of a bison. Its note is too low for people to hear.", "category": &"trinket", "value": 26, "nation": &"air", "color": Color(0.96, 0.74, 0.30)},
	&"wind_chime": {"name": "Wind Chime", "desc": "Bamboo and brass. Sings with the smallest breeze.", "category": &"trinket", "value": 18, "nation": &"air", "color": Color(0.80, 0.70, 0.40)},
	# --- materials / loot -------------------------------------------------------------------------
	&"cloth_scrap": {"name": "Cloth Scrap", "desc": "Torn cloth. Tailors pay a little for it.", "category": &"material", "value": 2, "nation": &"", "color": Color(0.62, 0.58, 0.52)},
	&"iron_scrap": {"name": "Iron Scrap", "desc": "Bent iron from armour or tools.", "category": &"material", "value": 4, "nation": &"", "color": Color(0.46, 0.48, 0.52)},
	&"iron_ore": {"name": "Iron Ore", "desc": "Dull red ore from a quarry face.", "category": &"material", "value": 6, "nation": &"", "color": Color(0.58, 0.36, 0.30)},
	&"jade_shard": {"name": "Jade Shard", "desc": "Raw jade with a deep green glow.", "category": &"material", "value": 18, "nation": &"earth", "color": Color(0.30, 0.78, 0.52)},
	&"whale_bone": {"name": "Whale Bone", "desc": "Bleached bone, prized by carvers.", "category": &"material", "value": 12, "nation": &"water", "color": Color(0.92, 0.90, 0.82)},
	&"sea_salt": {"name": "Sea Salt", "desc": "Coarse salt from the evaporation pans.", "category": &"material", "value": 3, "nation": &"fire", "color": Color(0.94, 0.94, 0.94)},
	&"komodo_hide": {"name": "Komodo Rhino Hide", "desc": "Thick, scaled hide.", "category": &"material", "value": 20, "nation": &"fire", "color": Color(0.42, 0.40, 0.36)},
	&"fire_nation_insignia": {"name": "Fire Nation Insignia", "desc": "A soldier's flame badge. Proof of a fight.", "category": &"material", "value": 10, "nation": &"fire", "color": Color(0.86, 0.26, 0.16)},
	# --- quest items (not sold) -------------------------------------------------------------------
	&"navy_orders": {"name": "Sealed Navy Orders", "desc": "Fire Navy orders stamped with an admiral's seal. Chief Tulok will want to read them.", "category": &"quest", "value": 0, "nation": &"fire", "color": Color(0.86, 0.22, 0.16), "sellable": false},
	&"moon_water": {"name": "Water of the Oasis", "desc": "A vial of water from the koi pond. It is cold even in your hands.", "category": &"quest", "value": 0, "nation": &"water", "color": Color(0.70, 0.88, 1.0), "sellable": false},
	&"letter_northreach": {"name": "Letter to Northreach", "desc": "A sealed letter for the elder of Northreach Harbor.", "category": &"quest", "value": 0, "nation": &"", "color": Color(0.92, 0.86, 0.70), "sellable": false},
	&"letter_omashu": {"name": "Letter for Omashu", "desc": "Addressed in a careful hand to the mail clerk of Omashu.", "category": &"quest", "value": 0, "nation": &"earth", "color": Color(0.92, 0.86, 0.70), "sellable": false},
	&"letter_temple": {"name": "Letter to the Temple", "desc": "A letter for the abbot of the Southern Air Temple.", "category": &"quest", "value": 0, "nation": &"air", "color": Color(0.92, 0.86, 0.70), "sellable": false},
	&"tea_parcel": {"name": "Parcel of Tea", "desc": "A wrapped parcel of rare white dragon tea.", "category": &"quest", "value": 0, "nation": &"earth", "color": Color(0.80, 0.86, 0.64), "sellable": false},
	&"ember_stone": {"name": "Ember Stone", "desc": "A warm stone from the sun temple's altar. It glows when you breathe on it.", "category": &"quest", "value": 0, "nation": &"fire", "color": Color(0.98, 0.52, 0.18), "sellable": false},
	&"lost_glider": {"name": "Novice's Glider", "desc": "A student's glider staff, its wings a little torn.", "category": &"quest", "value": 0, "nation": &"air", "color": Color(0.94, 0.70, 0.30), "sellable": false},
	&"net_float": {"name": "Net Float", "desc": "A carved float from a fishing net.", "category": &"quest", "value": 0, "nation": &"water", "color": Color(0.84, 0.64, 0.40), "sellable": false},
	&"stolen_crate": {"name": "Merchant's Crate", "desc": "A crate of goods taken by smugglers.", "category": &"quest", "value": 0, "nation": &"fire", "color": Color(0.62, 0.46, 0.30), "sellable": false},
	&"admiral_letter": {"name": "Admiral's Letter", "desc": "A letter sealed in red wax with the Fire Navy's flame, addressed to Chief Tulok.", "category": &"quest", "value": 0, "nation": &"fire", "color": Color(0.94, 0.84, 0.70), "sellable": false},
	&"scout_orders": {"name": "Scout's Orders", "desc": "Orders carried by a Fire Nation scout: maps, numbers and a careful hand.", "category": &"quest", "value": 0, "nation": &"fire", "color": Color(0.90, 0.80, 0.62), "sellable": false},
	&"airball_ribbon": {"name": "Airball Ribbon", "desc": "A champion's ribbon from the temple courts.", "category": &"trinket", "value": 12, "nation": &"air", "color": Color(0.96, 0.66, 0.24)},
	&"spirit_incense": {"name": "Spirit Incense", "desc": "Incense for the shrine of the Pale Moon.", "category": &"quest", "value": 0, "nation": &"water", "color": Color(0.80, 0.74, 0.90), "sellable": false},
}

## Currency pseudo-items (enemy loot) and their value in copper.
const COINS := {&"copper_coins": 1, &"silver_coins": 10}


static func has_item(id: StringName) -> bool:
	return ITEMS.has(id) or COINS.has(id)


static func ids() -> Array:
	return ITEMS.keys()


static func info(id: StringName) -> Dictionary:
	var d: Dictionary = ITEMS.get(id, {})
	if d.is_empty():
		if COINS.has(id):
			return {"id": id, "name": "Silver Coins" if id == &"silver_coins" else "Copper Coins", "desc": "Currency.",
				"category": &"goods", "value": int(COINS[id]), "nation": &"", "color": Color(0.86, 0.70, 0.40), "use": {}, "sellable": false, "stack": 9999}
		return {"id": id, "name": String(id).capitalize(), "desc": "", "category": &"material", "value": 1, "nation": &"",
			"color": Color(0.7, 0.7, 0.7), "use": {}, "sellable": true, "stack": 99}
	var out := d.duplicate()
	out["id"] = id
	out["use"] = d.get("use", {})
	out["sellable"] = bool(d.get("sellable", true))
	out["stack"] = int(d.get("stack", 99))
	return out


static func display_name(id: StringName) -> String:
	return String(info(id)["name"])


static func category(id: StringName) -> StringName:
	return StringName(str(info(id)["category"]))


static func color(id: StringName) -> Color:
	return info(id)["color"]


## What a merchant asks (markup > 1 for rare goods / foreign markets).
static func buy_price(id: StringName, markup: float = 1.0) -> int:
	return maxi(1, int(round(float(info(id)["value"]) * markup)))


## What a merchant pays (0 = will not buy).
static func sell_price(id: StringName) -> int:
	var d := info(id)
	if not bool(d["sellable"]) or int(d["value"]) <= 0:
		return 0
	return maxi(1, int(floor(float(d["value"]) * 0.45)))


static func is_usable(id: StringName) -> bool:
	return not (info(id)["use"] as Dictionary).is_empty()


## Uses one item from the inventory on the player: heals / restores chi. Returns true when used.
static func use_item(id: StringName, player: Node = null) -> bool:
	if GameState.item_count(id) <= 0 or not is_usable(id):
		return false
	var use: Dictionary = info(id)["use"]
	var p: Node = player if player != null else Quests.get_player()
	var did := false
	if p != null:
		var h: Variant = p.get("health")
		if h is HealthComponent and int(use.get("heal", 0)) > 0:
			var hc: HealthComponent = h
			if hc.health < hc.max_health:
				hc.health = minf(hc.max_health, hc.health + float(use["heal"]))
				hc.changed.emit(hc.health, hc.max_health)
				Events.player_healed.emit(float(use["heal"]))
				did = true
		var res: Variant = p.get("resources")
		if res is PlayerResources and int(use.get("chi", 0)) > 0:
			var pr: PlayerResources = res
			if pr.chi < PlayerResources.CHI_MAX:
				pr.set_chi(minf(PlayerResources.CHI_MAX, pr.chi + float(use["chi"])))
				did = true
	if not did:
		return false
	GameState.add_item(id, -1)
	Events.notify.emit("Used %s" % display_name(id), &"info")
	return true

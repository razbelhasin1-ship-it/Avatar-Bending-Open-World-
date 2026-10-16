class_name MerchantStock
extends RefCounted
## What merchants sell and buy. Named shops are listed in SHOPS; every market-stall NPC gets a
## stall shop from its nation and the anchor's goods (fish / pottery / furs / trinkets). Prices
## come from TradeGoods (foreign goods cost 30 % more); limited stock restocks every game day
## (48 real minutes at the default clock) and is remembered in GameState.world_flags["shops"].
##
##   MerchantStock.stock(&"stall_water_fish")  # [{item, price, left (-1 = plenty)}]
##   MerchantStock.buy(&"stall_water_fish", &"smoked_fish")   # -> &"" or &"coins" / &"sold_out"
##   MerchantStock.sell(&"jade_shard")                         # -> coins received (0 = will not buy)

const DAY_SECONDS := 2880.0

## shop id -> {name, nation, items: {item: limit (-1 = plenty)}}
const SHOPS := {
	&"nwt_healer": {"name": "Healer's Remedies", "nation": &"water", "items": {&"herb": -1, &"healing_salve": 4, &"warm_broth": -1, &"spirit_blossom": 1}},
	&"nwt_outfitter": {"name": "Harbour Outfitter", "nation": &"water", "items": {&"waterskin": 3, &"rope_coil": -1, &"lamp_oil": -1, &"fishing_line": -1, &"smoked_fish": -1, &"travel_rations": -1}},
	&"bss_tea_house": {"name": "The Jasmine Kettle", "nation": &"earth", "items": {&"jasmine_tea": -1, &"ginseng_tea": -1, &"egg_custard": -1, &"rice_ball": -1, &"tea_pot": 2}},
	&"bss_herbalist": {"name": "Root and Leaf", "nation": &"earth", "items": {&"ginseng_root": -1, &"healing_salve": 4, &"herb": -1, &"travel_rations": -1}},
	&"fnc_apothecary": {"name": "Ember Apothecary", "nation": &"fire", "items": {&"fire_lily": -1, &"healing_salve": 4, &"fire_flakes": -1, &"komodo_jerky": -1}},
	&"fnc_jeweller": {"name": "Sunfire Jewels", "nation": &"fire", "items": {&"flame_charm": 3, &"dragon_scale": 1, &"silk_scarf": 2, &"pai_sho_tile": 2}},
	&"sat_kitchen": {"name": "Temple Kitchens", "nation": &"air", "items": {&"fruit_pie": -1, &"mountain_sage": -1, &"travel_rations": -1}},
	&"sat_novices": {"name": "Novices' Crafts", "nation": &"air", "items": {&"prayer_beads": 3, &"wind_chime": 2, &"bison_whistle": 1}},
}

## Stall goods per nation (ambient merchants).
const STALLS := {
	&"water": {"fish": [&"arctic_cod", &"smoked_fish", &"sea_prunes"], "pottery": [&"clay_bowl", &"warm_broth"], "furs": [&"seal_pelt", &"fur_mittens"],
		"trinkets": [&"carved_whale_tooth", &"moon_pendant", &"pai_sho_tile"], "": [&"sea_prunes", &"arctic_moss", &"rope_coil"]},
	&"earth": {"fish": [&"rice_ball", &"egg_custard"], "pottery": [&"tea_pot", &"clay_bowl"], "furs": [&"silk_scarf"],
		"trinkets": [&"jade_figurine", &"pai_sho_tile"], "vegetables": [&"rice_ball", &"ginseng_root", &"egg_custard"],
		"cloth": [&"silk_scarf", &"rope_coil"], "tea": [&"jasmine_tea", &"ginseng_tea", &"tea_pot"], "cabbages": [&"rice_ball", &"travel_rations"],
		"tools": [&"rope_coil", &"lamp_oil", &"waterskin"], "": [&"ginseng_root", &"jasmine_tea", &"rice_ball", &"egg_custard"]},
	&"fire": {"fish": [&"smoked_fish", &"fire_flakes"], "pottery": [&"clay_bowl", &"tea_pot"], "furs": [&"silk_scarf"], "cloth": [&"silk_scarf"],
		"spices": [&"fire_flakes", &"komodo_jerky", &"fire_lily"], "fireworks": [&"flame_charm", &"lamp_oil"],
		"trinkets": [&"flame_charm", &"dragon_scale", &"pai_sho_tile"], "": [&"fire_flakes", &"komodo_jerky", &"fire_lily"]},
	&"air": {"": [&"fruit_pie", &"mountain_sage", &"prayer_beads", &"wind_chime"]},
}


static func shop_id_for(npc: Node) -> StringName:
	if npc == null:
		return &"stall_earth_"
	var nid := StringName(str(npc.get("npc_id")))
	if nid != &"":
		var s := StringName(str(NpcRegistry.get_npc(nid).get("shop", "")))
		if s != &"":
			return s
	var rec: Dictionary = npc.get("record")
	return StringName("stall_%s_%s" % [rec.get("nation", &"earth"), rec.get("goods", "")])


static func shop_def(shop: StringName) -> Dictionary:
	if SHOPS.has(shop):
		return SHOPS[shop]
	var s := String(shop)
	if s.begins_with("stall_"):
		var parts := s.substr(6).split("_", true, 1)
		var nation := StringName(parts[0])
		var goods := parts[1] if parts.size() > 1 else ""
		var table: Dictionary = STALLS.get(nation, STALLS[&"earth"])
		var list: Array = table.get(goods, table.get("", []))
		var items := {}
		for it: Variant in list:
			items[it] = 6 if TradeGoods.category(StringName(str(it))) == &"trinket" else -1
		return {"name": "%s Stall" % NpcBarks.role_title(&"merchant", nation, goods), "nation": nation, "items": items}
	return {"name": "Merchant", "nation": &"", "items": {}}


static func _day() -> int:
	return int(floor(GameState.play_time / DAY_SECONDS))


static func _sold(shop: StringName) -> Dictionary:
	var all: Dictionary = GameState.world_flags.get("shops", {})
	var rec: Dictionary = all.get(String(shop), {})
	if int(rec.get("day", -1)) != _day():
		rec = {"day": _day(), "sold": {}}
	return rec


static func price(shop: StringName, item: StringName) -> int:
	var nation: StringName = shop_def(shop).get("nation", &"")
	var inat := StringName(str(TradeGoods.info(item).get("nation", "")))
	var markup := 1.3 if inat != &"" and nation != &"" and inat != nation else 1.0
	return TradeGoods.buy_price(item, markup)


static func stock(shop: StringName) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var items: Dictionary = shop_def(shop).get("items", {})
	var sold: Dictionary = _sold(shop)["sold"]
	for it: Variant in items:
		var id := StringName(str(it))
		var limit := int(items[it])
		var left := -1 if limit < 0 else maxi(0, limit - int(sold.get(String(id), 0)))
		out.append({"item": id, "price": price(shop, id), "left": left})
	return out


## Buys `n` of `item`. Returns &"" on success, else &"coins", &"sold_out", &"unknown".
static func buy(shop: StringName, item: StringName, n: int = 1) -> StringName:
	var row: Dictionary = {}
	for r in stock(shop):
		if r["item"] == item:
			row = r
	if row.is_empty():
		return &"unknown"
	if int(row["left"]) >= 0 and int(row["left"]) < n:
		return &"sold_out"
	var cost := int(row["price"]) * n
	if GameState.currency < cost:
		return &"coins"
	GameState.currency -= cost
	GameState.add_item(item, n)
	var rec := _sold(shop)
	var sold: Dictionary = rec["sold"]
	sold[String(item)] = int(sold.get(String(item), 0)) + n
	rec["sold"] = sold
	var all: Dictionary = GameState.world_flags.get("shops", {})
	all[String(shop)] = rec
	GameState.world_flags["shops"] = all
	GameState.incr_stat("items_bought", n)
	return &""


## Sells `n` of `item` from the inventory. Returns the coins received (0 = refused).
static func sell(item: StringName, n: int = 1) -> int:
	var each := TradeGoods.sell_price(item)
	var have := GameState.item_count(item)
	if each <= 0 or have <= 0:
		return 0
	var k := mini(n, have)
	GameState.add_item(item, -k)
	GameState.currency += each * k
	GameState.incr_stat("items_sold", k)
	return each * k


## Inventory items a merchant will buy: [{item, count, price}].
static func sellable() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k: Variant in GameState.inventory:
		var id := StringName(str(k))
		var p := TradeGoods.sell_price(id)
		if p > 0 and GameState.item_count(id) > 0:
			out.append({"item": id, "count": GameState.item_count(id), "price": p})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return TradeGoods.display_name(a["item"]) < TradeGoods.display_name(b["item"]))
	return out

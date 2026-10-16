extends RefCounted
## Fire Nation quests: the Fire opening chain (A Spark Returns -> Breath of Fire -> Smoke over the
## Cove -> The Sun's Teaching) and side quests around the capital. Format:
## docs/modules/quests_npcs.md.

const QUESTS := [
	{
		"id": &"fn_a_spark_returns", "title": "A Spark Returns", "kind": &"main", "nation": &"fire", "giver": &"fn_kaida",
		"location": "Fire Nation Capital",
		"summary": "The palace has noticed the fire in you, and arranged a master. Of course it has.",
		"auto_start": {"element": &"fire"},
		"stages": [
			{"id": &"arrive", "text": "Envoy Kaida of the palace was waiting on the terrace.", "objectives": [
				{"id": &"meet_kaida", "type": &"talk_to", "npc": &"fn_kaida", "text": "Speak with Envoy Kaida"}]},
			{"id": &"kata", "text": "Master Jinzo teaches at the Flame Kata Grounds below the palace terrace.", "objectives": [
				{"id": &"find_grounds", "type": &"go_to", "target": {"poi": &"fn_flame_kata_grounds"}, "radius": 28.0, "text": "Go down to the Flame Kata Grounds"},
				{"id": &"meet_master", "type": &"talk_to", "npc": &"fn_jinzo", "text": "Present yourself to Master Jinzo"}]},
		],
		"rewards": {"xp": 60},
		"next": &"fn_breath_of_fire",
	},
	{
		"id": &"fn_breath_of_fire", "title": "Breath of Fire", "kind": &"main", "nation": &"fire", "giver": &"fn_jinzo",
		"location": "Flame Kata Grounds",
		"summary": "Jinzo's first lesson: eight strikes on the posts, each one a short breath.",
		"stages": [
			{"id": &"posts", "text": "Jab, jab, kick. Breathe out with every strike.", "objectives": [
				{"id": &"posts", "type": &"challenge", "npc": &"fn_jinzo", "text": "Strike the training posts with your fire combo (talk to Jinzo)",
					"challenge": {"kind": &"targets", "title": "Breath of Fire", "count": 3, "hits": 8, "slot": &"light", "time": 55.0}}]},
			{"id": &"report", "text": "My kicks are lazy, my fists honest, according to Jinzo.", "objectives": [
				{"id": &"report", "type": &"talk_to", "npc": &"fn_jinzo", "text": "Report to Master Jinzo"}]},
		],
		"rewards": {"xp": 90, "items": {&"fire_flakes": 3}},
		"next": &"fn_smoke_over_the_cove",
	},
	{
		"id": &"fn_smoke_over_the_cove", "title": "Smoke over the Cove", "kind": &"main", "nation": &"fire", "giver": &"fn_rina",
		"location": "Smugglers' Cove",
		"summary": "Smugglers run stolen goods out of a cove north-east of the capital. The palace wants it handled quietly.",
		"stages": [
			{"id": &"gate", "text": "Captain Rina guards the Dragon's Throat, the gorge out of the caldera.", "objectives": [
				{"id": &"orders", "type": &"talk_to", "npc": &"fn_rina", "text": "Speak with Captain Rina at the Dragon's Throat"}]},
			{"id": &"scout", "text": "The cove lies north-east along the coast, down the gorge road.", "objectives": [
				{"id": &"scout", "type": &"go_to", "target": {"site": &"fn_smugglers_cove"}, "radius": 45.0, "text": "Find the Smugglers' Cove"}]},
			{"id": &"fight", "text": "Pirates, a waterbender among them, and a stolen crate.", "objectives": [
				{"id": &"drive", "type": &"defeat", "site": &"fn_smugglers_cove", "count": 3, "text": "Drive off the smugglers"},
				{"id": &"crate", "type": &"collect", "item": &"stolen_crate", "count": 1, "text": "Recover the merchant's crate",
					"props": [{"at": {"site": &"fn_smugglers_cove", "offset": Vector3(-2.0, 0, 2.0)}, "kind": &"crate", "prompt": "Take the stolen crate"}]}]},
			{"id": &"report", "text": "The crate is intact. Captain Rina will want it.", "objectives": [
				{"id": &"report", "type": &"talk_to", "npc": &"fn_rina", "text": "Bring the crate to Captain Rina"}]},
		],
		"rewards": {"xp": 220, "currency": 40, "items": {&"healing_salve": 2}},
		"next": &"fn_the_suns_teaching",
	},
	{
		"id": &"fn_the_suns_teaching", "title": "The Sun's Teaching", "kind": &"main", "nation": &"fire", "giver": &"fn_mirei",
		"location": "Shrine of the Eternal Flame",
		"summary": "Jinzo teaches the strike. Sage Mirei teaches where it comes from.",
		"stages": [
			{"id": &"sage", "text": "Jinzo sent me to Sage Mirei at the temple on the palace terrace.", "objectives": [
				{"id": &"meet_sage", "type": &"talk_to", "npc": &"fn_mirei", "text": "Speak with Sage Mirei at the temple"}]},
			{"id": &"flame", "text": "The Shrine of the Eternal Flame burns west across the caldera rim. It has not gone out in a thousand years.", "objectives": [
				{"id": &"shrine", "type": &"discover", "poi": &"fn_eternal_flame", "text": "Find the Shrine of the Eternal Flame"},
				{"id": &"sit", "type": &"interact", "key": &"eternal_flame", "text": "Sit before the eternal flame and breathe",
					"props": [{"at": {"poi": &"fn_eternal_flame", "offset": Vector3(0, 0, 3.2)}, "kind": &"incense", "prompt": "Sit before the flame"}]}]},
			{"id": &"report", "text": "It never goes out because it never fights the wind.", "objectives": [
				{"id": &"report", "type": &"talk_to", "npc": &"fn_jinzo", "text": "Return to Master Jinzo"}]},
		],
		"rewards": {"xp": 260, "currency": 30, "techniques": [&"fire_burst", &"fire_ring", &"jet_step", &"fire_whip", &"inferno"]},
		"on_complete": [["flag", "fn_chain_done"]],
	},
	# --- side quests -------------------------------------------------------------------------
	{
		"id": &"fn_overgrown_sun_temple", "title": "The Overgrown Sun Temple", "kind": &"side", "nation": &"fire", "giver": &"fn_mirei",
		"location": "Overgrown Sun Temple", "requires": {"quest": [&"fn_a_spark_returns", "completed"]},
		"summary": "An ember stone lies on the altar of a forgotten sun temple in the western jungle.",
		"stages": [
			{"id": &"find", "text": "The temple lies in the jungle west of the capital.", "objectives": [
				{"id": &"find", "type": &"discover", "poi": &"fn_overgrown_sun_temple", "text": "Find the Overgrown Sun Temple"},
				{"id": &"stone", "type": &"collect", "item": &"ember_stone", "count": 1, "text": "Take the ember stone from the altar",
					"props": [{"at": {"poi": &"fn_overgrown_sun_temple", "offset": Vector3(0, 0, 2.5)}, "kind": &"ember", "prompt": "Lift the ember stone"}]}]},
			{"id": &"return", "text": "The stone is warm without fire.", "objectives": [
				{"id": &"return", "type": &"talk_to", "npc": &"fn_mirei", "text": "Bring the ember stone to Sage Mirei"}]},
		],
		"rewards": {"xp": 130, "currency": 20, "items": {&"flame_charm": 1}},
	},
	{
		"id": &"fn_kata_under_the_sun", "title": "Kata Under the Sun", "kind": &"training", "nation": &"fire", "giver": &"fn_jinzo",
		"location": "Flame Kata Grounds", "requires": {"quest": [&"fn_breath_of_fire", "completed"], "element": &"fire"},
		"summary": "Every noon the students run the kata under the sun. Techniques only.",
		"stages": [
			{"id": &"kata", "text": "Four technique strikes on the posts before the sun moves.", "objectives": [
				{"id": &"kata", "type": &"challenge", "npc": &"fn_jinzo", "text": "Run the kata: land techniques on the posts (talk to Jinzo)",
					"challenge": {"kind": &"targets", "title": "Kata Under the Sun", "count": 3, "hits": 4, "slot": &"technique", "time": 45.0}}]},
		],
		"rewards": {"xp": 90, "currency": 20},
	},
	{
		"id": &"fn_komodo_trouble", "title": "Komodo Trouble", "kind": &"side", "nation": &"fire", "giver": &"fn_hoshi",
		"location": "Cinder Flats", "requires": {"quest": [&"fn_a_spark_returns", "completed"]},
		"summary": "Komodo rhinos from the Cinder Flats trample the Ashleaf tea terraces at night.",
		"stages": [
			{"id": &"drive", "text": "The rhinos graze in the Cinder Flats south of the terraces.", "objectives": [
				{"id": &"drive", "type": &"defeat", "site": &"fn_cinder_flats_den", "count": 2, "text": "Drive the komodo rhinos from the Cinder Flats"}]},
			{"id": &"return", "text": "The flats are quiet. The terraces are safe.", "objectives": [
				{"id": &"return", "type": &"talk_to", "npc": &"fn_hoshi", "text": "Tell Elder Hoshi at the Ashleaf Terraces"}]},
		],
		"rewards": {"xp": 150, "currency": 35, "items": {&"fire_lily": 3}},
	},
]

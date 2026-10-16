extends RefCounted
## Cross-nation quests: errands that carry the player between the nations by ferry or flight.
## Format: docs/modules/quests_npcs.md.

const QUESTS := [
	{
		"id": &"tr_letters_across_the_strait", "title": "Letters Across the Strait", "kind": &"travel", "nation": &"water", "giver": &"wt_oki",
		"location": "Northreach Harbor, Earth Kingdom", "requires": {"quest": [&"wt_born_of_the_tide", "completed"]},
		"summary": "Harbourmaster Oki's runner broke his leg on a fish. His letter still has to cross the strait.",
		"on_start": [["give_item", &"letter_northreach", 1]],
		"stages": [
			{"id": &"cross", "text": "The ferry from the Water Tribe harbour crosses the strait to Northreach, in the Earth Kingdom.", "objectives": [
				{"id": &"cross", "type": &"go_to", "target": {"port": &"port_northreach"}, "radius": 60.0, "text": "Cross the strait to Northreach Harbor (take the ferry)"},
				{"id": &"deliver", "type": &"talk_to", "npc": &"ek_mok", "text": "Deliver the letter to Elder Mok"}]},
		],
		"rewards": {"xp": 160, "currency": 40, "items": {&"travel_rations": 2}},
	},
	{
		"id": &"tr_white_dragon_tea", "title": "White Dragon Tea", "kind": &"travel", "nation": &"earth", "giver": &"ek_hu",
		"location": "Southern Air Temple", "requires": {"quest": [&"ek_stone_beneath_the_sky", "completed"]},
		"summary": "Tea Master Hu owes the Abbot of the Southern Air Temple a parcel of tea. He has owed it for forty years.",
		"on_start": [["give_item", &"tea_parcel", 1]],
		"stages": [
			{"id": &"journey", "text": "South to Full Moon Bay, the ferry to Foothills Landing, then up the mountain. Or by air.", "objectives": [
				{"id": &"temple", "type": &"go_to", "target": {"city": &"southern_air_temple"}, "radius": 160.0, "text": "Journey to the Southern Air Temple"},
				{"id": &"deliver", "type": &"talk_to", "npc": &"at_dorje", "text": "Bring the tea to Abbot Dorje"}]},
		],
		"rewards": {"xp": 200, "currency": 40, "items": {&"prayer_beads": 1}},
	},
	{
		"id": &"tr_captains_apology", "title": "A Captain's Apology", "kind": &"travel", "nation": &"fire", "giver": &"fn_kuro",
		"location": "Northern Water Tribe", "requires": {"quest": [&"fn_a_spark_returns", "completed"]},
		"summary": "Admiral Kuro owes the Northern Water Tribe an apology, and will not send it on a warship.",
		"on_start": [["give_item", &"admiral_letter", 1]],
		"stages": [
			{"id": &"journey", "text": "Crimson Harbor to Full Moon Bay by ferry, north to Northreach, and across the strait.", "objectives": [
				{"id": &"tribe", "type": &"go_to", "target": {"city": &"northern_water_tribe"}, "radius": 420.0, "text": "Journey to the Northern Water Tribe"},
				{"id": &"deliver", "type": &"talk_to", "npc": &"wt_tulok", "text": "Deliver the admiral's letter to Chief Tulok"}]},
		],
		"rewards": {"xp": 240, "currency": 50, "items": {&"silk_scarf": 1}},
	},
	{
		"id": &"tr_a_letter_to_the_sun", "title": "A Letter to the Sun", "kind": &"travel", "nation": &"air", "giver": &"at_dorje",
		"location": "Fire Nation Capital", "requires": {"quest": [&"at_first_breath", "completed"]},
		"summary": "Abbot Dorje wrote to the sages of the Fire Nation's Sun Temple. Someone has to carry the first word.",
		"on_start": [["give_item", &"letter_temple", 1]],
		"stages": [
			{"id": &"journey", "text": "Foothills Landing to Full Moon Bay, then the ferry to Crimson Harbor and the road to the capital.", "objectives": [
				{"id": &"capital", "type": &"go_to", "target": {"city": &"fire_nation_capital"}, "radius": 450.0, "text": "Journey to the Fire Nation capital"},
				{"id": &"deliver", "type": &"talk_to", "npc": &"fn_mirei", "text": "Bring the abbot's letter to Sage Mirei"}]},
		],
		"rewards": {"xp": 240, "currency": 40, "items": {&"dragon_scale": 1}},
	},
]

extends RefCounted
## Northern Water Tribe quests: the Water opening chain (Born of the Tide -> The First Form ->
## Smoke on the Horizon -> Moon and Ocean) and side quests. Format: docs/modules/quests_npcs.md.

const NWT := &"northern_water_tribe"
const OASIS_POND := Vector3(-547.4, 54.0, -3184.7)

const QUESTS := [
	{
		"id": &"wt_born_of_the_tide", "title": "Born of the Tide", "kind": &"main", "nation": &"water", "giver": &"wt_anaaya",
		"location": "Northern Water Tribe",
		"summary": "Your bending woke early. Elder Anaaya wants you trained before the tide does it for you.",
		"auto_start": {"element": &"water"},
		"stages": [
			{"id": &"arrive", "text": "Elder Anaaya was waiting for me on the upper tier of the city.", "objectives": [
				{"id": &"meet_anaaya", "type": &"talk_to", "npc": &"wt_anaaya", "text": "Speak with Elder Anaaya"}]},
			{"id": &"hall", "text": "Anaaya sent me to Master Siku, who trains the city's benders in the great hall on the upper tier.", "objectives": [
				{"id": &"find_hall", "type": &"go_to", "target": {"anchor": {"settlement": NWT, "kind": &"quest_giver", "tags": ["training_hall"]}}, "radius": 26.0, "text": "Find the training hall on the upper tier"},
				{"id": &"meet_siku", "type": &"talk_to", "npc": &"wt_siku", "text": "Present yourself to Master Siku"}]},
		],
		"rewards": {"xp": 60},
		"next": &"wt_first_form",
	},
	{
		"id": &"wt_first_form", "title": "The First Form", "kind": &"main", "nation": &"water", "giver": &"wt_siku",
		"location": "Training hall, upper tier",
		"summary": "Master Siku wants six clean strikes on his training posts before he will call you a student.",
		"stages": [
			{"id": &"posts", "text": "Siku raised training posts in the hall. The whip is the first form: six clean strikes.", "objectives": [
				{"id": &"posts", "type": &"challenge", "npc": &"wt_siku", "text": "Strike the training posts with your Water Whip (talk to Siku)",
					"challenge": {"kind": &"targets", "title": "The First Form", "count": 3, "hits": 6, "slot": &"light", "time": 60.0}}]},
			{"id": &"report", "text": "The posts stood, but my strikes landed. Siku grunted. I think that was approval.", "objectives": [
				{"id": &"report", "type": &"talk_to", "npc": &"wt_siku", "text": "Report to Master Siku"}]},
		],
		"rewards": {"xp": 90},
		"next": &"wt_smoke_on_the_horizon",
	},
	{
		"id": &"wt_smoke_on_the_horizon", "title": "Smoke on the Horizon", "kind": &"main", "nation": &"water", "giver": &"wt_tulok",
		"location": "The eastern ice",
		"summary": "Black smoke on the eastern ice. The Chief needs a bender to find out what the Fire Navy wants.",
		"stages": [
			{"id": &"summons", "text": "A runner brought word: Chief Tulok asked for me at the palace.", "objectives": [
				{"id": &"summons", "type": &"talk_to", "npc": &"wt_tulok", "text": "Answer the Chief's summons at the palace"}]},
			{"id": &"scout", "text": "Hunters saw a Fire Navy landing party camped about a kilometre east of the city.", "objectives": [
				{"id": &"scout", "type": &"go_to", "target": {"site": &"wt_fire_navy_landing"}, "radius": 45.0, "text": "Find the Fire Navy landing east of the city"}]},
			{"id": &"fight", "text": "The landing was real: soldiers, a captain and an officer's chest.", "objectives": [
				{"id": &"drive", "type": &"defeat", "site": &"wt_fire_navy_landing", "count": 3, "text": "Drive off the Fire Navy scouts"},
				{"id": &"orders", "type": &"collect", "item": &"navy_orders", "count": 1, "text": "Recover their orders",
					"props": [{"at": {"site": &"wt_fire_navy_landing", "offset": Vector3(2.2, 0, 1.6)}, "kind": &"chest", "prompt": "Search the officer's chest"}]}]},
			{"id": &"report", "text": "Their orders were sealed with an admiral's flame. The Chief must see them.", "objectives": [
				{"id": &"report", "type": &"talk_to", "npc": &"wt_tulok", "text": "Bring the orders to Chief Tulok"}]},
		],
		"rewards": {"xp": 220, "currency": 40, "items": {&"healing_salve": 2}},
		"next": &"wt_moon_and_ocean",
	},
	{
		"id": &"wt_moon_and_ocean", "title": "Moon and Ocean", "kind": &"main", "nation": &"water", "giver": &"wt_naalu",
		"location": "The Spirit Oasis",
		"summary": "Princess Naalu wants to meet the bender the city whispers about, beside the koi of the Spirit Oasis.",
		"stages": [
			{"id": &"oasis", "text": "The Chief's daughter waits at the Spirit Oasis behind the palace.", "objectives": [
				{"id": &"meet_naalu", "type": &"talk_to", "npc": &"wt_naalu", "text": "Meet Princess Naalu at the Spirit Oasis"}]},
			{"id": &"draw", "text": "Tui and La circle in the pond. Naalu asked me to draw a little of their water, gently.", "objectives": [
				{"id": &"draw", "type": &"collect", "item": &"moon_water", "count": 1, "text": "Draw water from the koi pond",
					"props": [{"at": {"pos": OASIS_POND}, "kind": &"bowl", "prompt": "Draw water from the pond"}]}]},
			{"id": &"siku", "text": "The oasis water stayed cold in my hands. Master Siku will know what it means.", "objectives": [
				{"id": &"bring_water", "type": &"talk_to", "npc": &"wt_siku", "text": "Bring the oasis water to Master Siku"}]},
		],
		"rewards": {"xp": 260, "currency": 30, "techniques": [&"water_surge", &"ice_wall", &"healing_waters", &"water_wave", &"ice_trap", &"water_jet"]},
		"on_complete": [["flag", "wt_chain_done"]],
	},
	# --- side quests -------------------------------------------------------------------------
	{
		"id": &"wt_healers_moss", "title": "The Healer's Moss", "kind": &"side", "nation": &"water", "giver": &"wt_yara",
		"location": "The Ice Flats", "requires": {"quest": [&"wt_born_of_the_tide", "completed"]},
		"summary": "Healer Yara has run out of the pale moss she steeps for frostbite. It grows at the Ice Flats.",
		"stages": [
			{"id": &"gather", "text": "The moss grows where the frozen lake of the Ice Flats meets the rocks, west of the city.", "objectives": [
				{"id": &"moss", "type": &"collect", "item": &"arctic_moss", "count": 4, "text": "Gather healing moss at the Ice Flats",
					"props": [
						{"at": {"poi": &"wt_ice_flats", "offset": Vector3(46, 0, 18), "ground": true}, "kind": &"herb", "prompt": "Gather the moss"},
						{"at": {"poi": &"wt_ice_flats", "offset": Vector3(-38, 0, 34), "ground": true}, "kind": &"herb", "prompt": "Gather the moss"},
						{"at": {"poi": &"wt_ice_flats", "offset": Vector3(30, 0, -44), "ground": true}, "kind": &"herb", "prompt": "Gather the moss"},
						{"at": {"poi": &"wt_ice_flats", "offset": Vector3(-52, 0, -16), "ground": true}, "kind": &"herb", "prompt": "Gather the moss"},
						{"at": {"poi": &"wt_ice_flats", "offset": Vector3(8, 0, 56), "ground": true}, "kind": &"herb", "prompt": "Gather the moss"}]}]},
			{"id": &"return", "text": "Four bundles of moss, none of them a seal.", "objectives": [
				{"id": &"return", "type": &"talk_to", "npc": &"wt_yara", "text": "Bring the moss to Healer Yara"}]},
		],
		"rewards": {"xp": 90, "currency": 15, "items": {&"healing_salve": 2}},
	},
	{
		"id": &"wt_tangled_nets", "title": "Tangled Nets", "kind": &"side", "nation": &"water", "giver": &"wt_tikaani",
		"location": "The harbour", "requires": {"quest": [&"wt_born_of_the_tide", "completed"]},
		"summary": "Last night's storm flung Old Tikaani's nets across the harbour piers.",
		"stages": [
			{"id": &"nets", "text": "Three nets, tangled on three piers. The floats are what matter.", "objectives": [
				{"id": &"nets", "type": &"collect", "item": &"net_float", "count": 3, "text": "Untangle the nets on the harbour piers",
					"props": [
						{"at": {"anchor": {"settlement": NWT, "kind": &"fisher", "tags": ["pier"], "index": 1}, "offset": Vector3(1.2, 0, 0.8)}, "kind": &"net", "prompt": "Untangle the net"},
						{"at": {"anchor": {"settlement": NWT, "kind": &"fisher", "tags": ["pier"], "index": 2}, "offset": Vector3(-1.0, 0, 1.0)}, "kind": &"net", "prompt": "Untangle the net"},
						{"at": {"anchor": {"settlement": NWT, "kind": &"fisher", "tags": ["pier"], "index": 3}, "offset": Vector3(1.0, 0, -1.2)}, "kind": &"net", "prompt": "Untangle the net"}]}]},
			{"id": &"return", "text": "All three floats, salvaged.", "objectives": [
				{"id": &"return", "type": &"talk_to", "npc": &"wt_tikaani", "text": "Return the floats to Old Tikaani"}]},
		],
		"rewards": {"xp": 70, "currency": 20, "items": {&"smoked_fish": 3}},
	},
	{
		"id": &"wt_pale_moon_shrine", "title": "Light for the Pale Moon", "kind": &"side", "nation": &"water", "giver": &"wt_naalu",
		"location": "Shrine of the Pale Moon", "requires": {"quest": [&"wt_smoke_on_the_horizon", "completed"]},
		"summary": "No one has lit incense at the Shrine of the Pale Moon since the war began. Naalu asked me to.",
		"on_start": [["give_item", &"spirit_incense", 1]],
		"stages": [
			{"id": &"find", "text": "The shrine stands on the eastern shore, below the cliffs.", "objectives": [
				{"id": &"find", "type": &"discover", "poi": &"wt_moon_shrine", "text": "Find the Shrine of the Pale Moon on the eastern shore"}]},
			{"id": &"light", "text": "Cold stone, an empty bowl, and the sound of the sea.", "objectives": [
				{"id": &"light", "type": &"interact", "key": &"moon_incense", "text": "Light the incense at the shrine",
					"props": [{"at": {"poi": &"wt_moon_shrine", "offset": Vector3(0, 0, 3.0)}, "kind": &"incense", "prompt": "Light the incense"}]}],
				"on_complete": [["take_item", &"spirit_incense", 1]]},
		],
		"rewards": {"xp": 120, "items": {&"moon_pendant": 1}},
	},
	{
		"id": &"wt_ice_flats_trial", "title": "Trial on the Ice Flats", "kind": &"side", "nation": &"water", "giver": &"wt_siku",
		"location": "The Ice Flats", "requires": {"quest": [&"wt_first_form", "completed"], "element": &"water"},
		"summary": "Kallik boasts no student this season can best her on the Ice Flats. Siku wants her proven wrong.",
		"stages": [
			{"id": &"travel", "text": "The Ice Flats lie on the frozen lake west of the city.", "objectives": [
				{"id": &"travel", "type": &"go_to", "target": {"poi": &"wt_ice_flats"}, "radius": 40.0, "text": "Travel to the Ice Flats west of the city"}]},
			{"id": &"duel", "text": "Kallik was waiting on the ice.", "objectives": [
				{"id": &"duel", "type": &"challenge", "at": {"poi": &"wt_ice_flats"}, "radius": 34.0, "text": "Best Kallik in a sparring bout on the ice",
					"challenge": {"kind": &"spar", "title": "Spar with Kallik", "archetype": &"spar_water", "time": 120.0}}]},
			{"id": &"report", "text": "Kallik yielded. She even laughed about it.", "objectives": [
				{"id": &"report", "type": &"talk_to", "npc": &"wt_siku", "text": "Tell Master Siku"}]},
		],
		"rewards": {"xp": 160, "currency": 25, "skill_points": 1},
	},
]

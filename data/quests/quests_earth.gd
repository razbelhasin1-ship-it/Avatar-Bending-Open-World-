extends RefCounted
## Earth Kingdom quests: the Earth opening chain (Stone Beneath the Sky -> Rooted -> Smoke Beyond
## the Wall -> The Listening Earth) and side quests around Ba Sing Se. Format:
## docs/modules/quests_npcs.md.

const BSS := &"ba_sing_se"

const QUESTS := [
	{
		"id": &"ek_stone_beneath_the_sky", "title": "Stone Beneath the Sky", "kind": &"main", "nation": &"earth", "giver": &"ek_lin",
		"location": "Ba Sing Se, Upper Ring",
		"summary": "The earth listens to you. Guide Lin knows a master who can teach it to listen better.",
		"auto_start": {"element": &"earth"},
		"stages": [
			{"id": &"arrive", "text": "Guide Lin met me at the overlook of the Upper Ring.", "objectives": [
				{"id": &"meet_lin", "type": &"talk_to", "npc": &"ek_lin", "text": "Speak with Guide Lin at the overlook"}]},
			{"id": &"hall", "text": "Master Bao Shan teaches in the training hall of the Middle Ring.", "objectives": [
				{"id": &"find_hall", "type": &"go_to", "target": {"anchor": {"settlement": BSS, "kind": &"quest_giver", "tags": ["training_hall"]}}, "radius": 26.0, "text": "Find the training hall in the Middle Ring"},
				{"id": &"meet_master", "type": &"talk_to", "npc": &"ek_bao_shan", "text": "Present yourself to Master Bao Shan"}]},
		],
		"rewards": {"xp": 60},
		"next": &"ek_rooted",
	},
	{
		"id": &"ek_rooted", "title": "Rooted", "kind": &"main", "nation": &"earth", "giver": &"ek_bao_shan",
		"location": "Training hall, Middle Ring",
		"summary": "Bao Shan's first lesson: rock from the floor, through the fist, into the target.",
		"stages": [
			{"id": &"posts", "text": "Six strikes on the training posts, rock through fist.", "objectives": [
				{"id": &"posts", "type": &"challenge", "npc": &"ek_bao_shan", "text": "Strike the training posts with Earth Punch (talk to Bao Shan)",
					"challenge": {"kind": &"targets", "title": "Rooted", "count": 3, "hits": 6, "slot": &"light", "time": 60.0}}]},
			{"id": &"report", "text": "The posts stood. They are old posts, Bao Shan says.", "objectives": [
				{"id": &"report", "type": &"talk_to", "npc": &"ek_bao_shan", "text": "Report to Master Bao Shan"}]},
		],
		"rewards": {"xp": 90, "items": {&"ginseng_tea": 2}},
		"next": &"ek_smoke_beyond_the_wall",
	},
	{
		"id": &"ek_smoke_beyond_the_wall", "title": "Smoke Beyond the Wall", "kind": &"main", "nation": &"earth", "giver": &"ek_jin",
		"location": "West of Ba Sing Se",
		"summary": "Captain Jin of the west gate saw smoke beyond the wall: Fire Nation scouts counting patrols.",
		"stages": [
			{"id": &"gate", "text": "Captain Jin asked for any bender who could be spared at the west gate.", "objectives": [
				{"id": &"orders", "type": &"talk_to", "npc": &"ek_jin", "text": "Report to Captain Jin at the west gate"}]},
			{"id": &"scout", "text": "The smoke rose past the farms, just west of the gate.", "objectives": [
				{"id": &"scout", "type": &"go_to", "target": {"site": &"ek_fire_scout_camp"}, "radius": 45.0, "text": "Find the Fire Nation scout camp beyond the wall"}]},
			{"id": &"fight", "text": "A Fire Nation camp, close enough to count the patrols on our wall.", "objectives": [
				{"id": &"drive", "type": &"defeat", "site": &"ek_fire_scout_camp", "count": 3, "text": "Drive off the Fire Nation scouts"},
				{"id": &"papers", "type": &"collect", "item": &"scout_orders", "count": 1, "text": "Search the camp for their orders",
					"props": [{"at": {"site": &"ek_fire_scout_camp", "offset": Vector3(2.0, 0, -1.8)}, "kind": &"chest", "prompt": "Search the scout's chest"}]}]},
			{"id": &"report", "text": "Patrol times and gate counts, in a careful Fire Nation hand.", "objectives": [
				{"id": &"report", "type": &"talk_to", "npc": &"ek_jin", "text": "Bring the orders to Captain Jin"}]},
		],
		"rewards": {"xp": 220, "currency": 40, "items": {&"healing_salve": 2}},
		"next": &"ek_the_listening_earth",
	},
	{
		"id": &"ek_the_listening_earth", "title": "The Listening Earth", "kind": &"main", "nation": &"earth", "giver": &"ek_bao_shan",
		"location": "Stonefist Training Yard",
		"summary": "Bao Shan's harder lesson: hold the Stonefist yard and let the earth answer.",
		"stages": [
			{"id": &"return", "text": "Master Bao Shan heard about the scouts.", "objectives": [
				{"id": &"return", "type": &"talk_to", "npc": &"ek_bao_shan", "text": "Return to Master Bao Shan"}]},
			{"id": &"yard", "text": "His senior student waits at the Stonefist Training Yard in the fields beyond the west gate.", "objectives": [
				{"id": &"duel", "type": &"challenge", "at": {"poi": &"ek_stonefist_yard"}, "radius": 26.0, "text": "Hold the Stonefist yard against Senior Student Bao",
					"challenge": {"kind": &"spar", "title": "Hold the Yard", "archetype": &"spar_earth", "time": 120.0}}]},
			{"id": &"report", "text": "Bao yielded. Apparently she never yields.", "objectives": [
				{"id": &"report", "type": &"talk_to", "npc": &"ek_bao_shan", "text": "Tell Master Bao Shan"}]},
		],
		"rewards": {"xp": 260, "currency": 30, "techniques": [&"earth_pillar", &"earth_stomp", &"earth_spikes", &"earth_grab", &"earth_armor", &"earthquake"]},
		"on_complete": [["flag", "ek_chain_done"]],
	},
	# --- side quests -------------------------------------------------------------------------
	{
		"id": &"ek_lost_in_the_fields", "title": "Lost in the Millet", "kind": &"side", "nation": &"earth", "giver": &"ek_dao",
		"location": "Agrarian Zone", "requires": {"quest": [&"ek_stone_beneath_the_sky", "completed"]},
		"summary": "Farmer Dao's granddaughter chased a hopper-rabbit into the millet and has not come back.",
		"stages": [
			{"id": &"search", "text": "Mei ran off past the Stonefist yard.", "objectives": [
				{"id": &"search", "type": &"go_to", "target": {"npc": &"ek_mei"}, "radius": 12.0, "text": "Search the fields past the Stonefist yard"}]},
			{"id": &"calm", "text": "Found her, very cross and not at all lost.", "objectives": [
				{"id": &"calm", "type": &"talk_to", "npc": &"ek_mei", "text": "Talk to Little Mei"}]},
			{"id": &"escort", "text": "Mei agreed to come home, as long as I walk slowly.", "objectives": [
				{"id": &"escort", "type": &"escort", "npc": &"ek_mei", "to": {"npc": &"ek_dao"}, "radius": 7.0, "text": "Bring Mei home to Farmer Dao"}]},
			{"id": &"thanks", "text": "Grandfather and granddaughter, reunited and arguing.", "objectives": [
				{"id": &"thanks", "type": &"talk_to", "npc": &"ek_dao", "text": "Speak with Farmer Dao"}]},
		],
		"rewards": {"xp": 110, "currency": 25, "items": {&"rice_ball": 3}},
	},
	{
		"id": &"ek_mail_for_omashu", "title": "Mail for Omashu", "kind": &"side", "nation": &"earth", "giver": &"ek_lin",
		"location": "Omashu", "requires": {"quest": [&"ek_stone_beneath_the_sky", "completed"]},
		"summary": "Guide Lin has a letter for Pim, the mail clerk of Omashu, the mountain city to the west.",
		"on_start": [["give_item", &"letter_omashu", 1]],
		"stages": [
			{"id": &"deliver", "text": "The road west passes the farms and the canyons. Omashu crowns its mountain beyond a chasm.", "objectives": [
				{"id": &"chutes", "type": &"discover", "poi": &"ek_mail_chutes", "text": "Find the Mail Chute Terraces of Omashu"},
				{"id": &"deliver", "type": &"talk_to", "npc": &"ek_pim", "text": "Deliver the letter to Clerk Pim"}]},
		],
		"rewards": {"xp": 130, "currency": 30, "items": {&"jade_figurine": 1}},
	},
	{
		"id": &"ek_jade_for_wen", "title": "Jade for the Herbalist", "kind": &"side", "nation": &"earth", "giver": &"ek_wen",
		"location": "Jade Quarry", "requires": {"quest": [&"ek_stone_beneath_the_sky", "completed"]},
		"summary": "Herbalist Wen grinds jade into her best salves. The Jade Quarry lies east of the city.",
		"stages": [
			{"id": &"quarry", "text": "Glowing green shards stud the quarry face east of Ba Sing Se.", "objectives": [
				{"id": &"jade", "type": &"collect", "item": &"jade_shard", "count": 3, "take": true, "text": "Collect jade shards at the Jade Quarry"}]},
			{"id": &"return", "text": "Three shards, not a scratch on them.", "objectives": [
				{"id": &"return", "type": &"talk_to", "npc": &"ek_wen", "text": "Bring the jade to Herbalist Wen"}]},
		],
		"rewards": {"xp": 100, "currency": 45, "items": {&"ginseng_root": 3}},
	},
]

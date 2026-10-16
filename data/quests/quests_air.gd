extends RefCounted
## Southern Air Temple quests: the Air opening chain (The First Breath -> Leaves on the Wind ->
## Shadow at the Gate -> The Wind Remembers) and side quests. Format: docs/modules/quests_npcs.md.

const SAT := &"southern_air_temple"

const QUESTS := [
	{
		"id": &"at_first_breath", "title": "The First Breath", "kind": &"main", "nation": &"air", "giver": &"at_pasang",
		"location": "Southern Air Temple",
		"summary": "Your breath is louder than your footsteps. Master Tashi wants to know why.",
		"auto_start": {"element": &"air"},
		"stages": [
			{"id": &"arrive", "text": "Brother Pasang greeted me on the arrival plaza.", "objectives": [
				{"id": &"meet_pasang", "type": &"talk_to", "npc": &"at_pasang", "text": "Speak with Brother Pasang"}]},
			{"id": &"sanctum", "text": "Master Tashi waits in the sanctum at the top of the temple, under the great spire.", "objectives": [
				{"id": &"climb", "type": &"go_to", "target": {"anchor": {"settlement": SAT, "kind": &"trainer", "tags": ["master", "sanctum"]}}, "radius": 24.0, "text": "Climb to the sanctum"},
				{"id": &"meet_master", "type": &"talk_to", "npc": &"at_tashi", "text": "Present yourself to Master Tashi"}]},
		],
		"rewards": {"xp": 60},
		"next": &"at_leaves_on_the_wind",
	},
	{
		"id": &"at_leaves_on_the_wind", "title": "Leaves on the Wind", "kind": &"main", "nation": &"air", "giver": &"at_tashi",
		"location": "The sanctum",
		"summary": "Six gusts on the posts: palm, kick, burst. Light and quick.",
		"stages": [
			{"id": &"posts", "text": "Tashi raised training posts in the sanctum court.", "objectives": [
				{"id": &"posts", "type": &"challenge", "npc": &"at_tashi", "text": "Strike the training posts with your Air Combo (talk to Tashi)",
					"challenge": {"kind": &"targets", "title": "Leaves on the Wind", "count": 3, "hits": 6, "slot": &"light", "time": 60.0}}]},
			{"id": &"report", "text": "My third gust curled. Tashi says that means I stopped thinking.", "objectives": [
				{"id": &"report", "type": &"talk_to", "npc": &"at_tashi", "text": "Report to Master Tashi"}]},
		],
		"rewards": {"xp": 90, "items": {&"fruit_pie": 2}},
		"next": &"at_shadow_at_the_gate",
	},
	{
		"id": &"at_shadow_at_the_gate", "title": "Shadow at the Gate", "kind": &"main", "nation": &"air", "giver": &"at_sonam",
		"location": "The southern foothills",
		"summary": "Fire Nation scouts camp in the foothills below the Gate of a Thousand Steps.",
		"stages": [
			{"id": &"gate", "text": "Brother Sonam keeps watch at the bison landing above the pass.", "objectives": [
				{"id": &"orders", "type": &"talk_to", "npc": &"at_sonam", "text": "Speak with Brother Sonam at the bison landing"}]},
			{"id": &"scout", "text": "The scouts camp in the foothills south-west of the pass.", "objectives": [
				{"id": &"scout", "type": &"go_to", "target": {"site": &"at_fire_scouting_party"}, "radius": 45.0, "text": "Find the Fire Nation scouting party in the foothills"}]},
			{"id": &"fight", "text": "Three tents and a fire, close to the road up to the temple.", "objectives": [
				{"id": &"drive", "type": &"defeat", "site": &"at_fire_scouting_party", "count": 3, "text": "Drive off the scouting party"},
				{"id": &"papers", "type": &"collect", "item": &"scout_orders", "count": 1, "text": "Search their camp for orders",
					"props": [{"at": {"site": &"at_fire_scouting_party", "offset": Vector3(1.8, 0, 2.2)}, "kind": &"chest", "prompt": "Search the scouts' chest"}]}]},
			{"id": &"report", "text": "Maps of the stairs and counts of the bison.", "objectives": [
				{"id": &"report", "type": &"talk_to", "npc": &"at_sonam", "text": "Bring the orders to Brother Sonam"}]},
		],
		"rewards": {"xp": 220, "currency": 40, "items": {&"healing_salve": 2}},
		"next": &"at_the_wind_remembers",
	},
	{
		"id": &"at_the_wind_remembers", "title": "The Wind Remembers", "kind": &"main", "nation": &"air", "giver": &"at_dorje",
		"location": "The Meditation Ledge",
		"summary": "Tashi teaches the wind's movement. The abbot will teach its stillness.",
		"stages": [
			{"id": &"abbot", "text": "Abbot Dorje asked to see me in the sanctum.", "objectives": [
				{"id": &"meet_abbot", "type": &"talk_to", "npc": &"at_dorje", "text": "Speak with Abbot Dorje in the sanctum"}]},
			{"id": &"ledge", "text": "The meditation ledge lies on the western pinnacle, across the Bridge of Drifting Prayers.", "objectives": [
				{"id": &"ledge", "type": &"discover", "poi": &"at_meditation_ledge", "text": "Cross to the Meditation Ledge"},
				{"id": &"sit", "type": &"interact", "key": &"meditation_ledge", "text": "Meditate on the ledge until the wind forgets you",
					"props": [{"at": {"poi": &"at_meditation_ledge", "offset": Vector3(0, 0, 2.5)}, "kind": &"incense", "prompt": "Meditate"}]}]},
			{"id": &"report", "text": "The wind remembers everything and holds on to nothing.", "objectives": [
				{"id": &"report", "type": &"talk_to", "npc": &"at_tashi", "text": "Return to Master Tashi"}]},
		],
		"rewards": {"xp": 260, "currency": 30, "techniques": [&"air_push", &"air_scooter", &"air_tornado"]},
		"on_complete": [["flag", "at_chain_done"]],
	},
	# --- side quests -------------------------------------------------------------------------
	{
		"id": &"at_novices_glider", "title": "The Novice's Glider", "kind": &"side", "nation": &"air", "giver": &"at_kunga",
		"location": "Glider's Leap", "requires": {"quest": [&"at_first_breath", "completed"]},
		"summary": "A gust took Novice Kunga's glider down to the ledge by the Glider's Leap pavilion.",
		"stages": [
			{"id": &"find", "text": "The glider is caught near the Glider's Leap pavilion.", "objectives": [
				{"id": &"glider", "type": &"collect", "item": &"lost_glider", "count": 1, "text": "Recover the glider at the Glider's Leap",
					"props": [{"at": {"poi": &"at_gliders_leap", "offset": Vector3(3.0, 0, 1.5)}, "kind": &"glider", "prompt": "Pick up the glider"}]}]},
			{"id": &"return", "text": "Only a little torn.", "objectives": [
				{"id": &"return", "type": &"talk_to", "npc": &"at_kunga", "text": "Return the glider to Novice Kunga"}]},
		],
		"rewards": {"xp": 80, "items": {&"wind_chime": 1}},
	},
	{
		"id": &"at_airball_champion", "title": "Airball Champion", "kind": &"training", "nation": &"air", "giver": &"at_nima",
		"location": "Airball Courts", "requires": {"quest": [&"at_first_breath", "completed"]},
		"summary": "Sister Nima holds the airball record. Ten hits in forty seconds.",
		"stages": [
			{"id": &"match", "text": "Knock the posts, keep moving.", "objectives": [
				{"id": &"match", "type": &"challenge", "npc": &"at_nima", "text": "Beat Sister Nima's airball record (talk to her)",
					"challenge": {"kind": &"targets", "title": "Airball", "count": 4, "hits": 10, "slot": &"any", "time": 40.0}}]},
		],
		"rewards": {"xp": 90, "items": {&"airball_ribbon": 1}},
	},
	{
		"id": &"at_whistling_caves", "title": "The Whistling Caves", "kind": &"side", "nation": &"air", "giver": &"at_dorje",
		"location": "Whistling Wind Caves", "requires": {"quest": [&"at_leaves_on_the_wind", "completed"]},
		"summary": "The old monks carved tablets in the Whistling Wind Caves below the eastern cliffs.",
		"stages": [
			{"id": &"caves", "text": "The caves sing when the weather turns.", "objectives": [
				{"id": &"caves", "type": &"discover", "poi": &"at_whistling_caves", "text": "Find the Whistling Wind Caves"},
				{"id": &"tablet", "type": &"interact", "key": &"cave_tablet", "text": "Read the monks' tablet at the cave mouth",
					"props": [{"at": {"poi": &"at_whistling_caves", "offset": Vector3(2.5, 0, 2.5)}, "kind": &"tablet", "prompt": "Read the tablet"}]}]},
			{"id": &"return", "text": "'The wind that leaves returns as rain.'", "objectives": [
				{"id": &"return", "type": &"talk_to", "npc": &"at_dorje", "text": "Tell Abbot Dorje what the tablet says"}]},
		],
		"rewards": {"xp": 130, "items": {&"mountain_sage": 3}},
	},
]

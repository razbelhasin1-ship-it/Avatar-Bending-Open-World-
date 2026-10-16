extends RefCounted
## Named characters of the Fire Nation (the capital, Crimson Harbor, the villages) and their
## dialogue. Original writing.

const FNC := &"fire_nation_capital"

const NPCS := {
	&"fn_kaida": {
		"name": "Envoy Kaida", "title": "Envoy of the Palace", "nation": &"fire", "role": &"noble",
		"look": {"preset": &"fire_nation", "body": "female", "age": "adult", "seed": 3},
		"place": {"anchor": {"settlement": FNC, "kind": &"quest_giver", "tags": ["spawn", "guide"]}, "face": {"spawn": &"fire"}},
		"barks": ["The palace notices talent. Try not to waste it.", "Walk tall. You are in the capital."],
		"talk": [
			{"if": {"objective": [&"fn_a_spark_returns", &"meet_kaida"]}, "tree": &"kaida_welcome"},
			{"tree": &"kaida_default"},
		],
	},
	&"fn_jinzo": {
		"name": "Master Jinzo", "title": "Firebending Master", "nation": &"fire", "role": &"trainer",
		"look": {"preset": &"fire_nation", "body": "male", "age": "elder", "seed": 1, "beard": "long"},
		"place": {"anchor": {"settlement": FNC, "kind": &"trainer", "tags": ["kata_grounds"]}},
		"barks": ["Breathe from the belly, not the chest!", "Fire is life, not only destruction."],
		"trainer": {"element": &"fire", "spar": "Spar with Senior Student Azun",
			"menu": "The sun is high. A good hour for fire. What will you learn?",
			"lesson_lines": ["Breath first. The fire is only the breath made visible.", "Control, not fury. A wild flame burns its master."],
			"praise": ["Precise. The sun itself would approve.", "Good. Now do it a thousand more times."],
			"fail": ["Your flame flickered because your breath did. Again.", "Anger is quick fuel and a poor teacher."]},
		"talk": [
			{"if": {"objective": [&"fn_a_spark_returns", &"meet_master"]}, "tree": &"jinzo_meet"},
			{"if": {"objective": [&"fn_breath_of_fire", &"posts"]}, "tree": &"jinzo_posts"},
			{"if": {"objective": [&"fn_breath_of_fire", &"report"]}, "tree": &"jinzo_report"},
			{"if": {"objective": [&"fn_the_suns_teaching", &"report"]}, "tree": &"jinzo_sun_done"},
			{"if": {"objective": [&"fn_kata_under_the_sun", &"kata"]}, "tree": &"jinzo_kata"},
			{"if": {"quest": [&"fn_kata_under_the_sun", "available"]}, "tree": &"jinzo_offer_kata"},
			{"tree": &"jinzo_default"},
		],
	},
	&"fn_rina": {
		"name": "Captain Rina", "title": "Warden of the Dragon's Throat", "nation": &"fire", "role": &"guard",
		"look": {"preset": &"fire_soldier", "body": "female", "age": "adult", "seed": 1},
		"place": {"anchor": {"settlement": FNC, "kind": &"quest_giver", "tags": ["gatekeeper", "gorge"]}},
		"barks": ["Papers. Or a very good reason.", "Nothing passes the Throat without my say."],
		"talk": [
			{"if": {"objective": [&"fn_smoke_over_the_cove", &"orders"]}, "tree": &"rina_orders"},
			{"if": {"objective": [&"fn_smoke_over_the_cove", &"report"]}, "tree": &"rina_report"},
			{"tree": &"rina_default"},
		],
	},
	&"fn_mirei": {
		"name": "Sage Mirei", "title": "Sage of the Sun Temple", "nation": &"fire", "role": &"elder",
		"look": {"preset": &"fire_nation", "body": "female", "age": "elder", "seed": 2},
		"place": {"anchor": {"settlement": FNC, "kind": &"quest_giver", "tags": ["sage", "temple"]}},
		"barks": ["The flame remembers what the people forget.", "Sit with the fire. Listen."],
		"talk": [
			{"if": {"objective": [&"fn_the_suns_teaching", &"meet_sage"]}, "tree": &"mirei_teaching"},
			{"if": {"objective": [&"fn_overgrown_sun_temple", &"return"]}, "tree": &"mirei_ember_done"},
			{"if": {"objective": [&"tr_a_letter_to_the_sun", &"deliver"]}, "tree": &"mirei_letter"},
			{"if": {"quest": [&"fn_overgrown_sun_temple", "available"]}, "tree": &"mirei_offer_ruin"},
			{"tree": &"mirei_default"},
		],
	},
	&"fn_suda": {
		"name": "Apothecary Suda", "title": "Ember Apothecary", "nation": &"fire", "role": &"merchant", "shop": &"fnc_apothecary",
		"look": {"preset": &"merchant", "body": "female", "age": "adult", "seed": 1, "palette": {"robe": Color(0.62, 0.16, 0.12), "trim": Color(0.86, 0.62, 0.22)}},
		"place": {"anchor": {"settlement": FNC, "kind": &"quest_giver", "tags": ["market", "merchant"], "index": 1}},
		"barks": ["Fire lily for burns! You'll want it, firebender.", "Salves, tonics, jerky!"],
		"talk": [{"tree": &"suda_default"}],
	},
	&"fn_ashi": {
		"name": "Jeweller Ashi", "title": "Sunfire Jewels", "nation": &"fire", "role": &"merchant", "shop": &"fnc_jeweller",
		"look": {"preset": &"fire_nation", "body": "male", "age": "adult", "seed": 4, "beard": "goatee"},
		"place": {"anchor": {"settlement": FNC, "kind": &"quest_giver", "tags": ["market", "merchant"], "index": 0}},
		"barks": ["Gold that glows like the sun at noon!", "A charm for courage, a pendant for luck!"],
		"talk": [{"tree": &"ashi_default"}],
	},
	&"fn_kuro": {
		"name": "Admiral Kuro", "title": "Admiral of the Crimson Fleet", "nation": &"fire", "role": &"noble",
		"look": {"preset": &"fire_nation", "body": "male", "age": "elder", "seed": 5, "beard": "goatee"},
		"place": {"anchor": {"settlement": &"fire_harbor", "kind": &"quest_giver", "tags": ["admiral"]}},
		"barks": ["The sea is a harsh judge.", "Every ship in this harbour answers to me. Most days."],
		"talk": [
			{"if": {"quest": [&"tr_captains_apology", "available"]}, "tree": &"kuro_offer"},
			{"tree": &"kuro_default"},
		],
	},
	&"fn_hoshi": {
		"name": "Elder Hoshi", "title": "Elder of the Ashleaf Terraces", "nation": &"fire", "role": &"elder",
		"look": {"preset": &"villager_fire", "body": "female", "age": "elder", "seed": 2},
		"place": {"anchor": {"settlement": &"fn_villages", "kind": &"quest_giver", "tags": ["ashleaf", "elder"]}},
		"barks": ["The tea bushes need rain and quiet. They get neither.", "Mind the terraces, they crumble."],
		"talk": [
			{"if": {"objective": [&"fn_komodo_trouble", &"return"]}, "tree": &"hoshi_done"},
			{"if": {"quest": [&"fn_komodo_trouble", "available"]}, "tree": &"hoshi_offer"},
			{"tree": &"hoshi_default"},
		],
	},
}

const TREES := {
	&"kaida_welcome": {"nodes": {
		"start": {"lines": [
			"So you are the one the instructors whisper about. The fire in you woke before your manners did, I hear.",
			"Welcome to the capital, {player}. The palace above, the Noble Quarter below, and the Lower City around the caldera's rim.",
		], "next": "ask"},
		"ask": {"text": "The palace has arranged a master for you. Do you wish to know who?", "choices": [
			{"text": "Who will teach me?", "next": "master"},
			{"text": "Arranged? Without asking me?", "next": "arranged"},
		]},
		"arranged": {"text": "This is the Fire Nation. Everything is arranged. The trick is to arrange it back.", "next": "master"},
		"master": {"lines": [
			"Master Jinzo, at the Flame Kata Grounds, just down the stair from this terrace. He taught half the generals in the city.",
			"He will tell you that fire is breath. Listen to him. The ones who don't end up singed, or worse, in politics.",
		], "end": true},
	}},
	&"kaida_default": {"nodes": {
		"start": {"text": ["The palace notices talent. Try not to waste it.", "The Plaza of the Sun is lovely at dusk. Go and see."], "end": true},
	}},
	&"jinzo_meet": {"nodes": {
		"start": {"lines": [
			"Stop. Breathe. No, not like that, you sound like a kettle. From the belly.",
			"Firebending is the element of power, and of will. But a flame without breath is only a spark that dies proud.",
		], "next": "q"},
		"q": {"text": "Why do you want to bend fire?", "choices": [
			{"text": "To protect people.", "next": "protect"},
			{"text": "To become strong.", "next": "strong"},
		]},
		"protect": {"text": "A good answer. Now we will see whether your fire agrees.", "next": "end"},
		"strong": {"text": "Honest, at least. Strength is a tool. We will teach you which end to hold.", "next": "end"},
		"end": {"text": "Tell me when you are ready, and I will set up the posts.", "end": true},
	}},
	&"jinzo_posts": {"nodes": {
		"start": {"text": "Eight strikes on the posts. Jab, jab, kick. Each one a short breath. Ready?", "choices": [
			{"text": "Set up the posts.", "do": [["challenge", &"fn_breath_of_fire", &"posts"]], "next": "go"},
			{"text": "One moment, Master.", "end": true},
		]},
		"go": {"text": "Breathe out with every strike. The flame follows the breath.", "end": true},
	}},
	&"jinzo_report": {"nodes": {
		"start": {"lines": [
			"Not bad. Your kicks are lazy, but your fists are honest.",
			"Captain Rina at the Dragon's Throat sent a runner this morning. Smugglers in the cove to the north, under our very noses.",
		], "next": "end"},
		"end": {"text": "The palace would like that problem solved quietly. Go and see Rina. And keep your breath steady.", "end": true},
	}},
	&"jinzo_sun_done": {"nodes": {
		"start": {"lines": [
			"You sat with the eternal flame. I can tell. Your shoulders finally came down from your ears.",
			"The sun gives, and gives, and asks nothing back. That is the oldest firebending. Now let me show you something new.",
		], "end": true},
	}},
	&"jinzo_offer_kata": {"nodes": {
		"start": {"text": "Every noon the students run the kata under the sun. Today you will join them. Four technique strikes on the posts. Will you?", "choices": [
			{"text": "I will run the kata.", "do": [["start_quest", &"fn_kata_under_the_sun"]], "next": "now"},
			{"text": "Train me instead.", "do": [["train"]], "end": true},
			{"text": "Not today.", "end": true},
		]},
		"now": {"text": "Then begin. Tell me when you are ready.", "end": true},
	}},
	&"jinzo_kata": {"nodes": {
		"start": {"text": "The posts are waiting. Techniques only: sweep, burst, whatever you have learned.", "choices": [
			{"text": "Begin the kata.", "do": [["challenge", &"fn_kata_under_the_sun", &"kata"]], "end": true},
			{"text": "Not yet.", "end": true},
		]},
	}},
	&"jinzo_default": {"nodes": {
		"start": {"text": ["Breathe from the belly.", "Again? Good. Fire rewards persistence."], "choices": [
			{"text": "Train me.", "do": [["train"]], "end": true},
			{"text": "Any advice?", "next": "advice"},
			{"text": "Farewell, Master.", "end": true},
		]},
		"advice": {"text": "Pressure. A firebender wins by never letting the opponent breathe. Step in, strike, step in again.", "end": true},
	}},
	&"rina_orders": {"nodes": {
		"start": {"lines": [
			"Jinzo's student? Good. I have soldiers, but soldiers march loudly.",
			"Smugglers have been running goods out of a cove north-east of the city, past the Dragon's Throat. Stolen goods. Our goods.",
		], "next": "go"},
		"go": {"text": "Go down the gorge road and follow the coast. Clear them out and bring back the merchant's crate they took.", "end": true},
	}},
	&"rina_report": {"nodes": {
		"start": {"lines": [
			"The crate! Intact! The merchants' guild will stop shouting at me for at least a week.",
			"You did well, firebender. Quietly, too. The palace likes quietly.",
		], "do": [["take_item", &"stolen_crate", 1]], "end": true},
	}},
	&"rina_default": {"nodes": {
		"start": {"text": ["Nothing passes the Throat without my say.", "Papers. Or a very good reason."], "end": true},
	}},
	&"mirei_teaching": {"nodes": {
		"start": {"lines": [
			"Jinzo sends you to me. Of course he does. He teaches the strike; I teach where it comes from.",
			"Beyond the palace, west across the caldera rim, burns the Shrine of the Eternal Flame. It has not gone out in a thousand years.",
		], "next": "go"},
		"go": {"text": "Go and sit before it. Do not bend. Only breathe. When you understand why it never goes out, return to your master.", "end": true},
	}},
	&"mirei_offer_ruin": {"nodes": {
		"start": {"lines": [
			"In the jungle west of the capital lies a sun temple older than the nation. Overgrown now. Forgotten.",
			"Its altar held an ember stone, warm without fire. I would like it brought here, where someone remembers what it means.",
		], "choices": [
			{"text": "I will find the stone.", "do": [["start_quest", &"fn_overgrown_sun_temple"]], "end": true},
			{"text": "Not now.", "end": true},
		]},
	}},
	&"mirei_ember_done": {"nodes": {
		"start": {"lines": [
			"Warm. Still warm, after all these years. You see? The old fire never needed anger.",
			"Thank you. Take this charm. The jewellers make them for courage. I think you have enough, but it is pretty.",
		], "do": [["take_item", &"ember_stone", 1]], "end": true},
	}},
	&"mirei_letter": {"nodes": {
		"start": {"lines": [
			"A letter from the Southern Air Temple? For me? The monks have not written to this temple in a lifetime.",
			"'The wind remembers the flame that warmed it.' ...Forgive me. I need a moment.",
		], "next": "end"},
		"end": {"text": "Thank you, traveller. Perhaps I will answer. Perhaps the world is ready for that.", "do": [["take_item", &"letter_temple", 1]], "end": true},
	}},
	&"mirei_default": {"nodes": {
		"start": {"text": ["The flame remembers what the people forget.", "Sit with the fire. Listen."], "end": true},
	}},
	&"suda_default": {"nodes": {
		"start": {"text": ["Burns, bruises, broken pride? I have something for all of it.", "Fire lily for burns! You'll want it."], "choices": [
			{"text": "Show me your remedies.", "do": [["shop", &"fnc_apothecary"]], "end": true},
			{"text": "Farewell.", "end": true},
		]},
	}},
	&"ashi_default": {"nodes": {
		"start": {"text": ["Gold that glows like the sun at noon!", "Every noble in the capital wears my work. Some of them even paid for it."], "choices": [
			{"text": "Show me your jewels.", "do": [["shop", &"fnc_jeweller"]], "end": true},
			{"text": "Farewell.", "end": true},
		]},
	}},
	&"kuro_offer": {"nodes": {
		"start": {"lines": [
			"You have the look of someone who travels. Sit. I have a request that I cannot give to a sailor.",
			"Some of my captains landed on the Water Tribe's ice without my order. I have dealt with them. But the Chief of the north deserves an apology. From me.",
		], "choices": [
			{"text": "I will carry your letter north.", "do": [["start_quest", &"tr_captains_apology"]], "next": "route"},
			{"text": "Why not send a ship?", "next": "ship"},
			{"text": "Not now.", "end": true},
		]},
		"ship": {"text": "A Fire Navy ship in their bay would be an answer, not an apology. A traveller on a ferry is only a traveller.", "choices": [
			{"text": "I will carry your letter.", "do": [["start_quest", &"tr_captains_apology"]], "next": "route"},
			{"text": "Not now.", "end": true},
		]},
		"route": {"text": "The ferry from this harbour goes to Full Moon Bay. Then north, to Northreach, and the crossing to the Water Tribe. A long road. Thank you.", "end": true},
	}},
	&"kuro_default": {"nodes": {
		"start": {"text": ["The sea is a harsh judge.", "The fleet sails at dawn. It always sails at dawn."], "end": true},
	}},
	&"hoshi_offer": {"nodes": {
		"start": {"lines": [
			"Komodo rhinos. A whole herd of the brutes in the Cinder Flats to the south, trampling the lower terraces at night.",
			"Our pickers are too frightened to go down. If a bender could drive them off, we would be grateful. And we pay in tea.",
		], "choices": [
			{"text": "I will deal with the rhinos.", "do": [["start_quest", &"fn_komodo_trouble"]], "end": true},
			{"text": "Not now.", "end": true},
		]},
	}},
	&"hoshi_done": {"nodes": {
		"start": {"lines": [
			"Gone? Truly? The pickers will sing tonight. Badly, but loudly.",
			"Take these lilies, and our thanks. And come back for tea. The terraces are prettier without rhinos in them.",
		], "end": true},
	}},
	&"hoshi_default": {"nodes": {
		"start": {"text": ["The tea bushes need rain and quiet.", "Mind the terraces, they crumble."], "end": true},
	}},
}

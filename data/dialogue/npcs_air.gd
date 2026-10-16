extends RefCounted
## Named characters of the Southern Air Temple and their dialogue. Original writing.

const SAT := &"southern_air_temple"

const NPCS := {
	&"at_pasang": {
		"name": "Brother Pasang", "title": "Keeper of the Arrival Plaza", "nation": &"air", "role": &"monk",
		"look": {"preset": &"air_nomad", "body": "male", "age": "adult", "seed": 3},
		"place": {"anchor": {"settlement": SAT, "kind": &"quest_giver", "tags": ["greeter"]}, "face": {"spawn": &"air"}},
		"barks": ["Welcome home, little brother of the wind.", "Mind the edge. The clouds are softer than they look, but not much."],
		"talk": [
			{"if": {"objective": [&"at_first_breath", &"meet_pasang"]}, "tree": &"pasang_welcome"},
			{"tree": &"pasang_default"},
		],
	},
	&"at_tashi": {
		"name": "Master Tashi", "title": "Airbending Master", "nation": &"air", "role": &"trainer",
		"look": {"preset": &"monk_elder", "body": "male", "age": "elder", "seed": 2},
		"place": {"anchor": {"settlement": SAT, "kind": &"trainer", "tags": ["master", "sanctum"]}},
		"barks": ["Light feet, light heart.", "The wind never meets a wall. It goes around."],
		"trainer": {"element": &"air", "spar": "Spar with Novice Tenzu",
			"menu": "The wind is restless today. So are you. What shall we practise?",
			"lesson_lines": ["Do not push the air. Invite it.", "Move in circles. Straight lines are for arrows and people in a hurry."],
			"praise": ["Ha! The wind laughed with you. Did you hear it?", "Light as a leaf. Well done."],
			"fail": ["You tried too hard. The wind dislikes effort.", "Breathe out. Let go. Again."]},
		"talk": [
			{"if": {"objective": [&"at_first_breath", &"meet_master"]}, "tree": &"tashi_meet"},
			{"if": {"objective": [&"at_leaves_on_the_wind", &"posts"]}, "tree": &"tashi_posts"},
			{"if": {"objective": [&"at_leaves_on_the_wind", &"report"]}, "tree": &"tashi_report"},
			{"if": {"objective": [&"at_the_wind_remembers", &"report"]}, "tree": &"tashi_wind_done"},
			{"tree": &"tashi_default"},
		],
	},
	&"at_dorje": {
		"name": "Abbot Dorje", "title": "Abbot of the Southern Air Temple", "nation": &"air", "role": &"elder",
		"look": {"preset": &"monk_elder", "body": "male", "age": "elder", "seed": 4},
		"place": {"anchor": {"settlement": SAT, "kind": &"quest_giver", "tags": ["abbot"]}},
		"barks": ["Peace is not the absence of wind, child.", "Have you eaten? You look like you have not eaten."],
		"talk": [
			{"if": {"objective": [&"at_the_wind_remembers", &"meet_abbot"]}, "tree": &"dorje_teaching"},
			{"if": {"objective": [&"tr_white_dragon_tea", &"deliver"]}, "tree": &"dorje_tea"},
			{"if": {"objective": [&"at_whistling_caves", &"return"]}, "tree": &"dorje_caves_done"},
			{"if": {"quest": [&"at_whistling_caves", "available"]}, "tree": &"dorje_offer_caves"},
			{"if": {"quest": [&"tr_a_letter_to_the_sun", "available"]}, "tree": &"dorje_offer_letter"},
			{"tree": &"dorje_default"},
		],
	},
	&"at_nima": {
		"name": "Sister Nima", "title": "Airball Coach", "nation": &"air", "role": &"trainer",
		"look": {"preset": &"air_nomad", "body": "female", "age": "adult", "seed": 2},
		"place": {"anchor": {"settlement": SAT, "kind": &"trainer", "tags": ["airball"]}},
		"barks": ["Airball! Who's next?", "Faster! The ball won't wait for you!"],
		"talk": [
			{"if": {"objective": [&"at_airball_champion", &"match"]}, "tree": &"nima_match"},
			{"if": {"quest": [&"at_airball_champion", "available"]}, "tree": &"nima_offer"},
			{"tree": &"nima_default"},
		],
	},
	&"at_sonam": {
		"name": "Brother Sonam", "title": "Keeper of the Pass", "nation": &"air", "role": &"monk",
		"look": {"preset": &"air_nomad", "body": "male", "age": "adult", "seed": 1},
		"place": {"anchor": {"settlement": SAT, "kind": &"quest_giver", "tags": ["gatekeeper"]}},
		"barks": ["A thousand steps down, a thousand steps up.", "The pass is quiet. Too quiet."],
		"talk": [
			{"if": {"objective": [&"at_shadow_at_the_gate", &"orders"]}, "tree": &"sonam_orders"},
			{"if": {"objective": [&"at_shadow_at_the_gate", &"report"]}, "tree": &"sonam_report"},
			{"tree": &"sonam_default"},
		],
	},
	&"at_yeshe": {
		"name": "Elder Yeshe", "title": "Temple Cook", "nation": &"air", "role": &"merchant", "shop": &"sat_kitchen",
		"look": {"preset": &"air_nomad", "body": "female", "age": "elder", "seed": 1},
		"place": {"anchor": {"settlement": SAT, "kind": &"quest_giver", "tags": ["elder", "sanctuary"]}},
		"barks": ["Pie! Fresh from the oven!", "No one leaves my kitchen hungry."],
		"talk": [{"tree": &"yeshe_default"}],
	},
	&"at_lhamo": {
		"name": "Keeper Lhamo", "title": "Keeper of the Bison Stables", "nation": &"air", "role": &"merchant", "shop": &"sat_novices",
		"look": {"preset": &"air_nomad", "body": "female", "age": "adult", "seed": 3},
		"place": {"anchor": {"settlement": SAT, "kind": &"quest_giver", "tags": ["stable_keeper"]}},
		"barks": ["Easy, big one. Easy.", "The bison sense storms before we do."],
		"talk": [{"tree": &"lhamo_default"}],
	},
	&"at_kunga": {
		"name": "Novice Kunga", "title": "A Very Embarrassed Novice", "nation": &"air", "role": &"student",
		"look": {"preset": &"air_nomad", "body": "male", "age": "child", "seed": 2},
		"place": {"anchor": {"settlement": SAT, "kind": &"student", "index": 0}},
		"barks": ["Please don't tell Master Tashi.", "It was a very strong gust!"],
		"talk": [
			{"if": {"objective": [&"at_novices_glider", &"return"]}, "tree": &"kunga_done"},
			{"if": {"quest": [&"at_novices_glider", "available"]}, "tree": &"kunga_offer"},
			{"tree": &"kunga_default"},
		],
	},
}

const TREES := {
	&"pasang_welcome": {"nodes": {
		"start": {"lines": [
			"Welcome back, {player}! Or welcome, at least. The wind brought you here, and the wind is never wrong. Late, often. Never wrong.",
			"This is the arrival plaza. Above us the courtyard, the terraces, and the sanctum at the very top, under the great spire.",
		], "next": "ask"},
		"ask": {"text": "Master Tashi asked to meet you. He says your breath is louder than your footsteps. That is unusual.", "choices": [
			{"text": "Where do I find him?", "next": "where"},
			{"text": "Tell me about the temple.", "next": "temple"},
		]},
		"temple": {"lines": [
			"Four temples, four winds. This is the southern one, the home of the bison and the best fruit pies in the world.",
			"The stables lie below us, the airball courts beside the sanctuary, and the meditation ledge out on the western pinnacle.",
		], "next": "where"},
		"where": {"text": "Climb to the sanctum, at the top of the stairs. He will be there, pretending not to wait for you.", "end": true},
	}},
	&"pasang_default": {"nodes": {
		"start": {"text": ["Mind the edge. The clouds are softer than they look, but not much.", "The bison came home early today. Rain, I think."], "end": true},
	}},
	&"tashi_meet": {"nodes": {
		"start": {"lines": [
			"There you are. You came up the stairs two at a time. That is too slow. Three at a time is better.",
			"Airbending is the element of freedom. We do not fight our opponent. We simply refuse to be where they strike.",
		], "next": "q"},
		"q": {"text": "Tell me: when the wind meets a mountain, what does it do?", "choices": [
			{"text": "It goes around.", "next": "around"},
			{"text": "It pushes harder.", "next": "harder"},
		]},
		"around": {"text": "Yes. And the mountain never knows it lost.", "next": "end"},
		"harder": {"text": "That is what earthbenders think the wind does. They are wrong, but do not tell them. They get upset.", "next": "end"},
		"end": {"text": "When you are ready, tell me, and we will see whether your gusts can find the posts.", "end": true},
	}},
	&"tashi_posts": {"nodes": {
		"start": {"text": "Six gusts on the posts. Palm, kick, burst. Light and quick. Ready?", "choices": [
			{"text": "Raise the posts.", "do": [["challenge", &"at_leaves_on_the_wind", &"posts"]], "next": "go"},
			{"text": "One moment.", "end": true},
		]},
		"go": {"text": "Do not push the air. Invite it to push for you.", "end": true},
	}},
	&"tashi_report": {"nodes": {
		"start": {"lines": [
			"Lovely. The third gust curled. Did you feel it curl? It means you stopped thinking.",
			"Now, less lovely news. Brother Sonam at the pass saw smoke in the valley. Fire Nation scouts, on the road to our temple.",
		], "next": "end"},
		"end": {"text": "We do not seek fights. But we do not let them climb our stairs either. Go and speak with Sonam at the bison landing.", "end": true},
	}},
	&"tashi_wind_done": {"nodes": {
		"start": {"lines": [
			"You sat on the ledge. Your eyes are clearer. Good.",
			"The wind remembers everything it has ever touched, and holds on to none of it. Now let me show you what that means for a bender.",
		], "end": true},
	}},
	&"tashi_default": {"nodes": {
		"start": {"text": ["Light feet, light heart.", "Back again? The wind likes you."], "choices": [
			{"text": "Train me.", "do": [["train"]], "end": true},
			{"text": "Any advice?", "next": "advice"},
			{"text": "Farewell, Master.", "end": true},
		]},
		"advice": {"text": "Never stand still in a fight. Dash, jump, glide. Let them tire themselves hitting the place you were.", "end": true},
	}},
	&"dorje_teaching": {"nodes": {
		"start": {"lines": [
			"Ah. The young one who chased the scouts back down the mountain without breaking a single bone. Theirs or yours.",
			"Tashi teaches the wind's movement. I will teach its stillness. Go to the meditation ledge on the western pinnacle, across the bridge.",
		], "next": "go"},
		"go": {"text": "Sit there until the wind forgets you are there. Then come back and tell Tashi what it said.", "end": true},
	}},
	&"dorje_tea": {"nodes": {
		"start": {"lines": [
			"White dragon tea? From Master Hu? He promised me this forty years ago, over a game of Pai Sho I let him win.",
			"I did not let him win. But I tell everyone that I did. Thank you, traveller. Stay for a cup.",
		], "do": [["take_item", &"tea_parcel", 1]], "end": true},
	}},
	&"dorje_offer_caves": {"nodes": {
		"start": {"lines": [
			"Below the temple, on the eastern cliffs, the Whistling Wind Caves sing when the weather turns. The old monks carved tablets there.",
			"Would you read one for me? My knees no longer agree with cliffs.",
		], "choices": [
			{"text": "I will go to the caves.", "do": [["start_quest", &"at_whistling_caves"]], "end": true},
			{"text": "Not now.", "end": true},
		]},
	}},
	&"dorje_caves_done": {"nodes": {
		"start": {"lines": [
			"'The wind that leaves returns as rain.' Yes. That is the one. I had forgotten.",
			"Thank you. Take some sage from the gardens. Burn a little before you meditate; it helps the mind sit still.",
		], "end": true},
	}},
	&"dorje_offer_letter": {"nodes": {
		"start": {"lines": [
			"I have written a letter I should have written long ago. To the sages of the Fire Nation's Sun Temple.",
			"The world is changing, child. Someone must carry the first word across it. Will it be you?",
		], "choices": [
			{"text": "I will carry it to the Fire Nation.", "do": [["start_quest", &"tr_a_letter_to_the_sun"]], "next": "route"},
			{"text": "Not now.", "end": true},
		]},
		"route": {"text": "From Foothills Landing the ferry goes to Full Moon Bay, and from there to Crimson Harbor. Or fly. The bison know the way.", "end": true},
	}},
	&"dorje_default": {"nodes": {
		"start": {"text": ["Peace is not the absence of wind.", "Have you eaten? Yeshe's pies are worth the stairs."], "end": true},
	}},
	&"nima_offer": {"nodes": {
		"start": {"lines": [
			"You! New one! You look fast. Are you fast? Everyone says they're fast.",
			"Airball works like this: knock the posts, keep moving, and never let the ball touch the ground. We'll skip the ball. Just the posts.",
		], "choices": [
			{"text": "I'll play.", "do": [["start_quest", &"at_airball_champion"]], "next": "now"},
			{"text": "Maybe later.", "end": true},
		]},
		"now": {"text": "Tell me when you're ready. Ten hits, forty seconds. The record is mine. Obviously.", "end": true},
	}},
	&"nima_match": {"nodes": {
		"start": {"text": "Ten hits on the posts in forty seconds. Anything goes. Ready?", "choices": [
			{"text": "Start the match!", "do": [["challenge", &"at_airball_champion", &"match"]], "end": true},
			{"text": "Not yet.", "end": true},
		]},
	}},
	&"nima_default": {"nodes": {
		"start": {"text": ["Airball! Who's next?", "You again? Good. You owe me a rematch."], "end": true},
	}},
	&"sonam_orders": {"nodes": {
		"start": {"lines": [
			"Smoke in the valley below the Gate of a Thousand Steps. A Fire Nation scouting party, camped in the foothills to the south-west.",
			"They have not climbed yet. I would like them to stop wanting to.",
		], "choices": [
			{"text": "I will go down.", "next": "walk"},
			{"text": "Is there a faster way down?", "next": "fly"},
		]},
		"walk": {"text": "Take the thousand steps, then follow the foothills south-west. Their fire will guide you.", "end": true},
		"fly": {"text": "Keeper Lhamo's bison will carry you to the gate below. Hold on. Do not look at the clouds, look at the horizon.", "do": [["travel", {"poi": &"at_pass_gate", "offset": Vector3(0, 0, 12)}, "A sky bison carries you down to the Gate of a Thousand Steps"]], "end": true},
	}},
	&"sonam_report": {"nodes": {
		"start": {"lines": [
			"Maps of the stairs. Counts of the bison. They meant to come back with more.",
			"And now they will not. Thank you, little brother. The abbot will want to speak with you.",
		], "do": [["take_item", &"scout_orders", 1]], "end": true},
	}},
	&"sonam_default": {"nodes": {
		"start": {"text": ["A thousand steps down, a thousand steps up.", "The pass is quiet now. Thanks to you."], "end": true},
	}},
	&"yeshe_default": {"nodes": {
		"start": {"text": ["No one leaves my kitchen hungry.", "Pie? Pie."], "choices": [
			{"text": "What's cooking?", "do": [["shop", &"sat_kitchen"]], "end": true},
			{"text": "Farewell.", "end": true},
		]},
	}},
	&"lhamo_default": {"nodes": {
		"start": {"text": ["Easy, big one. Easy.", "The novices make these by hand. Have a look."], "choices": [
			{"text": "Show me the novices' crafts.", "do": [["shop", &"sat_novices"]], "end": true},
			{"text": "Farewell.", "end": true},
		]},
	}},
	&"kunga_offer": {"nodes": {
		"start": {"lines": [
			"Psst. You won't tell Master Tashi, right? I was practising at the Glider's Leap and a gust took my glider.",
			"It's caught down on the ledge by the pavilion. I can't reach it without, um, falling. Could you?",
		], "choices": [
			{"text": "I'll get your glider.", "do": [["start_quest", &"at_novices_glider"]], "end": true},
			{"text": "You should tell your master.", "next": "tell"},
		]},
		"tell": {"text": "...You sound exactly like him. Fine. But if you change your mind, I'll be here. Being embarrassed.", "end": true},
	}},
	&"kunga_done": {"nodes": {
		"start": {"lines": [
			"My glider! Thank you, thank you! It's only a little torn. Wings heal, right?",
			"Here. I made this chime. It's my best one. It only plays one note, but it's a good note.",
		], "do": [["take_item", &"lost_glider", 1]], "end": true},
	}},
	&"kunga_default": {"nodes": {
		"start": {"text": ["Please don't tell Master Tashi.", "One day I'll glide all the way to the clouds."], "end": true},
	}},
}

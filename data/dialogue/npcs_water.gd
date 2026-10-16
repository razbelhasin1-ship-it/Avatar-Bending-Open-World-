extends RefCounted
## Named characters of the Northern Water Tribe and their dialogue (format:
## docs/modules/quests_npcs.md "Named NPCs" / "Dialogue trees"). Original writing.

const NWT := &"northern_water_tribe"

const NPCS := {
	&"wt_anaaya": {
		"name": "Elder Anaaya", "title": "Keeper of the Upper Tier", "nation": &"water", "role": &"elder",
		"look": {"preset": &"water_tribe", "body": "female", "age": "elder", "seed": 4},
		"place": {"spawn": &"water", "local": Vector3(1.8, 0, -5.5)},
		"barks": ["Walk the upper tier, child. Look at your city.", "Siku will be waiting. He hates waiting."],
		"talk": [
			{"if": {"objective": [&"wt_born_of_the_tide", &"meet_anaaya"]}, "tree": &"anaaya_welcome"},
			{"tree": &"anaaya_default"},
		],
	},
	&"wt_siku": {
		"name": "Master Siku", "title": "Waterbending Master", "nation": &"water", "role": &"trainer",
		"look": {"preset": &"water_tribe", "body": "male", "age": "elder", "seed": 2, "beard": "long"},
		"place": {"anchor": {"settlement": NWT, "kind": &"trainer", "tags": ["training_hall"]}},
		"barks": ["Feet rooted, arms loose. Again.", "Water does not hurry, yet it reaches the sea."],
		"trainer": {"element": &"water", "spar": "Spar with Kallik",
			"menu": "The tide waits for no one. What will you practise?",
			"lesson_lines": ["Watch the water, not my hands. The hands only follow.", "Feel the pull of the moon in your arms. Now push it back."],
			"praise": ["Good. The water listened to you. Keep it listening.", "Better than I expected. Do not let it go to your head."],
			"fail": ["The posts are still standing. So are you. Again, when your breath is calm.", "You fought the water. Flow with it."]},
		"talk": [
			{"if": {"objective": [&"wt_born_of_the_tide", &"meet_siku"]}, "tree": &"siku_meet"},
			{"if": {"objective": [&"wt_first_form", &"posts"]}, "tree": &"siku_posts"},
			{"if": {"objective": [&"wt_first_form", &"report"]}, "tree": &"siku_first_report"},
			{"if": {"objective": [&"wt_moon_and_ocean", &"bring_water"]}, "tree": &"siku_moon_water"},
			{"if": {"objective": [&"wt_ice_flats_trial", &"report"]}, "tree": &"siku_trial_done"},
			{"if": {"quest": [&"wt_ice_flats_trial", "available"]}, "tree": &"siku_offer_trial"},
			{"tree": &"siku_default"},
		],
	},
	&"wt_tulok": {
		"name": "Chief Tulok", "title": "Chief of the Northern Water Tribe", "nation": &"water", "role": &"noble",
		"look": {"preset": &"water_tribe", "body": "male", "age": "adult", "seed": 5, "beard": "goatee"},
		"place": {"anchor": {"settlement": NWT, "kind": &"quest_giver", "tags": ["chief"]}},
		"barks": ["Our walls are strong. Our people are stronger.", "Keep your eyes on the eastern ice."],
		"talk": [
			{"if": {"objective": [&"wt_smoke_on_the_horizon", &"summons"]}, "tree": &"tulok_summons"},
			{"if": {"objective": [&"wt_smoke_on_the_horizon", &"report"]}, "tree": &"tulok_report"},
			{"if": {"objective": [&"tr_captains_apology", &"deliver"]}, "tree": &"tulok_apology"},
			{"tree": &"tulok_default"},
		],
	},
	&"wt_naalu": {
		"name": "Princess Naalu", "title": "Daughter of the Chief", "nation": &"water", "role": &"noble",
		"look": {"preset": &"water_tribe", "body": "female", "age": "teen", "seed": 6, "hair_color": Color(0.94, 0.94, 0.96)},
		"place": {"anchor": {"settlement": NWT, "kind": &"quest_giver", "tags": ["princess"]}},
		"idle": &"stand",
		"barks": ["Listen. Tui and La are circling.", "The oasis is never cold. Have you noticed?"],
		"talk": [
			{"if": {"objective": [&"wt_moon_and_ocean", &"meet_naalu"]}, "tree": &"naalu_meet"},
			{"if": {"quest": [&"wt_pale_moon_shrine", "available"]}, "tree": &"naalu_offer_shrine"},
			{"tree": &"naalu_default"},
		],
	},
	&"wt_yara": {
		"name": "Healer Yara", "title": "Healer of the Upper Tier", "nation": &"water", "role": &"merchant", "shop": &"nwt_healer",
		"look": {"preset": &"water_tribe", "body": "female", "age": "adult", "seed": 3},
		"place": {"anchor": {"settlement": NWT, "kind": &"healer"}},
		"barks": ["Sit, sit. Show me where it hurts.", "Moss, broth and patience. The best medicines."],
		"talk": [
			{"if": {"objective": [&"wt_healers_moss", &"return"]}, "tree": &"yara_moss_done"},
			{"if": {"quest": [&"wt_healers_moss", "available"]}, "tree": &"yara_offer"},
			{"tree": &"yara_default"},
		],
	},
	&"wt_oki": {
		"name": "Harbourmaster Oki", "title": "Keeper of the Sea Gate Docks", "nation": &"water", "role": &"merchant", "shop": &"nwt_outfitter",
		"look": {"preset": &"villager_water", "body": "male", "age": "adult", "seed": 2},
		"place": {"anchor": {"settlement": NWT, "kind": &"quest_giver", "tags": ["harbor_master"]}},
		"barks": ["Ferry to Northreach at the next tide!", "Mind the ropes, they bite."],
		"talk": [
			{"if": {"quest": [&"tr_letters_across_the_strait", "available"]}, "tree": &"oki_offer_letter"},
			{"tree": &"oki_default"},
		],
	},
	&"wt_tikaani": {
		"name": "Old Tikaani", "title": "Net Mender", "nation": &"water", "role": &"fisher",
		"look": {"preset": &"villager_water", "body": "male", "age": "elder", "seed": 1, "beard": "long"},
		"place": {"anchor": {"settlement": NWT, "kind": &"fisher", "tags": ["pier"], "index": 4}},
		"barks": ["My nets, my poor nets.", "Fish don't catch themselves, you know."],
		"talk": [
			{"if": {"objective": [&"wt_tangled_nets", &"return"]}, "tree": &"tikaani_done"},
			{"if": {"quest": [&"wt_tangled_nets", "available"]}, "tree": &"tikaani_offer"},
			{"tree": &"tikaani_default"},
		],
	},
}

const TREES := {
	&"anaaya_welcome": {"nodes": {
		"start": {"lines": [
			"There you are. The ice gave you back to us, {player}. Breathe the air up here. It is the cleanest in the world.",
			"This is the upper tier. Below us the middle tier, then the harbour, then the sea wall that keeps the ocean polite.",
		], "next": "ask"},
		"ask": {"text": "Your gift woke early. A bender untrained is a wave without a shore. Will you learn?", "choices": [
			{"text": "I want to learn. Who will teach me?", "next": "siku"},
			{"text": "What should I know about the city?", "next": "city"},
		]},
		"city": {"lines": [
			"The palace sits highest, on the northern ice. Chief Tulok rules from there, and listens more than most chiefs do.",
			"Behind the palace lies the Spirit Oasis. Tui and La swim there, the moon and the ocean. Be quiet when you visit.",
			"And the healers keep their hut on this tier. You will meet them soon, I suspect. Students always do.",
		], "next": "siku"},
		"siku": {"lines": [
			"Master Siku trains benders in the great hall, east along this tier. Follow the canal and look for the banners.",
			"He is strict. He was strict with me, and I was the Chief's cousin. Go on.",
		], "end": true},
	}},
	&"anaaya_default": {"nodes": {
		"start": {"branch": [
			{"if": {"quest": [&"wt_first_form", "active"]}, "next": "training"},
			{"if": {"quest": [&"wt_smoke_on_the_horizon", "active"]}, "next": "smoke"},
			{"if": {"quest": [&"wt_moon_and_ocean", "completed"]}, "next": "proud"},
			{"next": "plain"}]},
		"training": {"text": "How is Siku treating you? Badly? Good. It means he thinks you are worth the trouble.", "end": true},
		"smoke": {"text": "Smoke on the eastern ice, they say. The Chief will want every bender he can trust. Be careful out there.", "end": true},
		"proud": {"text": "The oasis water answered you. I heard Siku smiled. Twice. The children are calling it a miracle.", "end": true},
		"plain": {"text": ["The ice sings when the wind turns. Listen for it.", "Eat something warm before you go anywhere. That is an order from an elder."], "end": true},
	}},
	&"siku_meet": {"nodes": {
		"start": {"lines": [
			"So Anaaya sends me another one. Stand there. No, there, on the mark. Let me look at you.",
			"Hm. Your shoulders are tight. Your feet do not trust the floor. And you are breathing like a frightened seal.",
		], "next": "q"},
		"q": {"text": "Every student believes they are ready. Are you?", "choices": [
			{"text": "Ready enough to begin.", "next": "good"},
			{"text": "Not yet. That is why I am here.", "next": "better"},
		]},
		"good": {"text": "Enough is a dangerous word. We will find out what it means.", "next": "end"},
		"better": {"text": "...That is the first sensible thing a student has said to me this season.", "next": "end"},
		"end": {"text": "Your first form begins now. When you are ready, tell me, and the posts will rise.", "end": true},
	}},
	&"siku_posts": {"nodes": {
		"start": {"text": "The whip is the first form. Six clean strikes on the training posts. The water must snap, not slop. Ready?", "choices": [
			{"text": "Raise the posts.", "do": [["challenge", &"wt_first_form", &"posts"]], "next": "go"},
			{"text": "Give me a moment.", "next": "wait"},
		]},
		"go": {"text": "Light strikes. Let the water lead your hand.", "end": true},
		"wait": {"text": "The posts are patient. I am less so.", "end": true},
	}},
	&"siku_first_report": {"nodes": {
		"start": {"lines": [
			"Hm. Not terrible. Your third strike was even good. Do not ask me which one was the third.",
			"Take this waterskin. A waterbender without water is just someone with strong opinions.",
		], "do": [["give_item", &"waterskin", 1]], "next": "news"},
		"news": {"text": "Now go. A runner came from the palace while you were sweating. The Chief asks for you by name.", "end": true},
	}},
	&"siku_moon_water": {"nodes": {
		"start": {"lines": [
			"You carry water from the oasis. I can feel it from here; it is colder than the night.",
			"Tui and La do not speak to everyone. If the princess sent you, they must have listened back.",
		], "next": "teach"},
		"teach": {"text": "Then you are ready for something larger than a whip. Stand firm. Pull the tide to you, and let it go.", "do": [["take_item", &"moon_water", 1]], "end": true},
	}},
	&"siku_offer_trial": {"nodes": {
		"start": {"lines": [
			"Kallik has been boasting that no student of this season can best her on the Ice Flats.",
			"The flats lie west of the city, on the frozen lake. Go there. Prove her wrong, or learn why she is right.",
		], "choices": [
			{"text": "I will meet her on the ice.", "do": [["start_quest", &"wt_ice_flats_trial"]], "end": true},
			{"text": "Train me instead.", "do": [["train"]], "end": true},
			{"text": "Another time.", "end": true},
		]},
	}},
	&"siku_trial_done": {"nodes": {
		"start": {"lines": [
			"Kallik came back soaked and grinning, and told everyone you fought like a winter storm.",
			"She exaggerates. But not by much. Here. You have earned the right to choose your next lesson.",
		], "end": true},
	}},
	&"siku_default": {"nodes": {
		"start": {"text": ["You came back. Good. Habit is half of mastery.", "Breathe first. Then speak."], "choices": [
			{"text": "Train me.", "do": [["train"]], "end": true},
			{"text": "How do I get stronger?", "next": "advice"},
			{"text": "Farewell, Master.", "end": true},
		]},
		"advice": {"text": "Fight. Fail. Return. And listen to the water near you: a bender beside the sea is twice a bender in the desert.", "end": true},
	}},
	&"tulok_summons": {"nodes": {
		"start": {"lines": [
			"So you are Siku's newest. He says you are stubborn. From him, that is high praise.",
			"Hunters saw smoke on the eastern ice at dawn. Black smoke. Fire Navy smoke. A landing party, east of the city, past the cliffs.",
		], "next": "ask"},
		"ask": {"text": "I will not send warriors to start a war over smoke. But a bender, quietly, to look? Will you go?", "choices": [
			{"text": "I will find out what they want.", "next": "go"},
			{"text": "Why me?", "next": "why"},
		]},
		"why": {"text": "Because they will expect warriors, and they will not expect you. And because Siku vouches for you. Do not make him regret it.", "next": "go"},
		"go": {"text": "Their camp lies about a kilometre east. If they fight, drive them off. If they carry orders, bring them to me.", "end": true},
	}},
	&"tulok_report": {"nodes": {
		"start": {"lines": [
			"Sealed Fire Navy orders. Let me see.",
			"Soundings of the sea gate. Counts of our canoes. They are not raiding. They are measuring us.",
		], "next": "thanks"},
		"thanks": {"text": "You have done the tribe a great service, and quietly. Go to the oasis. My daughter wishes to meet the bender everyone is whispering about.", "do": [["take_item", &"navy_orders", 1]], "end": true},
	}},
	&"tulok_apology": {"nodes": {
		"start": {"lines": [
			"A letter from a Fire Navy admiral. In my hands. Carried by you. The world is stranger every year.",
			"He apologises for the landing on our ice. He says it was not his order, and that he will not let it happen again.",
		], "next": "end"},
		"end": {"text": "Words are cheap, but they are a start. Thank you. Perhaps the next generation will trade letters instead of fire.", "do": [["take_item", &"admiral_letter", 1]], "end": true},
	}},
	&"tulok_default": {"nodes": {
		"start": {"text": ["The tribe is stronger with you in it.", "The sea gate holds. Thanks in part to you."], "end": true},
	}},
	&"naalu_meet": {"nodes": {
		"start": {"lines": [
			"Shh. Come, stand here. Look: the white one is Tui, the moon. The black one is La, the ocean.",
			"They have circled each other since before the first bender lifted a drop. Push and pull. Neither ever wins.",
		], "next": "ask"},
		"ask": {"text": "My father says you saw the Fire Navy's orders. Does it frighten you, that they are measuring us?", "choices": [
			{"text": "A little.", "next": "honest"},
			{"text": "No. We will be ready.", "next": "brave"},
		]},
		"honest": {"text": "Good. Fear means you understand what you could lose.", "next": "task"},
		"brave": {"text": "You sound like my father before his morning tea.", "next": "task"},
		"task": {"text": "Draw a little water from the pond. Gently. Take it to Master Siku. He will know what it means. I think it means you are ready.", "end": true},
	}},
	&"naalu_offer_shrine": {"nodes": {
		"start": {"lines": [
			"There is an old shrine on the eastern shore, the Shrine of the Pale Moon. No one has lit incense there since the war began.",
			"Would you take this incense and light it for me? I cannot leave the palace without six guards and a speech.",
		], "choices": [
			{"text": "I will light it.", "do": [["start_quest", &"wt_pale_moon_shrine"]], "end": true},
			{"text": "Not now.", "end": true},
		]},
	}},
	&"naalu_default": {"nodes": {
		"start": {"text": ["They are circling faster tonight. Something is changing.", "Thank you for listening to them. Most people only look."], "end": true},
	}},
	&"yara_offer": {"nodes": {
		"start": {"lines": [
			"Ah, a bender with two working hands and no fever. Exactly what I need.",
			"My healing moss is nearly gone. It grows under the snow at the Ice Flats, west of the city, where the lake meets the rocks.",
		], "choices": [
			{"text": "I will gather some for you.", "do": [["start_quest", &"wt_healers_moss"]], "next": "thanks"},
			{"text": "Can I see your remedies first?", "do": [["shop", &"nwt_healer"]], "end": true},
			{"text": "Not today.", "end": true},
		]},
		"thanks": {"text": "Four bundles. Pale green, smells like the sea. If it smells like a seal, that is a seal. Leave it.", "end": true},
	}},
	&"yara_moss_done": {"nodes": {
		"start": {"lines": [
			"Four bundles and not one of them a seal. You have a healer's eye.",
			"Take these salves for your trouble. You will need them, the way you students throw yourselves at things.",
		], "do": [["take_item", &"arctic_moss", 4]], "end": true},
	}},
	&"yara_default": {"nodes": {
		"start": {"text": ["Sit, sit. Show me where it hurts.", "Back again? Not bleeding? Good."], "choices": [
			{"text": "Show me your remedies.", "do": [["shop", &"nwt_healer"]], "end": true},
			{"text": "Heal me, please.", "do": [["heal"]], "next": "healed"},
			{"text": "Farewell.", "end": true},
		]},
		"healed": {"text": "There. Water remembers how a body should be. You only have to remind it.", "end": true},
	}},
	&"oki_offer_letter": {"nodes": {
		"start": {"lines": [
			"You! Bender! You look like someone who can stand on a ferry without being sick.",
			"I have a letter for the elder of Northreach Harbor, across the strait in the Earth Kingdom. My runner broke his leg. On a fish.",
		], "choices": [
			{"text": "I will carry it.", "do": [["start_quest", &"tr_letters_across_the_strait"]], "next": "go"},
			{"text": "Tell me about the ferry first.", "next": "ferry"},
			{"text": "Not now.", "end": true},
		]},
		"ferry": {"text": "Ferry master's post is at the end of the quay. Take it to Northreach; it is a short, wet crossing. Then the Earth Kingdom is under your feet.", "choices": [
			{"text": "I will carry the letter.", "do": [["start_quest", &"tr_letters_across_the_strait"]], "next": "go"},
			{"text": "Not now.", "end": true},
		]},
		"go": {"text": "Elder Mok, at the harbour. Grumpy man. Likes letters, though. Safe crossing!", "end": true},
	}},
	&"oki_default": {"nodes": {
		"start": {"text": ["Ferries, ropes, oil, fish. What do you need?", "Mind the ropes, they bite."], "choices": [
			{"text": "Show me your supplies.", "do": [["shop", &"nwt_outfitter"]], "end": true},
			{"text": "Where does the ferry go?", "next": "ferry"},
			{"text": "Farewell.", "end": true},
		]},
		"ferry": {"text": "Across the strait to Northreach Harbor. From there the roads run south to Omashu and Ba Sing Se, and the coast to Full Moon Bay.", "end": true},
	}},
	&"tikaani_offer": {"nodes": {
		"start": {"lines": [
			"Last night's storm threw my nets across half the harbour. Three of them, tangled like an otter-penguin's bad day.",
			"My knees are older than the sea wall. Would you fetch them from the piers? Bring back the floats, at least.",
		], "choices": [
			{"text": "I will find your nets.", "do": [["start_quest", &"wt_tangled_nets"]], "end": true},
			{"text": "Sorry, I am busy.", "end": true},
		]},
	}},
	&"tikaani_done": {"nodes": {
		"start": {"lines": [
			"My floats! All three! You have the patience of a fisher, young one.",
			"Here: smoked char, the best in the harbour. Don't tell my wife I gave you the good ones.",
		], "do": [["take_item", &"net_float", 3]], "end": true},
	}},
	&"tikaani_default": {"nodes": {
		"start": {"text": ["The cod are running fat this season.", "A good net is like a good friend. Holds when it matters."], "end": true},
	}},
}

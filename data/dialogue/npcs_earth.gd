extends RefCounted
## Named characters of the Earth Kingdom (Ba Sing Se, its farmland, Northreach, Omashu) and their
## dialogue. Original writing.

const BSS := &"ba_sing_se"

const NPCS := {
	&"ek_lin": {
		"name": "Guide Lin", "title": "Guide of the Upper Ring", "nation": &"earth", "role": &"elder",
		"look": {"preset": &"earth_kingdom", "body": "female", "age": "adult", "seed": 4},
		"place": {"anchor": {"settlement": BSS, "kind": &"quest_giver", "tags": ["overlook", "guide"]}, "face": {"spawn": &"earth"}},
		"barks": ["Welcome to the Upper Ring. Mind the steps, they are older than the King.", "The view never gets old."],
		"talk": [
			{"if": {"objective": [&"ek_stone_beneath_the_sky", &"meet_lin"]}, "tree": &"lin_welcome"},
			{"if": {"quest": [&"ek_mail_for_omashu", "available"]}, "tree": &"lin_offer_mail"},
			{"tree": &"lin_default"},
		],
	},
	&"ek_bao_shan": {
		"name": "Master Bao Shan", "title": "Earthbending Master", "nation": &"earth", "role": &"trainer",
		"look": {"preset": &"earth_kingdom", "body": "male", "age": "elder", "seed": 2, "beard": "long", "bulk": 0.5},
		"place": {"anchor": {"settlement": BSS, "kind": &"trainer", "tags": ["earthbending"]}},
		"barks": ["Wait. Listen. Strike.", "The mountain does not hurry, and yet it wins."],
		"trainer": {"element": &"earth", "spar": "Spar with Senior Student Bao",
			"menu": "Plant your feet. Now, what will you learn?",
			"lesson_lines": ["Feel the stone before you move it. It will tell you when it is ready.", "Sink your weight. Become heavier than your fear."],
			"praise": ["Solid. Like a good wall. Now keep it standing.", "Ha! The stone moved for you. It does not do that for everyone."],
			"fail": ["You rushed. Stone punishes the impatient.", "Root yourself first, then try again."]},
		"talk": [
			{"if": {"objective": [&"ek_stone_beneath_the_sky", &"meet_master"]}, "tree": &"bao_meet"},
			{"if": {"objective": [&"ek_rooted", &"posts"]}, "tree": &"bao_posts"},
			{"if": {"objective": [&"ek_rooted", &"report"]}, "tree": &"bao_report"},
			{"if": {"objective": [&"ek_the_listening_earth", &"return"]}, "tree": &"bao_listening"},
			{"if": {"objective": [&"ek_the_listening_earth", &"report"]}, "tree": &"bao_listening_done"},
			{"tree": &"bao_default"},
		],
	},
	&"ek_jin": {
		"name": "Captain Jin", "title": "Captain of the West Gate", "nation": &"earth", "role": &"guard",
		"look": {"preset": &"earth_soldier", "body": "male", "age": "adult", "seed": 3},
		"place": {"anchor": {"settlement": BSS, "kind": &"quest_giver", "tags": ["gatekeeper", "west"]}},
		"barks": ["State your business at the gate.", "Nothing gets past this wall. Nothing."],
		"talk": [
			{"if": {"objective": [&"ek_smoke_beyond_the_wall", &"orders"]}, "tree": &"jin_orders"},
			{"if": {"objective": [&"ek_smoke_beyond_the_wall", &"report"]}, "tree": &"jin_report"},
			{"tree": &"jin_default"},
		],
	},
	&"ek_hu": {
		"name": "Tea Master Hu", "title": "Keeper of the Jasmine Kettle", "nation": &"earth", "role": &"merchant", "shop": &"bss_tea_house",
		"look": {"preset": &"earth_kingdom", "body": "male", "age": "elder", "seed": 1, "bulk": 0.5, "beard": "goatee"},
		"place": {"anchor": {"settlement": BSS, "kind": &"quest_giver", "tags": ["tea_master"]}},
		"barks": ["Tea first. Troubles after.", "Sit. The kettle is almost singing."],
		"talk": [
			{"if": {"quest": [&"tr_white_dragon_tea", "available"]}, "tree": &"hu_offer_tea"},
			{"tree": &"hu_default"},
		],
	},
	&"ek_wen": {
		"name": "Herbalist Wen", "title": "Root and Leaf", "nation": &"earth", "role": &"merchant", "shop": &"bss_herbalist",
		"look": {"preset": &"earth_kingdom", "body": "female", "age": "adult", "seed": 2},
		"place": {"anchor": {"settlement": BSS, "kind": &"quest_giver", "tags": ["market", "merchant_guild"], "index": 0}},
		"barks": ["Roots for the body, leaves for the mind!", "Ginseng, fresh from the hills!"],
		"talk": [
			{"if": {"objective": [&"ek_jade_for_wen", &"return"]}, "tree": &"wen_jade_done"},
			{"if": {"quest": [&"ek_jade_for_wen", "available"]}, "tree": &"wen_offer"},
			{"tree": &"wen_default"},
		],
	},
	&"ek_dao": {
		"name": "Farmer Dao", "title": "Elder of the Western Fields", "nation": &"earth", "role": &"elder",
		"look": {"preset": &"villager_earth", "body": "male", "age": "elder", "seed": 2},
		"place": {"anchor": {"settlement": BSS, "kind": &"quest_giver", "tags": ["farm_elder"], "index": 2}},
		"barks": ["Have you seen a little girl? About so high?", "The millet is tall this year."],
		"talk": [
			{"if": {"objective": [&"ek_lost_in_the_fields", &"thanks"]}, "tree": &"dao_thanks"},
			{"if": {"quest": [&"ek_lost_in_the_fields", "available"]}, "tree": &"dao_offer"},
			{"tree": &"dao_default"},
		],
	},
	&"ek_mei": {
		"name": "Little Mei", "title": "Lost in the Millet", "nation": &"earth", "role": &"escort",
		"look": {"preset": &"villager_earth", "body": "female", "age": "child", "seed": 1},
		"place": {"poi": &"ek_stonefist_yard", "offset": Vector3(-46, 0, -38), "ground": true, "face": {"poi": &"ek_stonefist_yard"}},
		"present": {"quest": [&"ek_lost_in_the_fields", "active"]},
		"barks": ["Grandpa? Grandpa!", "Are we nearly there?"],
		"talk": [
			{"if": {"objective": [&"ek_lost_in_the_fields", &"calm"]}, "tree": &"mei_found"},
			{"tree": &"mei_default"},
		],
	},
	&"ek_mok": {
		"name": "Elder Mok", "title": "Elder of Northreach Harbor", "nation": &"earth", "role": &"elder",
		"look": {"preset": &"villager_earth", "body": "male", "age": "elder", "seed": 1, "beard": "goatee"},
		"place": {"anchor": {"settlement": &"ek_villages", "kind": &"quest_giver", "tags": ["northreach", "elder"]}},
		"barks": ["The ferry is late again.", "Northreach remembers its friends."],
		"talk": [
			{"if": {"objective": [&"tr_letters_across_the_strait", &"deliver"]}, "tree": &"mok_letter"},
			{"tree": &"mok_default"},
		],
	},
	&"ek_pim": {
		"name": "Clerk Pim", "title": "Mail Clerk of Omashu", "nation": &"earth", "role": &"worker",
		"look": {"preset": &"villager_earth", "body": "male", "age": "adult", "seed": 2},
		"place": {"anchor": {"settlement": &"omashu", "kind": &"quest_giver", "tags": ["mail_clerk"]}},
		"barks": ["Parcels to the left, letters to the right, screaming to the chutes!", "Fastest mail in the world!"],
		"talk": [
			{"if": {"objective": [&"ek_mail_for_omashu", &"deliver"]}, "tree": &"pim_letter"},
			{"tree": &"pim_default"},
		],
	},
}

const TREES := {
	&"lin_welcome": {"nodes": {
		"start": {"lines": [
			"Welcome home, {player}. Or welcome, at least. Ba Sing Se is everyone's home, if you listen to the officials.",
			"From the overlook you can see all three rings: the Upper Ring where we stand, the Middle Ring below, and the Lower Ring by the great walls.",
		], "next": "ask"},
		"ask": {"text": "They say you have the gift. The earth listens to you. Do you want it to listen better?", "choices": [
			{"text": "Yes. Where do I train?", "next": "hall"},
			{"text": "Tell me about the city first.", "next": "city"},
		]},
		"city": {"lines": [
			"Two walls guard us: the Outer Wall around the farmland and the Inner Wall around the city. No army has ever broken either.",
			"The farmers of the Agrarian Zone feed us all. The Lower Ring has the best tea, whatever the Upper Ring says. And the palace... watches.",
		], "next": "hall"},
		"hall": {"lines": [
			"Master Bao Shan teaches in the training hall of the Middle Ring, down the grand stair to the south.",
			"He will make you lift rocks until your arms forget your name. It works, apparently.",
		], "end": true},
	}},
	&"lin_offer_mail": {"nodes": {
		"start": {"lines": [
			"Before you go: I have a letter for my brother's friend Pim, the mail clerk in Omashu. The road runs west, past the farms and the canyons.",
			"You could take it, if you want to see the greatest city in the world. The second greatest, I mean.",
		], "choices": [
			{"text": "I will take it to Omashu.", "do": [["start_quest", &"ek_mail_for_omashu"]], "end": true},
			{"text": "Not now.", "end": true},
		]},
	}},
	&"lin_default": {"nodes": {
		"start": {"text": ["The rings look smaller from up here, don't they?", "The gates close at dusk. Mostly.", "Have you tried the egg custard tarts? You must."], "end": true},
	}},
	&"bao_meet": {"nodes": {
		"start": {"lines": [
			"Hm. Stand there. No. Lower. Lower still. You stand like a reed in the wind.",
			"Earth is the element of substance. Of waiting. You will learn to wait, and when the moment comes you will not move. The world will.",
		], "next": "q"},
		"q": {"text": "Do you understand?", "choices": [
			{"text": "Not yet.", "next": "honest"},
			{"text": "I think so.", "next": "think"},
		]},
		"honest": {"text": "Good. A student who understands on the first day is a student who was not listening.", "next": "end"},
		"think": {"text": "Thinking is the wind talking. The stone does not think. We will fix that.", "next": "end"},
		"end": {"text": "When you are ready, tell me. The training posts rise when I say so.", "end": true},
	}},
	&"bao_posts": {"nodes": {
		"start": {"text": "Six strikes on the posts. Rock from the floor, through the fist, into the target. Ready?", "choices": [
			{"text": "Raise the posts.", "do": [["challenge", &"ek_rooted", &"posts"]], "next": "go"},
			{"text": "One moment.", "end": true},
		]},
		"go": {"text": "Feel the floor first. Then strike.", "end": true},
	}},
	&"bao_report": {"nodes": {
		"start": {"lines": [
			"The posts are still standing. That is fine. They are very old posts. You hit them, which is what matters.",
			"Drink this. Ginseng tea. It tastes like a forest floor and it will keep your breath steady.",
		], "next": "news"},
		"news": {"text": "Now go to the west gate. Captain Jin sent for any bender who can be spared. He says there is smoke beyond the wall.", "end": true},
	}},
	&"bao_listening": {"nodes": {
		"start": {"lines": [
			"Fire Nation scouts, a stone's throw from our walls. And you sent them running. Good.",
			"Now the harder lesson. Go to the Stonefist Training Yard in the fields beyond the gate. My senior student waits there.",
		], "next": "end"},
		"end": {"text": "Hold the yard. Do not chase. Let her come to you, and let the earth answer.", "end": true},
	}},
	&"bao_listening_done": {"nodes": {
		"start": {"lines": [
			"She yielded? Bao never yields to me. Hm. Perhaps I should be worried.",
			"You have learned to wait and to answer. That is the listening earth. Now I will show you what it can say.",
		], "end": true},
	}},
	&"bao_default": {"nodes": {
		"start": {"text": ["Lower your stance.", "You again. Good. Rocks do not lift themselves."], "choices": [
			{"text": "Train me.", "do": [["train"]], "end": true},
			{"text": "Any advice?", "next": "advice"},
			{"text": "Farewell, Master.", "end": true},
		]},
		"advice": {"text": "When an enemy charges, plant your feet and raise a wall. Let them meet the earth instead of you.", "end": true},
	}},
	&"jin_orders": {"nodes": {
		"start": {"lines": [
			"You're Bao Shan's student? Good. My soldiers are stretched thin along the wall and I need someone quick.",
			"Smoke rose this morning just west of the gate, out past the farms. Fire Nation scouts, if I'm any judge, camped where they can count our patrols.",
		], "next": "go"},
		"go": {"text": "Clear them out. And if they wrote anything down, bring it to me.", "end": true},
	}},
	&"jin_report": {"nodes": {
		"start": {"lines": [
			"Patrol times. Gate counts. They were measuring us. Cheeky.",
			"You did good work today, bender. The wall stands a little taller for it.",
		], "do": [["take_item", &"scout_orders", 1]], "end": true},
	}},
	&"jin_default": {"nodes": {
		"start": {"text": ["Nothing gets past this wall.", "Move along, citizen. Unless you are a bender. Then stay a while."], "end": true},
	}},
	&"hu_offer_tea": {"nodes": {
		"start": {"lines": [
			"Ah, a traveller. Sit. Before you ask, yes, the tea is free for those who sit, and very expensive for those who stand.",
			"I owe the Abbot of the Southern Air Temple a parcel of white dragon tea. A promise from long ago. The monks still visit my dreams about it.",
		], "choices": [
			{"text": "I can carry it to the temple.", "do": [["start_quest", &"tr_white_dragon_tea"]], "next": "route"},
			{"text": "May I see your teas?", "do": [["shop", &"bss_tea_house"]], "end": true},
			{"text": "Just the tea, thank you.", "end": true},
		]},
		"route": {"text": "Take the road south to Full Moon Bay, then the ferry to Foothills Landing. Then climb. Or fly, if you know anyone with a bison.", "end": true},
	}},
	&"hu_default": {"nodes": {
		"start": {"text": ["Tea first. Troubles after.", "Even the best fire needs good leaves."], "choices": [
			{"text": "What teas do you have?", "do": [["shop", &"bss_tea_house"]], "end": true},
			{"text": "Any wisdom today?", "next": "wisdom"},
			{"text": "Farewell.", "end": true},
		]},
		"wisdom": {"text": ["Leaves steep best in water that is hot, but not boiling. People too.", "A bitter cup still warms the hands."], "end": true},
	}},
	&"wen_offer": {"nodes": {
		"start": {"lines": [
			"You look strong. Jade-hauling strong. My grinding stones need jade dust for the good salves.",
			"The Jade Quarry lies east of the city, outside the wall. The shards glow green. Bring me three and I will make it worth your while.",
		], "choices": [
			{"text": "I will bring you jade.", "do": [["start_quest", &"ek_jade_for_wen"]], "end": true},
			{"text": "Show me your wares.", "do": [["shop", &"bss_herbalist"]], "end": true},
			{"text": "Not today.", "end": true},
		]},
	}},
	&"wen_jade_done": {"nodes": {
		"start": {"lines": [
			"Three shards, and not a scratch on them. Or on you. Impressive.",
			"Take some roots for the road. And come back when you need salves. I give good prices to good haulers.",
		], "end": true},
	}},
	&"wen_default": {"nodes": {
		"start": {"text": ["Roots for the body, leaves for the mind.", "What ails you, traveller?"], "choices": [
			{"text": "Show me your wares.", "do": [["shop", &"bss_herbalist"]], "end": true},
			{"text": "Farewell.", "end": true},
		]},
	}},
	&"dao_offer": {"nodes": {
		"start": {"lines": [
			"Please, bender, please. My granddaughter Mei went chasing a hopper-rabbit into the millet this morning and has not come back.",
			"She cannot have gone far. Past the Stonefist yard, maybe. She is small, and loud, and she will be very cross.",
		], "choices": [
			{"text": "I will find her.", "do": [["start_quest", &"ek_lost_in_the_fields"]], "end": true},
			{"text": "I cannot help right now.", "end": true},
		]},
	}},
	&"dao_thanks": {"nodes": {
		"start": {"lines": [
			"Mei! Oh, you silly child. Come here. No, closer. Never run off like that again.",
			"Thank you, bender. Take these. They are only rice balls, but my wife makes the best in the fields.",
		], "end": true},
	}},
	&"dao_default": {"nodes": {
		"start": {"text": ["The millet is tall this year.", "Rain tomorrow. My knee says so."], "end": true},
	}},
	&"mei_found": {"nodes": {
		"start": {"lines": [
			"I wasn't lost! I knew exactly where I was. I was... here.",
			"...Can you take me back to Grandpa? The millet keeps moving when I'm not looking.",
		], "end": true},
	}},
	&"mei_default": {"nodes": {
		"start": {"text": ["Are we nearly there?", "Can you bend a rock into a rabbit? Please?"], "end": true},
	}},
	&"mok_letter": {"nodes": {
		"start": {"lines": [
			"A letter? From Oki? That old walrus still writes? Let me see.",
			"Hah! He wants to trade sea prunes for our pickled radish again. Some things never change, praise the spirits.",
		], "next": "end"},
		"end": {"text": "Thank you, traveller. Northreach remembers its friends. If you head south, the road leads to Omashu and Ba Sing Se.", "do": [["take_item", &"letter_northreach", 1]], "end": true},
	}},
	&"mok_default": {"nodes": {
		"start": {"text": ["The ferry is late again.", "Northreach remembers its friends."], "end": true},
	}},
	&"pim_letter": {"nodes": {
		"start": {"lines": [
			"A letter! By hand! How charmingly slow. Who is it from? Ah, Lin's brother. Of course.",
			"Here, a little something from the post office. Now, would you like to send anything by chute? No? Everyone says no. Cowards.",
		], "do": [["take_item", &"letter_omashu", 1]], "end": true},
	}},
	&"pim_default": {"nodes": {
		"start": {"text": ["Parcels to the left, letters to the right!", "The chutes are perfectly safe. Mostly."], "end": true},
	}},
}

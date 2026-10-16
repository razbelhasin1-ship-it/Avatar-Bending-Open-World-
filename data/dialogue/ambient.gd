extends RefCounted
## Ambient lines: floating barks (greetings, merchants calling, reactions to bending and combat)
## and small talk shown when the player talks to an unnamed townsperson. Per nation, then
## situation / role; "any" applies to every nation. Original writing.

const BARKS := {
	&"any": {
		&"flee": ["Run!", "Get inside, quickly!", "Spirits, not here!", "Someone call the guards!", "Mind the children!"],
		&"cheer": ["Again! Do it again!", "Did you see that?", "Whoa!", "Show us another one!"],
		&"guard_combat": ["Stay back! Let them through!", "Clear the street!", "To me! Trouble ahead!"],
		&"escort_wait": ["Wait for me!", "Not so fast!", "I can't keep up!"],
		&"wary_bending": ["Careful with that.", "Not near the stalls, please.", "Hmph. Show-off."],
	},
	&"water": {
		&"greet": ["Moon watch over you.", "Cold morning, warm heart.", "Good tides, friend.", "The ice sings today."],
		&"greet_own": ["Good to see a bender in the canals.", "Flow well, sister of the tide.", "Master Siku's student? Work hard."],
		&"greet_wary": ["A long way from home, stranger.", "Keep your fire to yourself here.", "The guards are watching you."],
		&"night": ["The moon is bright tonight.", "Shouldn't you be by a fire?", "Quiet, the little ones are asleep."],
		&"merchant_fish": ["Fresh cod! Pulled from the bay this morning!", "Sea prunes, stewed the way your grandmother made them!", "Smoked char for the road!"],
		&"merchant_pottery": ["Bowls glazed like the northern lights!", "Sturdy pots, won't crack in the frost!"],
		&"merchant_furs": ["Seal pelts! Warmest in the north!", "Mittens, boots, parkas, come and see!"],
		&"merchant_trinkets": ["Carved whale tooth, one of a kind!", "Moon pendants for your sweetheart!"],
		&"merchant": ["Come, have a look!", "Good prices for good people!"],
		&"cheer": ["The tide answers you!", "Like Tui and La themselves!"],
	},
	&"earth": {
		&"greet": ["Good day to you.", "Stand firm, traveller.", "Mind the cart!", "Fine weather for the harvest."],
		&"greet_own": ["An earthbender! The wall feels safer already.", "Rooted and ready, eh?"],
		&"greet_wary": ["Fire Nation, here? Keep walking.", "Papers in order, are they?", "We don't want trouble."],
		&"night": ["The lanterns are lit. Home with you.", "Late for a stroll.", "Mind the Dai Li after dark."],
		&"merchant_fish": ["Carp from the lake, still flapping!", "River fish, cheap!"],
		&"merchant_pottery": ["Teapots! Every home needs one!", "Glazed bowls, a set for a song!"],
		&"merchant_furs": ["Wool and silk from the outer ring!"],
		&"merchant_trinkets": ["Jade from the quarries, real jade!", "Pai Sho sets, tiles, boards!"],
		&"merchant": ["Egg custard tarts, warm from the oven!", "Ginseng, good for the breath!", "Turnips and greens, picked at dawn!"],
		&"cheer": ["Like a true master!", "The stone obeys you!"],
	},
	&"fire": {
		&"greet": ["Glory to the Fire Nation.", "Hot day, isn't it?", "Mind your step, citizen.", "The sun is generous today."],
		&"greet_own": ["Your fire burns bright, firebender.", "Breathe deep, strike true."],
		&"greet_wary": ["What is a foreigner doing in the capital?", "I'd keep my head down if I were you.", "The guards have questions for your kind."],
		&"night": ["Off the streets, curfew comes soon.", "The braziers burn low.", "Only patrols walk this late."],
		&"merchant_fish": ["Ocean fish from Crimson Harbor!", "Salted, smoked, fresh, take your pick!"],
		&"merchant_pottery": ["Lacquered bowls, red as the sun!", "Teaware fit for a noble house!"],
		&"merchant_furs": ["Silk! Finest silk in the archipelago!"],
		&"merchant_trinkets": ["Flame charms for courage!", "Dragon pendants, very lucky!"],
		&"merchant": ["Fire flakes! Get your fire flakes!", "Komodo jerky, chewy and good!"],
		&"cheer": ["Now that is firebending!", "Hotter! Hotter!"],
	},
	&"air": {
		&"greet": ["Peace be with you.", "The wind is kind today.", "Breathe, and be light.", "Welcome, friend of the sky."],
		&"greet_own": ["Your breath is steady, little brother.", "The bison like you, I can tell."],
		&"greet_wary": ["All are welcome here. Even you.", "Leave your anger at the gate, friend."],
		&"night": ["The stars are close tonight.", "The monks are at evening meditation.", "Sleep well, traveller."],
		&"merchant": ["Fruit pies, fresh from the kitchens!", "Prayer beads, made by the novices!", "Wind chimes, they sing for you!"],
		&"cheer": ["Ha! The wind loves you!", "Airball! Play airball with us!"],
	},
}

## Small talk with unnamed townsfolk: per nation, then role (or "any").
const SMALL_TALK := {
	&"water": {
		&"any": [
			"The Chief says the Fire Navy has been seen off the eastern ice. My cousin saw their smoke.",
			"Have you visited the Spirit Oasis? It is warm there, even in the long night. Nobody knows why.",
			"My father fished these canals before the walls were raised this high. He says the city grows like ice.",
			"When the moon is full, the benders train all night. You can hear the water singing from the upper tier.",
			"Master Siku is strict, but his students never fall through the ice.",
		],
		&"guard": [
			"Stay on the walkways. The canals freeze thin at the edges.",
			"Fire Navy ships have been sighted. Keep your eyes on the horizon.",
			"The sea gate opens at dawn. Not before.",
		],
		&"child": ["Do you want to see me slide all the way to the harbour? Watch!", "I can bend! Well. A little. A puddle.", "My brother says polar bear dogs can smell a lie."],
		&"fisher": ["Cod are running fat this season.", "Keep away from my nets and we'll be friends."],
	},
	&"earth": {
		&"any": [
			"Behind these walls nothing can touch us. That's what they say, anyway.",
			"The tea in the Lower Ring is better than anything up top. Don't tell the nobles.",
			"Omashu's mail chutes are faster than any messenger hawk. My nephew rides them for fun. Madness.",
			"The farmers in the Agrarian Zone feed the whole city, and they get the dust for thanks.",
			"An earthbender listens before striking. My grandmother taught me that. She also threw rocks at me.",
		],
		&"guard": ["Move along, citizen.", "Keep your bending inside the training halls.", "The gates close at dusk."],
		&"child": ["Bet you can't jump over that wall!", "When I grow up I'm going to ride a badgermole."],
		&"merchant": ["Everything is fair priced. Mostly fair.", "You look like someone who appreciates quality."],
	},
	&"fire": {
		&"any": [
			"The Fire Lord's palace catches the sunrise first. It is a sight worth waking early for.",
			"The komodo rhinos are restless in the heat. Keep clear of the stables.",
			"They say the dragons once flew over this city every morning. Imagine it.",
			"Crimson Harbor never sleeps. Ships come in, ships go out, smoke and iron.",
			"Firebending is breath. Too many forget that and only remember the anger.",
		],
		&"guard": ["Papers are checked at the Dragon's Throat.", "State your business, citizen.", "No firebending in the market. Unless you want to pay for the awnings."],
		&"child": ["I can make a spark! Look! ...It was there a moment ago.", "Have you seen the turtle-ducks in the palace pond?"],
		&"merchant": ["Silk and spice from every island.", "Haggling is an art. I am a master."],
	},
	&"air": {
		&"any": [
			"The bison returned from the eastern clouds this morning. They brought rain.",
			"There are four temples, one for each wind. This one is my home.",
			"We do not lock our doors. There is nothing here worth stealing, except the pies.",
			"Meditation is simple. Sit. Breathe. Let your thoughts float away like clouds. Simple, but not easy.",
			"The gliders' leap is a rite for every novice. Some leap more than once. Some land in the hay.",
		],
		&"child": ["Airball! You play? I'll win, though.", "Lemurs stole my fruit pie again."],
		&"monk": ["Detachment is not coldness. It is freedom to love without fear.", "Walk lightly, and the mountain will carry you."],
	},
}

extends RefCounted
## Travellers' characters at the ports between the nations (route advice, rumours that point at
## quests elsewhere). Original writing.

const NPCS := {
	&"tr_jian": {
		"name": "Harbourmaster Jian", "title": "Full Moon Bay Docks", "nation": &"earth", "role": &"worker",
		"look": {"preset": &"villager_earth", "body": "male", "age": "adult", "seed": 1},
		"place": {"anchor": {"settlement": &"ek_villages", "kind": &"quest_giver", "tags": ["full_moon_bay", "harbor_master"]}},
		"barks": ["Ferries to the Fire Nation and the Foothills!", "Tickets? No tickets. Just get on."],
		"talk": [{"tree": &"jian_routes"}],
	},
	&"tr_ryu": {
		"name": "Dockmaster Ryu", "title": "Crimson Harbor Quay", "nation": &"fire", "role": &"worker",
		"look": {"preset": &"villager_fire", "body": "male", "age": "elder", "seed": 2},
		"place": {"anchor": {"settlement": &"fire_harbor", "kind": &"quest_giver", "tags": ["harbor_master"]}},
		"barks": ["Mind the coal carts!", "The ferry to Full Moon Bay leaves when it leaves."],
		"talk": [{"tree": &"ryu_routes"}],
	},
}

const TREES := {
	&"jian_routes": {"nodes": {
		"start": {"text": "Full Moon Bay, crossroads of the south! Where are you headed?", "choices": [
			{"text": "Where do the ferries go?", "next": "routes"},
			{"text": "Any news from the road?", "next": "news"},
			{"text": "Nowhere yet.", "end": true},
		]},
		"routes": {"lines": [
			"East across the bay to Crimson Harbor, if you have business with the Fire Nation. South to Foothills Landing, for the Air Temple's mountain.",
			"And the north road runs to Northreach, where the ferry crosses to the Water Tribe. The ferry master's post is at the end of the quay.",
		], "end": true},
		"news": {"text": ["They say an admiral in Crimson Harbor is looking for an honest courier. Strange times.", "A tea master in Ba Sing Se has been asking about the Air Temple. Forty-year-old debts, he says."], "end": true},
	}},
	&"ryu_routes": {"nodes": {
		"start": {"text": "Crimson Harbor. Iron, coal and ferries. What do you want?", "choices": [
			{"text": "Where does the ferry go?", "next": "routes"},
			{"text": "Who runs this harbour?", "next": "who"},
			{"text": "Nothing.", "end": true},
		]},
		"routes": {"text": "West to Sunflare Isle, for the resort. North-east to Full Moon Bay in the Earth Kingdom. Pick one and stop blocking the carts.", "end": true},
		"who": {"text": "Admiral Kuro, up in the Admiralty. Honest man, for an admiral. He has been writing letters lately. Lots of letters.", "end": true},
	}},
}

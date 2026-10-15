extends TestCase
## Foundation tests: elements, health, combat helpers, game state, saves, settings.


func test_element_ids_roundtrip() -> void:
	for e in ElementDefs.ALL:
		expect_eq(ElementDefs.from_id(ElementDefs.id_of(e)), e, "roundtrip")
	expect_eq(ElementDefs.from_id(&"nope"), ElementDefs.Element.NONE)


func test_health_damage_and_death() -> void:
	var h := HealthComponent.new()
	add_child(h)
	h.max_health = 50.0
	h.revive()
	var hit := HitInfo.make(20.0, null, ElementDefs.Element.FIRE, HitInfo.Reaction.FLINCH, Vector3.FORWARD)
	h.apply_damage(20.0, hit)
	expect_near(h.health, 30.0)
	expect(not h.is_dead())
	h.apply_damage(100.0, hit)
	expect(h.is_dead(), "should be dead")
	h.revive(0.5)
	expect_near(h.health, 25.0)


func test_poise_breaks() -> void:
	var h := HealthComponent.new()
	add_child(h)
	h.max_poise = 20.0
	h.poise = 20.0
	var hit := HitInfo.new()
	hit.poise_damage = 12.0
	expect(not h.apply_damage(1.0, hit))
	expect(h.apply_damage(1.0, hit), "second hit breaks poise")


func test_game_state_roundtrip() -> void:
	GameState.new_game(ElementDefs.Element.EARTH)
	GameState.unlock_ability(&"earth_punch")
	GameState.add_item(&"herb", 3)
	GameState.player_position = Vector3(10, 20, 30)
	GameState.quests["q1"] = {"state": "active", "objectives": {"a": 2}, "stage": 1}
	var d := GameState.to_dict()
	var json := JSON.stringify(d)
	GameState.reset()
	expect(GameState.from_dict(JSON.parse_string(json)), "from_dict ok")
	expect_eq(GameState.element, ElementDefs.Element.EARTH)
	expect(GameState.is_unlocked(&"earth_punch"))
	expect_eq(GameState.equipped_abilities[0], &"earth_punch")
	expect_eq(GameState.item_count(&"herb"), 3)
	expect(GameState.player_position.is_equal_approx(Vector3(10, 20, 30)))
	expect_eq(int(GameState.quests["q1"]["objectives"]["a"]), 2)
	expect_eq(GameState.companion["type"], "badgermole")


func test_game_state_rejects_invalid() -> void:
	expect(not GameState.from_dict({"element": 99}), "invalid element rejected")


func test_xp_levels() -> void:
	GameState.new_game(ElementDefs.Element.AIR)
	GameState.add_xp(GameState.xp_for_level(1) + 5)
	expect_eq(GameState.level, 2)
	expect_eq(GameState.skill_points, 1)


func test_settings_presets_and_snapshot() -> void:
	var snap := Settings.snapshot()
	Settings.apply_preset("low")
	expect_eq(Settings.get_value("graphics", "preset"), "low")
	expect_eq(int(Settings.get_value("graphics", "shadows")), 1)
	Settings.set_value("graphics", "shadows", 4)
	expect_eq(Settings.get_value("graphics", "preset"), "custom")
	Settings.restore_snapshot(snap)
	expect_eq(Settings.get_value("graphics", "preset"), snap["graphics"]["preset"])


func test_input_actions_registered() -> void:
	for a: StringName in InputDefaults.ACTIONS:
		expect(InputMap.has_action(a), "action %s registered" % a)
	expect(InputMap.action_get_events(&"jump").size() >= 1)


func test_rebinding() -> void:
	var snap := Settings.snapshot()
	Settings.set_binding(&"jump", "kbm", {"type": "key", "code": KEY_J})
	Settings.apply_controls()
	var found := false
	for ev in InputMap.action_get_events(&"jump"):
		if ev is InputEventKey and (ev as InputEventKey).physical_keycode == KEY_J:
			found = true
	expect(found, "jump rebound to J")
	Settings.restore_snapshot(snap)
	Settings.apply_controls()


func test_save_and_load_slot() -> void:
	GameState.new_game(ElementDefs.Element.FIRE)
	GameState.level = 4
	GameState.player_position = Vector3(1, 2, 3)
	expect(SaveSystem.save_game(3), "save ok")
	GameState.reset()
	expect(SaveSystem.load_game(3), "load ok")
	expect_eq(GameState.element, ElementDefs.Element.FIRE)
	expect_eq(GameState.level, 4)
	var info := SaveSystem.get_save_info(3)
	expect_eq(int(info.get("element", -1)), ElementDefs.Element.FIRE)
	SaveSystem.delete_save(3)
	expect(not SaveSystem.has_save(3))


func test_corrupt_save_is_rejected() -> void:
	var f := FileAccess.open(SaveSystem.slot_path(2), FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	GameState.new_game(ElementDefs.Element.WATER)
	expect(not SaveSystem.load_game(2), "corrupt save rejected")
	expect_eq(GameState.element, ElementDefs.Element.WATER, "state untouched")
	SaveSystem.delete_save(2)


class Dummy:
	extends Node3D
	var team := Combat.Team.ENEMY
	var hits := 0
	func _init() -> void:
		add_to_group(Combat.GROUP_DAMAGEABLE)
	func receive_hit(_h: HitInfo) -> int:
		hits += 1
		return Combat.Result.HIT


func test_combat_team_filter() -> void:
	var d := Dummy.new()
	add_child(d)
	var hit := HitInfo.new()
	hit.team = Combat.Team.ENEMY
	expect_eq(Combat.deal(d, hit), Combat.Result.IGNORED, "same team ignored")
	hit.team = Combat.Team.PLAYER
	expect_eq(Combat.deal(d, hit), Combat.Result.HIT, "enemy team hit")
	var child := Node3D.new()
	d.add_child(child)
	expect_eq(Combat.find_damageable(child), d, "resolves owner")

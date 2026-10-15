extends Node
## Global signal bus (autoload "Events").
##
## Systems emit and listen here so they stay decoupled. Add new signals at the
## bottom of the matching section; never repurpose an existing signal's arguments.

# --- Game flow ---------------------------------------------------------------
signal element_selected(element: int)
signal game_started(element: int, is_new_game: bool)
signal game_loaded(slot: int)
signal game_saved(slot: int)
signal pause_changed(paused: bool)
signal returning_to_menu

# --- Player ------------------------------------------------------------------
signal player_spawned(player: Node3D)
signal player_damaged(amount: float, hit: HitInfo)
signal player_healed(amount: float)
signal player_died
signal player_respawned
signal player_level_up(level: int)
signal xp_gained(amount: int, reason: String)
signal player_resource_changed(resource: StringName, value: float, max_value: float)

# --- Bending / combat --------------------------------------------------------
signal ability_used(ability_id: StringName)
signal ability_failed(ability_id: StringName, reason: StringName)
signal ability_unlocked(ability_id: StringName)
signal abilities_equipped_changed
signal hit_landed(hit: HitInfo, target: Node, result: int)
signal enemy_alerted(enemy: Node3D)
signal enemy_killed(enemy: Node3D, killer: Node)
signal target_locked(target: Node3D)
signal target_unlocked
## A combat encounter started/ended near the player (used for music and HUD).
signal combat_state_changed(in_combat: bool)

# --- Camera / feel -----------------------------------------------------------
signal camera_shake(strength: float, duration: float)
signal camera_impulse(direction: Vector3, strength: float)
signal hitstop(duration: float)

# --- World -------------------------------------------------------------------
## Emitted by any walking actor (player, NPCs, companions) when a foot plants.
## `size` is the approximate foot/paw length in meters, `weight` is 0..1+.
signal footstep(actor: Node3D, position: Vector3, yaw: float, size: float, weight: float, surface: StringName)
## Landing after a jump/fall. `impact` is the vertical speed at touchdown (m/s).
signal landed(actor: Node3D, position: Vector3, impact: float, surface: StringName)
signal region_entered(region_id: StringName)
signal poi_discovered(poi_id: StringName)
signal time_of_day_changed(hour: float)
signal weather_changed(weather: StringName)
signal world_ready

# --- Quests / NPC / UI -------------------------------------------------------
signal quest_started(quest_id: StringName)
signal quest_updated(quest_id: StringName)
signal objective_completed(quest_id: StringName, objective_id: StringName)
signal quest_completed(quest_id: StringName)
signal item_collected(item_id: StringName, count: int)
signal dialogue_started(npc: Node)
signal dialogue_ended(npc: Node)
signal interaction_prompt(text: String, visible: bool)
## HUD toast notification. kind: &"info", &"quest", &"warning", &"discovery", &"unlock".
signal notify(text: String, kind: StringName)

# --- Companion ---------------------------------------------------------------
signal companion_spawned(companion: Node3D)
signal companion_command(command: StringName)
signal mounted(mount: Node3D)
signal dismounted(mount: Node3D)

# --- Settings ----------------------------------------------------------------
signal settings_applied
signal graphics_settings_changed
signal audio_settings_changed
signal controls_changed

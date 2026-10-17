# UI module (`src/ui/`, `scenes/ui/`, `assets/ui/`)

Every menu and in-game overlay of *Avatar: The Four Nations*: main menu with a live 3D
panorama, settings (incl. full rebinding), element selection with live bender previews,
pause menu, HUD, region title cards, dialogue box and loading screen. Everything is built
in code on top of one shared look (`UiTheme`): lacquer ink panels, parchment text, gold
hairlines, cinnabar brush strokes, Cinzel / Marcellus / Ma Shan Zheng.

The UI is authored at **1920×1080** and scales through the project's `canvas_items`
stretch (`aspect = expand`) from 1280×720 to 4K. 3D previews render their SubViewports at
the final on-screen resolution (capped), so they stay crisp at 4K.

```
src/ui/
  theme/      UiTheme (palette, fonts, Theme), UiFrameStyle (StyleBox), UiFx (sounds, tweens),
              UiInput (active device + binding labels)
  widgets/    MenuOptionButton, BrushStroke, UiChoice, UiSlider, UiToggle, PromptGlyph,
              InputHintBar, UiOverlay, ConfirmDialog, InkTransition
  shaders/    brush_stroke, text_gradient, dry_brush_text, backdrop_blur, hud_bar, hud_vignette,
              panorama_* (terrain, sea, mist), god_rays, soft_puff, petal, flame_particle,
              ribbon, water_stream, stage_ground, silhouette, aurora
  menu/       MainMenu, SaveChooser, panorama/ (MenuPanorama, PanoramaRange, PanoramaLandmarks)
  settings/   SettingsMenu, SettingsSchema, SettingRow, KeyBindList, RebindPrompt, RebindLogic
  select/     ElementSelect, ElementCard, ElementPreview, ElementBackdrop, BackdropPainter,
              fx/ (PreviewFx + Air/Earth/Fire/Water, PreviewRibbon)
  pause/      PauseMenu
  hud/        Hud + HudVitals, HudBar, HudAbilityBar, HudAbilitySlot, HudCompass, HudLockOn,
              HudToasts, HudQuestTracker, HudCompanion, HudDamageNumbers
              dev/ HudMockPlayer, HudPreviewStage (tests / playtests only)
  common/     TitleCard, DialogueBox, LoadingOverlay
scenes/ui/    main_menu, element_select, settings_menu, pause_menu, hud, title_card,
              dialogue_box, loading_overlay (.tscn wrappers: root node + script)
assets/ui/    emblem_{air,earth,fire,water}.svg, icon_*.svg, ability_*.svg, ui_*.svg
              authoring/ make_emblems.py, make_icons.py, svgkit.py (regenerates the SVGs)
```

## Scenes

| Scene | Root | Use |
| --- | --- | --- |
| `scenes/ui/main_menu.tscn` | `Node` (`MainMenu`) | `Router.MAIN_MENU`; boot routes here |
| `scenes/ui/element_select.tscn` | `Node` (`ElementSelect`) | `Router.ELEMENT_SELECT`; reads `Router.params.tutorial` |
| `scenes/ui/settings_menu.tscn` | `Control` (`SettingsMenu`) | overlay; instanced by the main and pause menus |
| `scenes/ui/pause_menu.tscn` | `CanvasLayer` 90 (`PauseMenu`) | add one to the world / tutorial scene |
| `scenes/ui/hud.tscn` | `CanvasLayer` 10 (`Hud`) | add one to the world / tutorial scene, then `bind_player()` |
| `scenes/ui/title_card.tscn` | `Control` (`TitleCard`) | standalone banner for cinematics (the HUD has its own) |
| `scenes/ui/dialogue_box.tscn` | `Control` (`DialogueBox`) | NPC dialogue presenter |
| `scenes/ui/loading_overlay.tscn` | `CanvasLayer` 125 (`LoadingOverlay`) | or `LoadingOverlay.open(tree, text)` |

## Shared look — `UiTheme`

```gdscript
root.theme = UiTheme.get_theme()            # once per UI root (built in code, cached)
label.theme_type_variation = &"HeadingLabel"
UiTheme.title_font(700, 6)                  # Cinzel (variable wght 400..900) + tracking, cached
UiTheme.body_font()                         # Marcellus
UiTheme.brush_font()                        # Ma Shan Zheng (CJK brush); brush_font(true) = Zhi Mang Xing
UiTheme.emblem(ElementDefs.Element.FIRE)    # white SVG emblem, tint with modulate
UiTheme.icon("icon_quest")                  # assets/ui/<name>.svg
UiTheme.element_light(e)                    # element colour lifted for text on dark panels
UiTheme.apply_safe_area(control)            # notch-safe insets on phones/tablets
UiTheme.touch_height(66)                    # >= 88 px when touch controls are on
```

Palette constants: `INK #1b1512`, `PARCHMENT #efe3c8`, `GOLD #e7b552`, `GOLD_HI`, `SEAL`
(cinnabar), `DANGER`, `SUCCESS`, `VEIL` (HUD lacquer). Type scale at 1080p: hero 168,
H1 64, H2 44, H3 34, body 26, small 22, tiny 19.

Type variations: `TitleLabel`, `HeadingLabel`, `SubheadingLabel`, `MutedLabel`, `SmallLabel`,
`BrushLabel`, `GhostButton`, `PrimaryButton`, `DangerButton`, `InkPanel`, `CardPanel`,
`ToastPanel`, `RowPanel`. `UiFrameStyle` is a custom `StyleBox` (fill, paper grain, top sheen,
gold border, ruyi cloud corners, L-shaped focus brackets, tab underline, toast accent bar).

**Texture lifetime rule.** `CanvasItem.draw_texture*()` only stores the texture RID; a
texture that is loaded inside `_draw()` and not referenced anywhere is freed and renders as
a white square. Always get UI textures through `UiTheme.texture(path)` / `icon()` /
`emblem()`, which keep them alive.

### Interaction model
* `UiFx.wire(control, opts)` — hover grabs focus (mouse and keyboard/controller share one
  focus), focus plays `ui_hover`, press plays `ui_click` (or `opts.press_sound`).
  `UiFx.focus_silently(c)` focuses without the tick (menus opening). `UiFx.history` records
  requested sounds (tests).
* Sounds used: `ui_hover`, `ui_click`, `ui_confirm`, `ui_back`, `ui_open`, `ui_close`,
  `ui_error`, `ui_select_element`, `ui_notify`, `ui_quest`, `ui_discovery`, `ui_levelup`
  (all through `Audio.play_ui` → bus `UI`).
* Focus is always visible: menu options paint a brush stroke and slide, rows light up with a
  gold bar, other controls get gold corner brackets (`UiFrameStyle.make_focus`).
* Navigation: arrows / d-pad / left stick (`ui_*`), Enter / Space / A accept, Esc / B back,
  Q/E or LB/RB switch settings tabs, Esc / Start toggles pause.
* `UiInput.ensure(tree)` adds a tiny self-registering node that tracks the active device
  (`UiInput.device` = `&"kbm"`, `&"pad"`, `&"touch"`; signal `device_changed`).
  `PromptGlyph` and `InputHintBar` draw keycaps, mouse buttons or controller glyphs
  (coloured face buttons, shoulders, triggers, d-pad arm, sticks with direction) for the
  current device and re-draw on `Events.controls_changed`. Labels come from the live
  `InputMap` (`UiInput.action_label(action, device)`), the same entries
  `InputDefaults.prompt_for` reads.
* Godot 4.7's built-in `ui_accept` / `ui_cancel` have no controller buttons (only the
  d-pad/stick `ui_up/down/left/right` do), so `UiInput.ensure()` calls
  `UiInput.install_pad_menu_buttons()`, which adds A to `ui_accept` and B to `ui_cancel`
  at runtime when no pad button is mapped. These `ui_*` actions are not rebindable and
  are never written to settings.

## Main menu — `MainMenu`

* Exactly four options: `01 — ENTER THE WORLD`, `02 — TUTORIAL`, `03 — SETTINGS`, `04 — EXIT GAME`.
* ENTER THE WORLD: with `SaveSystem.has_any_save()` a `SaveChooser` opens (latest journey's
  emblem, level, region, play time, save date) offering CONTINUE
  (`SaveSystem.load_game(SaveSystem.latest_slot())` → `Router.goto(Router.WORLD, {"new_game": false})`)
  and NEW JOURNEY (asks to confirm, then element select). Without a save → element select.
  The option's caption shows "Continue as Firebender · Level 5".
* TUTORIAL → `Router.goto(Router.ELEMENT_SELECT, {"tutorial": true})`; SETTINGS → overlay;
  EXIT → fade, `get_tree().quit()`. Plays `Audio.play_music(&"music_menu")`.
* `route_override: Callable(path, params)` and `quit_override: Callable()` replace
  `Router.goto` / `quit` (tests).

### Panorama — `MenuPanorama` (Node3D, no world data needed)
Golden-hour sky using the world sky shader (animated clouds), five `PanoramaRange`
heightfield ranges with art-directed peaks (ridged noise, crest profile, toon light, snow
line, warm rim light, per-layer haze + exponential/height fog for atmospheric perspective),
pine forests (MultiMesh), a PBR sea (scrolling normal layers, distance calm, sun glitter),
drifting mist banks, screen-space god rays (8 taps on a blurred mip, sun position from the
camera), petals on turbulent wind (GPU particles), gull and crow flocks (`BirdFlock`), and
a slow camera drift. Nation hints: Air Temple towers on the tallest peak, a Ba Sing Se wall
with gate towers along a ridge, Water Tribe ice spires on a floe with a periodic sun
glint, and a Fire Nation volcano with a glowing crater and smoke plume. `set_time(t)` jumps
the drift clock. Settings: environment toggles via `Settings.configure_environment`,
shadows via `configure_sun`, particle counts from `effects_scale()`, forest density from
`vegetation_density()`, rays off at detail 0.

## Settings overlay — `SettingsMenu`

```gdscript
var s: SettingsMenu = preload("res://scenes/ui/settings_menu.tscn").instantiate()
add_child(s); s.open()                    # snapshot taken on open
s.closed.connect(...); s.applied.connect(...)
s.show_tab("controls")
s.set_option("audio", "music", 0.4, "audio")   # what a row does (tests, scripted tours)
```

* Tabs: Display (mode, resolution filtered to the screen, vsync, FPS limit, render scale,
  upscaler, FOV) · Graphics (preset Low/Medium/High/Ultra/Custom (+Mobile on phones), AA,
  shadows, SSAO, SSIL, glow, volumetric fog, SDFGI, view distance, vegetation, effects,
  detail) · Audio (master, music, effects, ambience, interface, voice) · Controls (mouse /
  controller sensitivity, invert Y, camera distance, camera shake, toggle sprint, all touch
  options, **key bindings**) · Gameplay (difficulty, hints, damage numbers, subtitles).
* Rows are data (`SettingsSchema.rows(tab)`): `{kind: choice|slider|toggle|header|bindings,
  section, key, label, help, apply: display|graphics|audio|controls|gameplay|preset,
  feature, items | min/max/step/format}`.
* **Live apply**: every edit calls `Settings.set_value` and the matching
  `apply_display/apply_graphics/apply_audio/apply_controls` immediately (volume sliders play
  a preview tick on their bus) and emits `Events.settings_applied`. **APPLY** =
  `Settings.apply()` + `Settings.save()` and close; **CANCEL** =
  `Settings.restore_snapshot()` + `apply()` and close; **RESTORE DEFAULTS** resets the
  current tab's sections (still cancellable). Back with unsaved edits asks APPLY / DISCARD /
  KEEP EDITING. `persist = false` skips writing `user://settings.cfg` (tests).
* Changing a single graphics option turns the preset row to Custom; choosing a preset
  refreshes every graphics row.
* Options `Settings.is_feature_supported()` rejects are disabled with a tooltip and an
  explanation in the help panel (e.g. "Not supported by the Compatibility (OpenGL)
  renderer."); unsupported choice values (TAA, SMAA, FSR) are skipped by the selector.
* The help panel on the right always describes the focused option (controllers have no
  tooltips) and shows the active renderer.

### Rebinding — `KeyBindList`, `RebindPrompt`, `RebindLogic`
* Every rebindable action of `InputDefaults.ACTIONS` grouped Movement / Camera / Bending /
  World / Menus, one keyboard & mouse column and one controller column, plus RESET ALL.
* Press-to-bind: activating a cell opens `RebindPrompt`; the next key / mouse button (kbm
  column) or button / trigger / stick direction (pad column) is captured. Esc cancels a
  keyboard capture, Menu (Start) a controller capture, and it times out after 8 s.
* Conflicts with another action on the same device class show "SPACE is already used by
  JUMP" with **SWAP** (the other action receives your previous binding, or loses the
  conflicting one), **BIND ANYWAY** and **CANCEL**.
* `RebindLogic.bind(action, entry, swap)` writes `Settings` and re-applies the InputMap
  (`Settings.apply_controls()`), so bindings work immediately and are kept or reverted
  with APPLY / CANCEL. Other helpers: `grouped_actions()`, `entry_from_event(ev, device)`,
  `find_conflicts(action, entry)`, `current_entry(action, device)`, `reset_all()`.

## Element select — `ElementSelect`

* Title "BEGIN YOUR JOURNEY AS..." (tutorial adds a TRAINING GROUNDS tag) and four cards
  in this order: EARTHBENDER, AIRBENDER, FIREBENDER, WATERBENDER, each with name, the
  ElementDefs tagline verbatim, combat philosophy, home and companion.
* Focus/hover changes the full-screen `ElementBackdrop` (cross-fade), the motif and the
  BEGIN label. Choosing a card (click / Enter / A) focuses **BEGIN AS …**; confirming plays
  `InkTransition` (element-coloured brush wipe, emblem burst, sink to black) then:
  * normal: `GameState.new_game(e)` → `Router.goto(Router.WORLD, {"new_game": true, "element": e})`
  * tutorial (`Router.params.tutorial == true`): `GameState.new_game(e, true)` →
    `Router.goto(Router.TUTORIAL, {"element": e})`
  and emits `Events.element_selected(e)`. Back (Esc / B, or the BACK button) returns to the
  main menu; from BEGIN, Back returns to the cards. `route_override`, `instant` for tests.
* **Live previews** (`ElementPreview`, a TextureRect showing a SubViewport with its own
  World3D and transparent background): the real `HumanoidRig` in the nation's outfit
  (`air_nomad`, `earth_kingdom`, `fire_nation`, `water_tribe`) looping real bending clips
  with event-synced effects, plus the companion `CreatureRig` (sky bison and dragon flying,
  badgermole and polar bear dog on the ground). A collision floor gives the rigs' foot
  probes a ground in the isolated physics space. The focused card renders every frame;
  the others at `idle_fps` (12); hidden previews stop entirely.
* **Effects** (`PreviewFx` subclasses; presentation only — gameplay bending is
  `src/bending`): Air — spiralling wind ribbons, palm gusts, sweep ring; Earth — stomp
  tears a boulder from the ground (debris via `CreatureFx.debris_burst`), lift, hurl, rock
  punches; Fire — flickering fists, fireballs with light and trails, fire arc behind the
  kick; Water — orbiting stream tube that is drawn into the hands and lashed out as whips
  with spray. A subclass implements `sequence()` and reacts in `on_event(clip, event)`.
* **Backdrops** (`ElementBackdrop` + `BackdropPainter`, vector-painted, resolution
  independent): Earth — Ba Sing Se's wall and gate towers before peaks at golden hour,
  falling leaves; Air — temple towers on stone pillars above a sea of clouds, drifting
  clouds and wind streaks; Fire — the palace's flared roofs and a glowing volcano under a
  crimson dusk, rising embers; Water — ice walls, domes and spires under moon, stars and
  an animated aurora, falling snow.
* **Show-intro motif**: a cinnabar brush swash with the brush glyph pair (水善 / 土强 / 火烈 /
  气和, dry-brush shader, ink-reveal on change) around a black silhouette of the bender
  (`ElementPreview` in `silhouette` mode) performing the element's move with the effect in
  colour.

## Pause menu — `PauseMenu`

```gdscript
add_child(preload("res://scenes/ui/pause_menu.tscn").instantiate())   # world / tutorial scene
```
Esc / Start (`pause` action) toggles. Opening sets `get_tree().paused = true`, shows the
mouse, blurs the game and emits `Events.pause_changed(true)`; resuming restores the previous
mouse mode (e.g. captured). Options: RESUME, SAVE GAME (`SaveSystem.save_game()`, disabled
in the tutorial), SETTINGS (overlay), RETURN TO MAIN MENU (saves first unless tutorial →
`Router.goto_main_menu()`), QUIT TO DESKTOP (saves first). The side panel shows element,
level, region, play time and the last save. Overrides: `route_override`, `quit_override`,
`save_override` (tests).

## HUD — `Hud`

```gdscript
var hud: Hud = preload("res://scenes/ui/hud.tscn").instantiate()
add_child(hud)
hud.bind_player(player)
hud.bind_quest_provider(quest_system)      # optional
```

**Player contract** (duck-typed):

| Member | Notes |
| --- | --- |
| `var health: HealthComponent` (or `get_health_component()`) | required; drives the health bar and the low-health vignette |
| `signal resource_changed(resource: StringName, value: float, max_value: float)` | `&"health"`, `&"chi"`, `&"focus"`; `Events.player_resource_changed` works the same |
| `func get_resource(resource) -> Vector2` | optional `(value, max)` for the initial chi / focus |
| `func get_ability_slot_info(i: int) -> Dictionary` | polled every frame for `i` 0..3 (techniques) and 4 (signature): `{id: StringName, name, icon: Texture2D or res path, element, cooldown_ratio: 1 just used → 0 ready, cooldown_left: s, available: bool, cost}`; `{}` / empty id = empty slot |
| `func get_lock_target() -> Node3D` | polled; null when not locked (`Events.target_locked/unlocked` also work). Target name: `get_display_name()`, `display_name` property or meta, else node name; health from a `HealthComponent` child or `health` property |
| `func get_companion() -> Node3D` | optional; health as above, `get_status_text()` for the state line |

**Quest provider**: `get_quest_display(quest_id) -> {"title", "objectives": [{"text", "done", "count", "target"}], "target": Vector3}`;
refreshed on `Events.quest_started/updated/objective_completed` for `GameState.tracked_quest`,
cleared on `quest_completed`. The `target` becomes a compass marker with distance.

**Events consumed**: `notify(text, kind)` → toasts (info, quest, warning, discovery, unlock;
max 4, auto-dismiss, each with icon + sound); `interaction_prompt(text, visible)` →
"[E] Talk to …" above the techniques; `region_entered(id)` → compass region name +
`TitleCard`; `ability_failed(id, reason)` → red flash + shake on that slot (+ `ui_error`);
`ability_used(id)` → pop; `hit_landed(hit, target, result)` → damage numbers (only if
`gameplay.damage_numbers`; heavy hits gold and larger); `player_damaged` → edge flash;
`target_locked/unlocked`; `player_level_up`; `companion_spawned`; `dialogue_started/ended`
(combat widgets fade out).

**Layout** (1080p design): vitals top-left (element medallion with focus ring + level seal,
brushed health bar with damage trail, chi bar), compass top-centre (ticks, cardinals, POI /
quest / companion markers within 900 m, region name), lock-on plate under it + rotating
brackets on the target, toasts top-right, quest tracker right, companion bottom-left,
4 technique slots + round signature slot bottom-centre (icon, key/button badge, clockwise
cooldown sweep with seconds, insufficient-chi marker, ready glint, focus ring on the
signature), interaction prompt above them. `Hud.center_clear_rect()` (30–70 % × 22–74 %)
is kept free of widgets (verified by the HUD playtest); only damage numbers and the
lock-on brackets, which sit on the target, enter it. `set_combat_hud_visible(false)` fades
the combat widgets (cinematics, dialogue).

Components can be used directly: `hud.notify(text, kind)`, `hud.set_interaction_prompt()`,
`hud.set_resource()`, `hud.compass.set_markers([...])`, `hud.quest.show_quest({...})`,
`hud.damage_numbers.spawn(world_pos, amount, heavy, element)`, `hud.title_card.show_title(...)`.

`HudMockPlayer` (`src/ui/hud/dev/`) implements the contract for tests and previews;
`HudPreviewStage` builds a small 3D scene with it.

## Title card, dialogue, loading

```gdscript
# Arrival / discovery banner (ink stroke sweeps in, caption + title reveal, cinnabar seal with the element glyph)
title_card.show_title("The Northern Water Tribe", "Arrival", ElementDefs.Element.WATER)
await title_card.finished          # titles queue; skip() ends the current one
title_card.show_region(&"fire_nation")          # "THE FIRE NATION" · Region Discovered

# Dialogue (typewriter reveal; Enter/A/E or click completes the line, then advances)
dialogue.open()
await dialogue.say("Master Pakku", "Again. Your form is sloppy.", {"element": ElementDefs.Element.WATER})
var i: int = await dialogue.ask("Katara", "Will you help us?", ["Of course.", "Not yet."])   # arrows/d-pad, 1-6, mouse
dialogue.close()

# Loading / tips (above the Router fade)
Router.hold_fade()
var lo := LoadingOverlay.open(get_tree(), "Entering the Northern Water Tribe")
lo.set_progress(0.5)               # omit for an indeterminate ensō spinner
lo.close(); Router.release_fade()
```

## Assets

`assets/ui/*.svg` are single-colour white so they can be tinted. Emblems follow the show's
designs (water: ring with three rising curls over waves; earth: trapezoid, spiral, mirrored
step glyphs at the base; air: three spirals with sweeping tails; fire: flame tongues from a
central spiral). They are generated by `assets/ui/authoring/make_emblems.py` and
`make_icons.py` (tapered "brush" strokes → filled SVG paths; `python3 make_emblems.py
<preview_dir>` also writes PNG previews). Imports use mipmaps; draw them with
`TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` when scaled down.

Fonts (OFL, `assets/fonts`): Cinzel (titles; variable weight), Marcellus (body), Ma Shan Zheng
(CJK brush). None of them contain arrow glyphs: draw arrows (PromptGlyph does) instead of
using "←↑" in text.

## Performance notes
* Main menu: ~5 heightfield meshes (~60k tris), 3 forest MultiMeshes, 2 GPU particle
  systems, 2 bird flocks; panorama builds in ~0.3 s.
* Element select: 4 card previews + 4 silhouettes (8 SubViewports). Only the focused card and
  the visible silhouette render every frame; idle cards at 12 fps; hidden ones not at all.
  Software (lavapipe) rendering runs it at interactive rates.
* HUD: one CanvasLayer, no per-frame allocations in the hot path (pooled damage numbers,
  slots poll a dictionary), compass markers refreshed at 2 Hz.

## Testing
* `tools/test.sh test_ui` — 37 tests: theme/assets, input device tracking, main-menu wiring
  (four options, chooser continue/new journey with a real save, settings, exit), settings
  live apply (viewport scaling/MSAA, environment glow, bus volumes/mute, invert Y), cancel
  restore (incl. bindings), apply, presets/custom, unsupported options, tab switching,
  rebinding (InputMap, conflicts, swap, capture, cancel, timeout), element select (order,
  exact taglines, live previews, glyphs/backdrop per hover, routing in both modes, back),
  pause (pause/unpause, mouse restore, save/return/quit, tutorial never saves, settings
  overlay), HUD (mock player resources, cooldowns, failures, toasts, prompt, lock-on, quest
  tracker, damage-number setting, region/compass maths), title card queue, dialogue
  say/ask, loading overlay, widgets. Tests never write the real settings or saves.
* Playtests (`tools/playtest.sh <name> <out> 1920x1080`):
  `ui_main_menu` (two panorama moments, keyboard/controller navigation, all settings tabs,
  Back), `ui_element_select` (each element focused, ui_left/right navigation, choose +
  confirm with the real ink wipe; `TUTORIAL=1` for tutorial mode), `ui_settings` (binding
  table kbm and controller glyphs, press-to-bind with a real key event, conflict + swap,
  preset, cancel), `ui_hud` (combat HUD over a 3D stage with real rigs, failure flash,
  low-health vignette, title card, dialogue with keyboard choice, loading overlay, pause
  menu via the pause action; `ELEMENT=fire` etc.). Shots wait on state rather than
  wall-clock because software rendering caps game time per frame.

## Wave 4 integration fixes (docs/qa/integration_fixes.md)
* `DialogueBox.open()` kills a still-running close fade (it used to hide a box reopened within
  0.15 s); the NPC runner no longer waits it out.
* HUD signature slot: while the element's signature is not learned it draws the technique's
  icon faint under a padlock with "LV n" (`HudAbilitySlot.set_locked`, from the player's
  optional `get_locked_signature_info()`); pressing R then shows one hint toast ("... is locked
  · learn it in Bending Skills (level n)", at most every 4 s).
* Level-up: `GameState.add_xp` no longer toasts; the progression `LevelUpBanner` (group
  `level_up_banner`) is the presentation in the world, and the HUD shows one combined toast
  only where no banner exists (dev arenas).
* Burn ticks (hits tagged `dot`) only tint the vignette lightly (0.3 instead of a full flash).

## Known limitations
* Panorama landmarks are stylised low-poly silhouettes meant to be read at a distance;
  they are not the gameplay versions of those places.
* Preview effects are menu presentation; gameplay bending VFX belong to `src/bending`.
* Display mode / resolution changes apply immediately without a "keep these settings?"
  revert timer.
* Ability icons: the HUD shows whatever the bending module provides; `ability_*.svg` is a
  small generic set used by the mock and as fallbacks (the element emblem otherwise).

## Wave 4 (flow_qa)

* **`ConfirmDialog` traps keyboard / pad focus on its answers** (`_trap_focus()` in `ask()`):
  left / right cycle the answers, up / down stay, Tab / Shift+Tab stay in the row. Without
  explicit neighbours Godot moved focus to the nearest focusable control in the direction,
  which on a real 960x540 window was a settings toggle BEHIND the dim: right from APPLY on
  "UNSAVED CHANGES" left the dialog, and Enter then flipped a setting the player could not
  see. Answer buttons are named `Choice0..n`. Regression:
  `tests/unit/test_flow_qa.gd::test_confirm_dialog_traps_focus_on_its_answers`, playtest
  `flow_qa_confirms` (rendered: right x3 cycles inside the dialog, DISCARD by Enter; the map's
  FAST TRAVEL answered by Enter).
* **The quest tracker follows the touch layout even mid slide-in** (`HudQuestTracker.settle()`,
  called by `Hud.apply_touch_layout()` and before each new slide). On the phone the first
  quest of a new journey slid in while the arrival still hid the HUD (touch overlay off,
  tracker on the right); the overlay then moved the tracker under the vitals, and the running
  `UiFx.slide_in` tween — which animates `position` back to where it started — carried it back
  to the right, under the technique buttons, until the next dialogue. Two quests in quick
  succession also left it 40 px off (the second slide started from the first one's offset).
  Regression: `tests/unit/test_flow_qa.gd::test_quest_tracker_takes_the_touch_layout_during_its_slide_in`,
  playtest `flow_qa_mobile`.

# The Avatar expansion — design contract

This document is the shared contract for the Avatar expansion. Every module building it must
follow these names, data shapes and rules so the pieces fit together. Where a number is a
starting point, tune it by playtesting, but keep the relationships.

Priority: **P0** Avatar State + Elements Sphere (and the multi-element Avatar it needs) ·
**P1** character customization · **P2** masters & special moves, water like the show,
taming companions, world detail, polish.

## 1. You are the Avatar

* The element chosen at the start is the element you **begin learning** and your **origin**
  (home region, starting companion, default culture/wardrobe). It never restricts you.
* `GameState.element` keeps its saved meaning: *origin / starting element*.
* New state, owned by `AvatarProgress` (class_name, static helpers over GameState,
  `src/avatar/progress/avatar_progress.gd`) — the single source of truth for elements:

| Field / call | Meaning |
| --- | --- |
| `enum ElementState { LOCKED, NOVICE, ADEPT, MASTER }` | not learned · knows the basics · proficient · mastered (trial passed) |
| `AvatarProgress.state(e) -> int` | current state of an element |
| `AvatarProgress.learn(e)` | LOCKED → NOVICE; grants that element's core kit + starter techniques; `Events.element_learned(e)` |
| `AvatarProgress.add_proficiency(e, amount)` / `proficiency(e)` / `rank(e)` | practice with that element (landed hits, lessons, quests); NOVICE → ADEPT happens automatically at the rank threshold |
| `AvatarProgress.master(e)` | ONLY the element's Mastery Trial calls this; ADEPT → MASTER; `Events.element_mastered(e)` |
| `is_learned(e)`, `is_mastered(e)`, `learned_elements()`, `mastered_count()`, `all_mastered()` | queries |
| `Events.elements_sphere_unlocked` | fired once when the 4th element is mastered (then saved) |

* Saved in `GameState` (`active_element`, `elements` = `{"air": {"state": int, "proficiency": float}, ...}`,
  `loadouts` = per-element technique slots). Old saves migrate: origin element → NOVICE (ADEPT if it
  already had ≥4 techniques), the other three LOCKED.
* Mastery is never inferred from level, location or equipment.

## 2. Learning the other three elements

* Each nation has a **Teacher** in its capital who teaches the basics (lesson challenge →
  `AvatarProgress.learn`): Air — Monk Tashi (`at_tashi`, Southern Air Temple); Water — Master
  Siku (`wt_siku`, Northern Water Tribe); Earth — Master Bao Shan (`ek_bao_shan`, Ba Sing Se);
  Fire — Master Jinzo (`fn_jinzo`, Fire Nation capital). The same NPC is the element's
  **Grandmaster** who later offers its Mastery Trial.
* Main quest **"The Avatar's Path"** starts after the opening chain and points to the next teacher in
  the show's cycle Air → Water → Earth → Fire (starting after your origin and wrapping around).
* Mastery Trials (playable, built on the existing quest / BendingChallenge / lesson systems; offered
  when the element is ADEPT):
  * Air — **Trial of the Wind**: movement + evasion gauntlet (wind gates, dodge volleys, aerial route).
  * Water — **Trial of the Tides**: precision + defensive flow (redirect projectiles, parry chains, freeze targets).
  * Earth — **Trial of the Stone**: grounding + impact (hold your stance against pushers, shatter targets, build cover under fire).
  * Fire — **Trial of the Sun**: control + timing (ignite/extinguish braziers in order, precision shots, no misfires).

## 3. Switching elements in combat (stances)

* Actions (rebindable): `element_next`, `element_prev`, `element_wheel` (hold → radial wheel).
  Defaults: mouse wheel down/up, hold **V** for the wheel; controller hold **LB** for the wheel
  (tap LB stays *call companion*), D-pad stays techniques; touch: an element ring button (tap
  cycles, hold opens the wheel). Only learned elements are selectable.
* Switching is fast (≤ 0.25 s stance flourish, cancellable by dodge, buffered during recovery, 0.3 s
  lockout) and changes: rig style (air/earth/fire/water body language), locomotion profile, core kit
  (light/heavy/defense/dodge), the technique bar (per-element loadout of 4 + that element's
  signature) and the HUD emblem. **The rig is built once from the player's appearance; switching never
  rebuilds meshes.** Health/chi/focus are shared by all elements.

## 4. Avatar State (form one)

* Action **`avatar_state`** toggles it (default **T**; controller **L3 + R3 pressed together**, detected in
  code and also bindable to a single button; touch: a glowing Avatar button). Available from the first
  minutes of a new game (the tutorial / first activation explains it).
* Blocked while loading, in cinematics/dialogue, dead, knocked down / getting up, or mounted.
* **Avatar Spirit** (0–100) fuels it: drains while active (~120 s Avatar State, ~100 s Elements Sphere;
  master techniques cost extra), refills when inactive (~45 s), +spirit on landed hits. Deactivate any
  time; at 0 it ends with a 3 s warning. Re-entry lockout 2 s. Gameplay setting
  *Avatar State duration: Standard / Unlimited*. No long cooldowns.
* Activation: the first time a short (≤ 4 s, skippable) cinematic; afterwards a 0.6–0.9 s transformation
  (stance → eyes ignite → tattoos/markings glow → expanding energy wave → control returns) with brief
  i-frames.
* Gameplay: `BendingContext.avatar_level` = 0 normal, 1 Avatar State, 2 Elements Sphere; helpers
  `ctx.avatar_power()`. Starting multipliers (state / sphere): damage ×1.5 / ×2.0, force ×1.4 / ×1.7,
  chi cost ×0.5 / ×0.25, damage taken ×0.7 / ×0.5, extra poise armor, VFX scale ×1.25 / ×1.4. Abilities
  read `avatar_level` to grow and switch to enhanced visual variants.
* Look: `HumanoidRig.set_avatar_glow(amount: float, color := Color(0.78, 0.95, 1.0))` (implemented by the
  customization module) makes the eyes blaze white-blue regardless of eye color, lights equipped tattoos /
  markings (no leak through solid clothing), adds a rim glow; `0` restores the exact customized look. An
  aura FX follows the body.
* Environment: `Events.avatar_pulse(position, radius, strength)` on transformation/major moves; vegetation
  and cloth (wind impulse), water (ripples/splash, rising droplets), fires (flare), loose rocks/props
  (lift/vibrate) react within the radius only.
* Mastering elements is separate from Avatar State power: the state never grants unlearned elements.

## 5. Elements Sphere (form two)

* Automatically replaces the Avatar State once `AvatarProgress.all_mastered()`; same input; the unlock is
  saved and announced as a major milestone (in-world notification + short intro + tutorial tip).
* The sphere is real 3D: orbiting **rock** meshes with mass, flowing **water** ribbons that can flash to ice
  and back, **fire** arcs with glowing cores and embers, and a **wind** vortex shown through moving streaks,
  dust/snow/leaves — moving together in coordinated, balanced patterns that react to movement and bending.
  It follows the body, never blocks the view of enemies, never clips badly, and cleans up fully on exit
  (pooled pieces, no lingering damage). Lower quality reduces secondary particles only.
* While active, the technique bar becomes the master moveset (all real abilities with collision, damage,
  reactions and environment effects, bounded radii, protected quest/settlement objects):

| Slot | id | Technique |
| --- | --- | --- |
| 1 | `avatar_hurricane` | **Hurricane** — aimed growing vortex that pulls, lifts and flings |
| 2 | `avatar_tsunami` | **Tsunami** — advancing wall of water (bigger from real water), knockdown, carry, wetness |
| 3 | `avatar_fire_tornado` | **Fire Tornado** — colossal flame column at the aimed spot, burn zone, launches |
| 4 | `avatar_earthquake` | **Earthquake** — travelling shockwaves, raised ridges/pillars, knockdowns |
| R | `avatar_cataclysm` | **Avatar Cataclysm** — all four elements converge and release |
| wheel | `avatar_elemental_vortex`, `avatar_magma_ring`, `avatar_earth_barrage`, `avatar_frozen_hurricane` | combos chosen from the inner ring of the element wheel |

* Light / heavy / defense / dodge stay the active element's kit at sphere power; element switching works.
* The existing Earth signature `earthquake` is renamed **"Fissure"** (display name only; id unchanged).

## 6. Masters and special moves (the learning mechanic)

Masters live at real places; you travel to them, talk, and pass a short lesson to learn their special
move (`AbilityDef.unlock = {"trainer": npc_id, "level": n, "element_state": NOVICE|ADEPT}` via
`TrainerLessons`). Names are original. Special moves (ids):

| Element | Master (place) | Special move |
| --- | --- | --- |
| Air | Monk Tashi (Southern Air Temple) | Trial of the Wind |
| Air | Sister of the gardens (temple gardens) | `air_ball` — Air Ball |
| Air | Acolyte coach (airball court) | `cyclone_kick` — Cyclone Kick |
| Air | Bison keeper (bison stables) | `vacuum_pull` — Vacuum Pull |
| Air | Wind hermit (high peak POI) | `wind_spiral` — Wind Spiral (air spout) |
| Water | Master Siku (Northern Water Tribe) | `octopus_form` — Octopus Form + Trial of the Tides |
| Water | Ice-fisher master (arctic fishing camp) | `glacier_glide` — Glacier Glide |
| Water | Oasis hermit (Spirit Oasis / frozen lake) | `water_spout` — Water Spout |
| Water | Wandering waterbender (Earth Kingdom lake village) | `ice_lance` — Ice Lance |
| Earth | Master Bao Shan (Ba Sing Se) | `rock_avalanche` — Rock Avalanche + Trial of the Stone |
| Earth | Guard captain (Ba Sing Se Middle Ring) | `stone_gauntlets` — Stone Gauntlets |
| Earth | Omashu's eccentric master (Omashu) | `earth_wave` — Earth Wave |
| Earth | Blind cave master (Earth Kingdom cave POI) | `seismic_sense` — Seismic Sense |
| Fire | Master Jinzo (Fire Nation capital) | `meteor_fist` — Meteor Fist + Trial of the Sun |
| Fire | Sun keeper (volcano-island ruins) | `dragons_breath` — Dragon's Breath |
| Fire | Harbor dojo master (Crimson Harbor) | `fire_daggers` — Fire Daggers |
| Fire | Retired general (Ba Sing Se tea house) | `lightning_redirection` — Lightning Redirection |

## 7. Water like the show

* Waterbending needs water. Real sources: sea, lakes, **rivers**, canals, fountains, pools, snow, ice, rain.
* `WaterReserve` (player): a water skin (capacity ~100 units; bigger skins from merchants/quests). Away
  from sources, water abilities spend skin water; near a source they are free and grow with the source
  (open sea / big river → abundance ×1.35); the skin refills automatically near sources. Empty skin and no
  source → water abilities fail with "No water nearby" plus a hint toward the nearest source. HUD shows
  the skin while Water is the active element.
* The world gets real **rivers** (world data + rendering + `WorldData.get_water_height/find_water_source`).

## 8. Character customization

* New-game flow: Main Menu → ENTER THE WORLD → **"BEGIN YOUR JOURNEY AS THE AVATAR"** ("Choose the element
  with which your journey begins. Your destiny is to master all four.") → **Character Creator** → **Review**
  (character + companion) → Confirm → arrival. The four main-menu options stay exactly as they are.
* `GameState.appearance` (versioned dict): body, age, height, bulk, skin, face {preset + sliders: width,
  length, jaw, cheeks, chin, nose, eye_shape, eye_spacing, brow, mouth, ears}, eye_color, brows, hair
  {style, extras, color}, facial_hair, marks {freckles, scar}, tattoo {style: none|arrows_traditional|
  arrows_full|arrows_partial|markings_*, color, regions}, culture (northern_water, southern_water, swamp,
  ba_sing_se, omashu, kyoshi, desert, mountain, fire_capital, fire_noble, fire_colony, air_nomad), outfit
  {base, upper, outer, lower, belt, boots, gloves, scarf, headwear, necklace, accessories[]}, colors {slot:
  Color}. Stable item ids in `AppearanceDB`; `GameState.wardrobe` (owned ids); `GameState.appearance_presets`
  (≤ 5 named). Cosmetics never change stats.
* `HumanoidRig` builds from an appearance (cache key = appearance hash) and exposes `set_avatar_glow`.
  Wardrobe stations in each capital and new clothes from merchants, quests and exploration.

## 9. Taming companions

* Wild companion species live in their own nation: sky bison herds (Air Temple peaks), dragons (Fire Nation
  volcano island — rare, legendary), polar bear dogs (arctic tundra packs), badgermoles (Earth Kingdom caves
  and mines); plus tameable mounts ostrich horses (Earth Kingdom plains) and komodo rhinos (Fire Nation).
* Taming: approach calmly (no attacks, slow), build the animal's trust, offer its favourite food, pass a
  species-specific bonding challenge (e.g. dragon: a Sun-Warrior-style fire dance; badgermole: earth
  rhythm; bison: a flight chase; polar bear dog: stand calm, then a chase), then name it.
* `GameState.companions` (roster: id, species, name, bond, health) + `GameState.active_companion`; stables in
  every capital to switch; a Companions page in the Journey Book; G calls the active one. The starting
  companion stays.

## 10. Polish bar

Bending must look and feel AAA: strong anticipation and follow-through, readable silhouettes, VFX with a
clear source, shape, motion and impact, hitstop and camera work that sell weight, consistent across the four
elements and in the Avatar forms. Every feature runs on desktop, mobile and web (quality scaling may trim
decoration, never mechanics) and persists through save/load.

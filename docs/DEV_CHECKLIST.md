# Development checklist

Status keys:
- ✅ implemented and verified (automated tests plus rendered playtests with screenshots)
- 🟡 partial, or verified only in simulation
- ⬜ not started

Evidence and details are in `docs/qa/*.md` and `docs/modules/*.md`.

## Stage 1 — Foundation
- ✅ Godot 4.7.2 project, autoloads, physics layers, Jolt physics, per-platform renderers
- ✅ Main menu with exactly four options (Enter the World, Tutorial, Settings, Exit Game)
- ✅ Settings that apply real configuration: presets (incl. mobile), display, AA, shadows,
  post-processing, view distance, vegetation, effects, audio buses, rebinding, touch;
  Apply, Cancel and Restore Defaults; values persist
- ✅ "Begin your journey as…" element selection with live previews and cinematic arrival
- ✅ Third-person controller with element-specific locomotion profiles, plus camera, lock-on
  and soft aim
- ✅ Companion spawning and following

## Stage 2 — Bending combat
- ✅ Ability framework: data-driven definitions; animation-event timing; buffering, cancels,
  cooldowns, chi and focus
- ✅ Full kits for all four elements (11–12 abilities each, incl. signatures and Lightning),
  available on keyboard/mouse, controller and touch
- ✅ Environment reactions:
  - snow prints
  - earth cracks and platforms
  - fire ignition and controlled grass burns
  - water sources, ice floes and dousing
  - air gusts on vegetation, cloth and fires
  - interactive braziers, torches and campfires in settlements
- ✅ 16 enemy archetypes with telegraphs, attack tokens and per-element counterplay; camps,
  outposts and patrols
- ✅ Training grounds tutorial for every element (all lessons completable)

## Stage 3 — Northern Water Tribe vertical slice
- ✅ City: sea wall and gate, tiers, canals, harbour, palace, Spirit Oasis, interiors
- ✅ Snow footprints and trails, weather, aurora, day/night
- ✅ NPC crowds, quest givers, Master Siku's lessons, merchants, opening quest chain
- ✅ Polar bear dog companion and ground mount

## Stage 4 — Remaining nations
- ✅ Ba Sing Se (walls, farmland, rings, palace), Omashu, Earth Kingdom villages
- ✅ Fire Nation capital (caldera), Crimson Harbor, Fire Nation villages
- ✅ Southern Air Temple (terraces, bridges, sanctuary)
- ✅ Sky bison and dragon flight, badgermole burrowing
- ✅ Travel: walkable links, ferries between ports, map fast travel, flight
- ✅ Opening quest chains and side quests per nation; trainers per element; wildlife

## Stage 5 — Polish and optimization
- ✅ Shader warm-up during loading; settlement LOD cross-fades; lock-on framing; occluder fade
- ✅ Mobile budget at all four home spawns (< 250k primitives, < 200 draws, Mobile renderer)
- ✅ Save/load fidelity: atomic writes, backup and recovery, typed round-trips
- ✅ Adversarial bug hunts (gameplay + world/UI): 26 bugs fixed, plus 12 in flow QA, each with
  a regression test
- ✅ CI: tests plus Web, Android APK, Windows and Linux exports on every push
- 🟡 Real-device verification (phones, GPUs): not possible in the build container; touch and
  performance were verified by simulation
- 🟡 Audio: generated and analysed, but not yet tuned by ear
- 🟡 Navigation uses steering, not a navmesh (long detours are possible)
- 🟡 Camera vs tree canopies; brief streaming spikes when flying fast over cities

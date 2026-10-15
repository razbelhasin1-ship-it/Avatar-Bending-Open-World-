# Development checklist

Status keys: ✅ implemented + verified · 🟡 partial · ⬜ not started

## Stage 1 — Foundation
- ✅ Godot 4.7.2 project, autoloads, physics layers, Jolt
- ✅ Core contracts: ElementDefs, HitInfo, Combat, HealthComponent, Layers, InputDefaults
- ✅ Settings (persisted, presets, display/graphics/audio/controls apply, rebinding)
- ✅ GameState + SaveSystem (atomic JSON slots, corrupt-save handling)
- ✅ Router scene transitions; boot dev flags (`--scene`, `--element`)
- ✅ Test runner, playtest runner with screenshots, check script
- ✅ Shared toon + outline shaders
- ⬜ Main menu / settings menu / element selection
- ⬜ Player controller + camera
- ⬜ Opening sequence into each starting region

## Stage 2 — Bending combat vertical slice
- ⬜ Ability framework, per-element abilities, VFX
- ⬜ Element-specific locomotion
- ⬜ Enemy AI and hit reactions
- ⬜ Tutorial

## Stage 3 — Northern Water Tribe vertical slice
- ⬜ World data + terrain, water, sky, weather
- ⬜ Snow footprints and trails
- ⬜ Settlement, NPCs, quests, polar bear dog

## Stage 4 — Remaining nations
- ⬜ Ba Sing Se, Fire Nation Capital, Southern Air Temple, companions, travel

## Stage 5 — Polish and optimization
- ⬜

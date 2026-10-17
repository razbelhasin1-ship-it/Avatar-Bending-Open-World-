# QA wave 4 — end-to-end game flow and the brief's testing checklist (`flow_qa`)

The real game was played like a QA lead: scripted playtests on the REAL scenes (boot, main
menu, element select, world, training grounds, pause / settings, Journey Book, ferries, map,
mounts) for all four elements, with input through the InputMap (key / pad actions, mouse-look
events, simulated touch on the phone run) — never by calling gameplay functions, except where
a step says "harness" (placing the player next to a target, a heal to keep a long run going).
Every log was scanned for `ERROR` / `WARNING` / `SCRIPT ERROR`. Bugs were fixed at their root
(in any module), each with a regression test that fails without the fix.

* Tests: `tests/unit/test_flow_qa.gd` (7 tests).
* Playtests: `tests/playtest/scenarios/flow_qa_menus.gd`, `flow_qa_journey.gd` (`ELEMENT=`),
  `flow_qa_travel.gd` (`ELEMENT=fire|air`), `flow_qa_mobile.gd` (`MOBILE=1 RENDERER=mobile`),
  and the fixed `worldscene_tutorial.gd`.
* Run on the shared CI container: llvmpipe software Vulkan, 4 cores shared with two other
  agents' Godot runs, 960×540 (phone run 1600×720). Load times are software-rendering numbers.

## Bugs found and fixed

| # | Bug (how it showed in play) | Root cause | Fix | Regression |
| --- | --- | --- | --- | --- |
| 1 | Training grounds as an **earthbender**: lessons *Heavy Strike* and *Charged Strike* never complete (the known `worldscene_tutorial ELEMENT=earth` failure) | `TutorialDirector._on_ability_ended` counted a heavy only if the ability `is ChargeAbility`; Earth Boulder is its own lift → hold → throw state machine | Heavies share one release contract (`released`, `tapped`, `charge`); `earth_boulder.gd` exposes it; the director reads it for any heavy-slot ability (`TutorialDirector.heavy_strike_of`) | `test_tutorial_heavy_charge_sprint_lessons_complete_for_every_element`, `test_heavy_strike_report_for_charge_abilities_and_earth_boulder` |
| 2 | Same run, lesson *Sprint* fails for Earth | Harness, not the game: the playtest sprinted right, then left (1.1 s each); Earth (accel 16, decel 28 m/s²) spends each reversal braking — ~1.3 s above run speed of the 1.5 s needed | The playtest runs one straight line like a player told "hold Shift while moving" | same unit test (straight sprint, all four elements) |
| 3 | **Back / Esc on the element select during its fade-in** leaves a dead screen: every later key / pad / tap is ignored, the only way out is quitting | `Router.goto` silently returned while a transition was running, but the screen had already set its own `_busy` flag before routing. The fade blocks the mouse, not keys / pad | `Router.goto`: a request from the NEW scene during its fade-in is queued (latest wins) and runs when the fade ends; requests made before the swap (by the outgoing scene) are still dropped | `test_router_request_during_fade_in_is_not_lost`; playtest `flow_qa_menus` ("Back pressed during the fade-in returns to the main menu") |
| 4 | After a **save → load**, a failed quest's journal page shows no stages; every count comes back as `2.0` | A save is JSON (one number type): integer records came back as floats and `[0.0, 1.0].has(1)` is false (the journal's "stage reached" test) | `GameState.from_dict` turns whole numbers back into ints in the integer records (inventory, stats, practice, quest stage / log / objective progress, companion bond); times stay floats | `test_save_round_trip_keeps_integer_records` |
| 5 | **Tutorial → ENTER THE WORLD silently replaces a saved journey**: main menu → 02 TUTORIAL (with a level-7 journey on disk) → finish → ENTER THE WORLD starts a new journey whose arrival autosave overwrites the old one, no question asked (the main menu's NEW JOURNEY asks) | The completion screen started the new journey unconditionally | With a journey on disk ENTER THE WORLD asks "A NEW JOURNEY" (names the saved journey; KEEP JOURNEY focused, BEGIN ANEW) | `test_tutorial_enter_world_asks_before_replacing_a_saved_journey`; `worldscene_tutorial` checks the question appears exactly when a save exists |
| 6 | Pause → SETTINGS → change an option → Back → "UNSAVED CHANGES": pressing **right on APPLY sends focus behind the dialog** (to a Glow / SSAO toggle under the dim); Enter then flips a setting the player cannot see and the question can no longer be answered with keys / pad | `ConfirmDialog` buttons had no focus neighbours; Godot picks the nearest focusable control in the direction, and on a real 960×540 window that was a settings toggle behind the overlay (headless layout differs, so only the rendered run showed it) | `ConfirmDialog._trap_focus()`: left / right cycle the answers, up / down / Tab stay in the row — every confirmation in the game (settings, Journey Book fast travel / unlearn, rebind reset, the new tutorial question) | `test_confirm_dialog_traps_focus_on_its_answers`; rendered playtest `flow_qa_confirms` (right ×3 cycles inside the dialog, DISCARD by Enter, map FAST TRAVEL answered by Enter) |
| 7 | (tooling) A playtest scenario with a parse error made the runner idle until its 15–30 min timeout | `Playtest._ready` called `new()` on a script that loaded but could not be instantiated | `tests/playtest/playtest.gd` fails at once ("cannot load scenario … (parse error?)") | — |

<!-- RESULTS -->

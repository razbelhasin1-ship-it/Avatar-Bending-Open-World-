# Settlements I — Northern Water Tribe + Southern Air Temple (`settlements_wa`)

The game's first polished vertical-slice city (the **Northern Water Tribe**, with the igloo
villages and fishing camps of the arctic wilds) and the **Southern Air Temple**, built on the
shared settlement framework ([settlements.md](settlements.md): registry, plans, streaming
providers, anchors API, budgets).

| | |
| --- | --- |
| Water Tribe | `src/world/settlements/water_tribe/`: `NwtPlanner` + `NwtDistricts` (layout), `NwtBuilder` (dispatch + extras), recipes `NwtHomes`, `NwtCivic`, `NwtLandmarks`, `NwtPlaces`, `NwtProps`, `NwtStyle`, `SpiritKoi` (Tui and La), `ArcticPlanner` |
| Air Temple | `src/world/settlements/air_temple/`: `SatPlanner` + `SatDistricts` (layout), `SatBuilder`, recipes `SatTowers`, `SatCivic`, `SatPlaces`, `SatProps`, `SatStyle` |
| Settlement ids | `&"northern_water_tribe"`, `&"arctic_villages"`, `&"southern_air_temple"` |
| Tests | `tests/unit/test_settlements_wa.gd` (plans, cell builds, LOD, anchors contract, lookups, determinism, registration / claims / tutorial skip tags, arrival-flight clearance, probe-capsule walk tests over real collision) |
| Playtests | `settlements_wa_tour` (screenshot tour, `VIEWS=a,b`, `PRESET=`), `settlements_wa_walk` (the real player walks bridge, stairs, grand stair, into an interior; `WALKS=`) |
| Dev scene | `godot --path . -- --scene=res://scenes/dev/settlements_wa.tscn` (RMB look, WASD/QE fly, Shift x6, 1–9 views, T +1 h, N night, P stats) |

DOC_BODY

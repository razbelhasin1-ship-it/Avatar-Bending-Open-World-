# Avatar: The Four Nations

An open-world elemental bending action RPG inspired by *Avatar: The Last Airbender*, built
in **Godot 4.7.2**. Choose to begin your journey as an Earthbender, Airbender, Firebender or
Waterbender. Then explore one connected 8 × 8 km world of four nations, master your element,
fight, ride your companion and follow quests through living cities.

> Fan-made, non-commercial project. All art, animation, audio, music and the world are
> generated in code or by the project's own tools; fonts are SIL Open Font License
> (see `assets/fonts/OFL-*.txt`).

## Play it

| Platform | How |
| --- | --- |
| **Android phone/tablet** | GitHub → **Actions** → latest **Build** run → *Artifacts* → `android-debug-apk`. Copy the `.apk` to the phone, open it, and allow "Install unknown apps". |
| **Phone or desktop browser** | Download the `web` artifact and serve it with `tools/export/serve_web.py`. Or enable **Settings → Pages → Source: GitHub Actions** on the repository, and every build then deploys a playable link. |
| **Windows / Linux** | Download the `windows-x86_64` / `linux-x86_64` artifact and run the executable. |
| **From source** | Install [Godot 4.7.2](https://godotengine.org/download), then open `project.godot` and press Play. You can also run `godot --path .` from the repository root. |

Quick-start into a scene while developing: `godot --path . -- --scene=world --element=fire`
(aliases `world`, `tutorial`, `menu`, `select`; add `--mobile` to simulate a phone).

## Controls

| Action | Keyboard + mouse | Controller | Touch |
| --- | --- | --- | --- |
| Move / sprint | WASD / Shift | Left stick / L3 | Floating left stick (push to the edge to sprint) |
| Camera | Mouse | Right stick | Drag on the right half |
| Jump (Air: double jump, hold to glide) | Space | A | Jump button |
| Dodge (element-specific) | C | B | Dodge button |
| Light strike combo | Left mouse | X | Strike |
| Heavy strike (hold to charge) | Right mouse | RT | Heavy (hold) |
| Defend (perfect timing = parry) | Q (hold) | LT | Defend (hold) |
| Techniques 1–4 / Signature | 1–4 / R | D-pad / RB | Technique arc / Signature |
| Lock on / switch target | Tab or middle mouse | R3 | Lock-on (tap / swipe) |
| Interact · call companion · mount | E · G · F | Y · LB | Context button · companion button |
| Map · skills · journal · pause | M · K · J · Esc | View · — · — · Start | Top bar |

All keyboard, mouse and controller bindings can be changed in **Settings → Controls**. On
phones the Controls tab adds touch layout options: button size, opacity and left-handed mode.

## What's in the game

- **Main menu** with a living panorama and the four options: Enter the World, Tutorial,
  Settings, Exit Game. **Settings** cover display, graphics (Low/Medium/High/Ultra/Custom plus
  a mobile preset), audio, controls with key rebinding, touch and gameplay; Apply, Cancel and
  Restore Defaults all work.
- **"Begin your journey as…"**: four element cards, each with a live character and companion
  preview, a nation backdrop and the show's brush calligraphy (土强 · 气和 · 火烈 · 水善),
  followed by a cinematic arrival flight into your home region.
- **Four distinct fighting styles** with their own locomotion, stances, timing and martial-arts
  animation:
  - **Air** (Ba Gua): Air Combo, Air Blast, Air Shield, Air Dash, Air Jump and glide, Air Sweep,
    Air Push, Wind Blade, Air Scooter, Vortex Ward and the Air Tornado signature.
  - **Earth** (Hung Gar): Earth Punch, Earth Boulder, Earth Shield, Earth Slide, Earth Wall,
    Pillar, Stomp, Spikes, Grab, Earth Armor and the Earthquake signature.
  - **Fire** (Northern Shaolin): the fire punch and kick combo, Fire Blast and Blaze Charge,
    Flame Guard, Fire Step, Flame Sweep, Fire Burst, Fire Ring, Jet Step, Fire Whip,
    Lightning and the Inferno signature.
  - **Water** (Tai Chi): Water Whip, Water Blast and Torrent, Water Shield, Flow Slide, Ice
    Shards, Water Surge, Ice Wall, Ice Trap, Water Wave, Water Jet, Healing Waters and the
    Tidal Torrent signature. Water is drawn from real sources: the sea, canals, pools and snow.
- **Environment reactions**:
  - Snow takes real foot- and paw-prints that slowly fill back in.
  - Earth cracks and leaves craters and rock platforms.
  - Fire lights braziers and burns grass under strict spread limits.
  - Water douses fires, freezes floes and soaks targets.
  - Air flattens grass, flaps banners and blows out flames.
- **The world**: an eroded 8 km world with:
  - the Northern Water Tribe (sea wall, canals, palace, Spirit Oasis)
  - Ba Sing Se (colossal walls, farmland, rings, palace)
  - Omashu
  - the Fire Nation capital in its caldera, with Crimson Harbor
  - the Southern Air Temple on its peaks
  - villages, caves, waterfalls, bridges and more than 70 points of interest
  It also has a day/night cycle, regional weather and atmosphere, ferries between ports and
  map fast travel.
- **Companions**:
  - **Polar bear dog** and **badgermole**: ground mounts. The badgermole can also tunnel.
  - **Sky bison** and **dragon**: fly with takeoff, banking and landing.
  - All four follow you, help in fights, react to the world and never get permanently lost.
- **Living world**: NPC crowds with daily routines, merchants and guards; opening quest
  chains and side quests in every nation; trainers who teach advanced techniques; wildlife.
- **Enemies**: 16 archetypes, including brawlers, skirmishers, archers, shield fighters,
  fire/earth/water/air benders, elite captains and beasts. They telegraph their attacks, at
  most two attack you at once, and they react to each element differently. You'll find them
  in camps, outposts and road patrols.
- **Progression**: XP and levels, per-element technique trees, the four technique slots plus
  a signature, and the Journey Book with skills, map, journal, inventory and character pages.
- **Saves**: atomic JSON saves with backups, plus autosave. Continue restores your position,
  loadout, quests, inventory, companion and time of day.
- **Platforms**: desktop (Forward+), phones and tablets (Mobile renderer, touch controls,
  mobile quality budget) and browsers (Compatibility renderer).

## Development

| Task | Command |
| --- | --- |
| Parse-check all scripts | `tools/check.sh` |
| Run all automated tests (headless) | `tools/test.sh [filter]` |
| Scripted playtest with screenshots | `tools/playtest.sh <scenario> [out_dir] [WxH]` (`RENDERER=mobile`, `MOBILE=1` options) |
| Regenerate the world | `python3 tools/worldgen/generate_world.py` |
| Regenerate audio | see `docs/modules/audio.md` |
| Export Web / Android | `tools/export/export_web.sh`, `tools/export/export_android.sh` |

Documentation:
- `docs/ARCHITECTURE.md`: contracts, layout and platform rules
- `docs/GAME_DESIGN.md`: combat and element design
- `docs/modules/`: one page per module
- `docs/qa/`: QA reports with every bug found and fixed
- `docs/DEV_CHECKLIST.md`: feature status

CI (`.github/workflows/build.yml`) runs the tests and exports every platform on each push.

## Known limitations

- Nothing has been played on a real phone or GPU yet. Touch was tested by simulation, and
  frame times were measured with software rendering. Mobile budgets are met on the measured
  views, but with thin margins.
- There is no navmesh: enemies, NPCs and companions steer around obstacles with ray probes,
  and the occasional long detour or teleport is expected.
- Streaming large city cells during fast flight can still cause brief frame spikes.
- Audio was tuned from analysis, not by ear, so it will benefit from a listening pass.
- The camera can enter tree canopies, and large companions can briefly block the view right
  after spawning.

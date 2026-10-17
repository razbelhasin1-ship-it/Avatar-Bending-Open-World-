# Mobile module — touch controls, mobile performance, export builds, CI

Makes *Avatar: The Four Nations* playable on phones and tablets (Android / iOS apps with the
Mobile renderer, and mobile browsers through the Web export with the Compatibility renderer)
without forking any gameplay code: the touch overlay presses the same InputMap actions as a
keyboard or controller, and camera look goes through `Events.look_input`.

```
src/ui/touch/       TouchOverlay (+ TouchStick, TouchButton, TouchActions, TouchLayout, TouchHaptics)
src/ui/touch/icons/ touch_*.svg glyphs + make_touch_icons.py (same brush kit as assets/ui)
src/platform/       PlatformInfo, MobilePlatform (back button / background), PerfProbe, RenderCompat
export_presets.cfg  Web, Android, iOS, Linux, Windows Desktop
tools/export/       export_web.sh, export_android.sh, serve_web.py, web_smoke.mjs
.github/workflows/  build.yml (tests + exports + artifacts + Pages)
tests/unit/test_mobile.gd, tests/playtest/scenarios/mobile_*.gd
```

## Touch controls — `TouchOverlay`

The HUD (`src/ui/hud/hud.gd`) creates one `TouchOverlay` as the top child of its root, so every
scene with a HUD (world, tutorial, combat / enemy arenas) has touch controls. The overlay shows
itself while `Settings.touch_controls_enabled()` (setting `touch.controls` = auto / on / off;
auto = phones, tablets, mobile browsers, touchscreens) and hides while a controller is in use
(`UiInput.device == &"pad"`), during dialogue (`Events.dialogue_started/ended`), while the HUD is
hidden (loading, cinematics) and while the tree is paused.

**Layout** (`TouchLayout.compute(rect, scale, left_handed, top_ids)`, 1920×1080 design px,
expanded to the screen's aspect, inside the display safe area):

| Where | What |
| --- | --- |
| left 46 % below the vitals | floating stick: appears where the thumb lands; push to the ring = run; past the ring = sprint (`touch.auto_sprint`); far past it drags the base along; a faint resting ring hints where it lives |
| anywhere free | drag to look (`Events.look_input`, `touch.camera_sensitivity`); while locked a quick swipe switches target (PlayerTargeting flick) |
| right thumb | Strike (element emblem, 192 px), Heavy (hold = charge), Dodge, Defend (hold), Jump; an arc of the 4 technique slots + the round Signature slot |
| top right | Pause, Lock-on, Call companion (when there is one), Map / Journal (only when such screens exist) |
| bottom centre | contextual Interact button with the prompt text (`Events.interaction_prompt`, key prefix stripped); Dismount while riding |

`touch.button_scale` scales the cluster (it shrinks automatically to fit short screens),
`touch.opacity` sets idle opacity (pressed buttons are opaque), `touch.left_handed` mirrors
stick zone, cluster and contextual button. Every button is ≥ 88 px at scale 1 (tested for
6 aspect ratios × 4 scales × both hands: no overlaps, everything on screen).

**The buttons ARE the HUD ability slots on touch.** Technique / signature buttons embed the
HUD's own `HudAbilitySlot` (icon, clockwise cooldown sweep with seconds, chi marker, fail flash,
ready glint, focus ring), fed from `player.get_ability_slot_info(i)`; the HUD hides its ability
bar and its "[E] …" prompt panel (`Hud.apply_touch_layout(on, left_handed)`), moves toasts
below the top bar, the quest tracker under the vitals, and the companion plate away from a
left-handed cluster. Empty slots are not shown as buttons.

**Modes.** `normal` (all of the above), `mounted` (Ascend = jump, Descend when the mount flies
or burrows, Dismount, stick = steer, past the ring = gallop / boost; no combat buttons),
`cinematic` and `dead` (pause only). Mode changes release everything.

**Lock-on button**: tap = lock (`lock_on`); tap while locked = next target
(`targeting.cycle`), or release when there is no other; hold 0.45 s = release.

### Input routing (multi-touch)

The overlay is a full-rect Control with `MOUSE_FILTER_STOP` while active. Godot's Viewport
routes every touch index to the Control under it (per-index touch focus), so menus, dialogue
and pause layers above the HUD receive their own taps first, and each finger keeps its owner
until it lifts: `touch_down(index, pos)` → button under the finger (nearest centre), else the
stick zone (if the stick is free), else the look pad (one look finger), else ignored;
`touch_move` / `touch_up` go to that owner. Mouse events emulated from touch
(`DEVICE_ID_EMULATION`) are ignored; a real mouse acts as finger 99 (desktop with touch "on").

### `TouchActions` — pressing actions like a device

```gdscript
var acts := TouchActions.new()
acts.press(&"block", &"defend")        # held while any source holds it
acts.set_strength(&"move_forward", &"stick", 0.6)   # analog
acts.release(&"block", &"defend")
acts.tap(&"pause")                     # menu actions -> InputEventAction events
acts.flush()                           # every physics tick
acts.release_all()                     # pause / focus loss / hide / exit
```

* Gameplay actions use `Input.action_press/release` (immediate state, read by PlayerInput's
  per-tick edge detection). A tap shorter than 2 physics ticks is released on a later tick,
  so even a one-frame tap is seen.
* `pause`, `open_map`, `open_journal`, `open_skills`, `ui_cancel` are consumed by
  `_unhandled_input` listeners, so they are sent as `InputEventAction` events.
* Several sources per action (the stick's sprint and nothing else fight over it).

### Haptics — `TouchHaptics`

`Input.vibrate_handheld` (Android, iOS, `navigator.vibrate` in mobile browsers) when
`touch.haptics` is on: player hits 16 ms (heavy 34 ms), parry 30 ms, block 22 ms, damage taken
42–60 ms, button press 7 ms; throttled to one pulse per 70 ms unless a stronger one cuts in.
The Android preset requests the VIBRATE permission.

### Adding a top-bar screen (map, journal …)

Put your screen node in group `&"map_screen"` (or `&"journal_screen"`) while it exists and
handle the `open_map` (`open_journal`) action in `_unhandled_input`; the top bar then shows the
button and taps send that action as an event. No button is shown for screens that do not exist.

## Menus by tap

Godot emulates the mouse from touch (`pointing/emulate_mouse_from_touch`), so buttons, cards,
sliders and toggles work by tap. Fixed for touch (all verified by `mobile_menus` and the web
smoke test):

* **Keyboard / controller glyphs on touch** — `InputHintBar` hides on touch, `PromptGlyph`
  collapses while `UiInput.device == &"touch"` (or shows a tap mark with `tap_on_touch`,
  used by the dialogue's advance prompt); settings' Q/E tab glyphs disappear.
* **Dialogue panel** — the panel stopped mouse input, so a click / tap *on the panel* never
  advanced the line (only taps beside it did); it now advances.
* **Selectors in scroll lists** — `UiChoice` stepped on press, so starting a scroll on a
  selector changed the setting; on touch it now acts on lift and only for a tap
  (≤ 24 px travel), and lets the drag reach the ScrollContainer. `UiToggle` ignores a lift
  that ends a scroll drag.
* **EXIT GAME / QUIT TO DESKTOP** — on Web (and iOS) quitting cannot work: the main menu faded
  out and waited forever (a stuck state). Hidden where `PlatformInfo.can_quit()` is false.
* **Settings** — the Controls tab lists the TOUCH CONTROLS section first on touch devices
  (on-screen controls auto/on/off, button size, opacity, left-handed, look speed, auto
  sprint, haptics); key rebinding stays disabled on phones.
* **Android back button / gesture** — `MobilePlatform` turns it into `pause` in gameplay and
  `ui_cancel` in menus (never quits mid-journey); sending the app to the background releases
  every held action and pauses a running game.
* Drag-scrolling settings pages works (Godot ScrollContainer touch scrolling, verified in
  Chromium with touch emulation).

## Platform helpers

```gdscript
PlatformInfo.is_web(); PlatformInfo.is_web_mobile(); PlatformInfo.is_native_mobile()
PlatformInfo.can_quit()            # false on Web / iOS
PlatformInfo.has_threads()         # false on our Web build
PlatformInfo.describe()            # "Android (mobile app) · Mobile · Adreno ..."
MobilePlatform.ensure(get_tree())  # installed by UiInput.ensure (every menu + HUD)
```

### Compatibility renderer: MultiMesh colours — `RenderCompat`

On the Compatibility renderer (Web, and desktop OpenGL) a MultiMesh that has per-instance
custom data but **no** per-instance colours read garbage into the mesh's vertex `COLOR` in
the world scene: grass, trees, rocks and bird flocks came out in neon noise on the Web build
(isolated test scenes were fine, so it is an engine-side state issue we could not pin down
further). Giving those MultiMeshes white instance colours fixes it:

```gdscript
RenderCompat.configure(mm, use_custom)        # before instance_count: use_custom_data (+ use_colors on Compatibility)
mm.buffer = RenderCompat.buffer_for(mm, buf)  # 16-float stride -> 20 with white colours when needed
RenderCompat.whiten(mm)                        # MultiMeshes filled with set_instance_* calls
```

Applied in `WorldContent.spawn_multimesh`, `VegetationProvider`, `SettlementFx` and
`BirdFlock`; Forward+ / Mobile keep their 16-float buffers. `mobile_compat_probe` (pixel
read-back of INSTANCE_CUSTOM rows) and `mobile_veg_probe` (library vegetation in a test stage)
are the renderer regression probes.

## Exports

| Preset | Renderer | Notes |
| --- | --- | --- |
| Web | Compatibility (WebGL 2) | **no threads** (runs in every mobile browser without COOP/COEP headers), ETC2/ASTC + S3TC textures, `head_include`: fullscreen + landscape lock on the first tap, "rotate your device" card in portrait, no pinch-zoom / overscroll |
| Android | Mobile (Vulkan) | arm64-v8a, package `com.fournations.avatar`, landscape (project `handheld/orientation` = sensor landscape), immersive, keep screen on, VIBRATE permission, prebuilt template (no Gradle) |
| iOS | Mobile (Metal) | exports an Xcode project (`export_project_only`); set your App Store Team ID and build on a Mac |
| Linux / Windows Desktop | Forward+ | x86_64, PCK embedded |

```bash
tools/export/export_web.sh [release|debug]     # -> build/web (≈ 40 MB wasm + 55 MB pck; 10 + 53 MB gzipped)
python3 tools/export/serve_web.py --host 0.0.0.0   # http://<pc-ip>:8060 from a phone on the same Wi-Fi
NODE_PATH=/opt/node-tools/node_modules node tools/export/web_smoke.mjs --out .playtest/web
tools/export/export_android.sh [debug|release] # -> build/android/avatar-four-nations-debug.apk (≈ 82 MB)
```

**World data.** Every preset has `include_filter="assets/world/*"`: the heightmap
(`heightmap.r16.zlib`, importer *keep*) is not a resource type, so the default
"all resources" export silently left it out and every exported build ran on the flat
fallback world ("The Wilds"). `test_export_presets` guards the filter and `web_smoke.mjs`
fails when the world turns out flat. `build/` carries a `.gdignore` (created by the export
scripts) so Godot never imports exported files back into the project.

`export_android.sh` needs a JDK 17+ and Android build-tools with `apksigner`
(`ANDROID_HOME`); on Debian / Ubuntu `apt install apksigner zipalign adb` is enough — the
script assembles a minimal SDK layout around them, creates a debug keystore and seeds Godot's
editor settings. Release builds read Godot's `GODOT_ANDROID_KEYSTORE_RELEASE_*` variables.

### Installing the APK on a phone
1. Download the `android-debug-apk` artifact from the latest *Build* workflow run (GitHub →
   Actions → Build → run → Artifacts), or build it with `tools/export/export_android.sh`.
2. Copy `avatar-four-nations-debug.apk` to the phone (USB, cloud drive, e-mail) and open it;
   allow "Install unknown apps" for the app you opened it with. Or with USB debugging on:
   `adb install -r avatar-four-nations-debug.apk`.
3. Requires Android 7.0+ (API 24), a 64-bit ARM device with Vulkan 1.0+ (Godot's Mobile
   renderer; devices without Vulkan fall back to OpenGL ES 3 via
   `rendering_device/fallback_to_opengl3`).

### Web on a phone
Open the GitHub Pages URL (or `serve_web.py` on the LAN), tap once (fullscreen + landscape),
play. The first launch downloads ~63 MB (gzipped; the world heightmap and textures are most
of the pck) and is cached by the browser.

## CI — `.github/workflows/build.yml`

On push to `main` / the `ccr-*` integration branches and on manual dispatch: installs Godot
4.7.2 + export templates from the official release (SHA-512 verified, cached), runs
`tools/check.sh` and `tools/test.sh` (skippable on dispatch), exports Web, the Android debug APK
(JDK 17 via `actions/setup-java`, the runner's preinstalled Android SDK; `sdkmanager` installs
build-tools if missing), Linux and Windows, uploads each as an artifact (`web`,
`android-debug-apk`, `linux-x86_64`, `windows-x86_64`) and deploys the Web build to GitHub Pages
in a separate job with `continue-on-error` (a repository without Pages enabled never fails
the build; enable Pages → Source: GitHub Actions to get the site). Actions pinned by major
version: checkout@v5, cache@v4, setup-java@v5, upload-artifact@v4, upload-pages-artifact@v4,
configure-pages@v5, deploy-pages@v4.

## Performance

Measured with `tests/playtest/scenarios/mobile_perf.gd` (`MOBILE=1`, mobile preset, render
scale 0.75, 1280×720, new Water-Tribe game at the Northern Water Tribe spawn — the heaviest
home region — four view directions, a sprint through the city, then a fight in the combat
arena) on the Mobile renderer and on Compatibility (the Web renderer). `PerfProbe` reads the
renderer's own counters; `census` lists what is drawn by owner (streamed content by provider
and payload tag) and `_breakdown` hides one group at a time to measure its cost.
Frame times are llvmpipe software rendering in this container (4 shared cores): they rank
costs, they do not predict a phone. Draw calls and primitives are the device-independent
budget.

**What was expensive** (Mobile renderer, Water Tribe spawn, before):

| group | draws (+shadow) | primitives (+shadow) |
| --- | --- | --- |
| Northern Water Tribe near cells (LOD0 + LOD1) | 40 (+9) | 874k (+1286k) |
| settlement silhouettes (LOD2) | 47 | 142k |
| terrain clipmap | 85 (+64) | 36k (+41k) |
| player / companion rigs | 1 + 1 (+2) | 21k + 12k (+68k) |
| water | 17 | 24k |

The merged LOD1 city meshes (100k+ triangles per draw, up to 420 m) casting sun shadows were
almost the whole shadow pass. Elsewhere the world is light: the Earth Kingdom home spawn draws
109 (+62) calls, 165k (+53k) primitives; the arena 60 (+52), 71k (+71k).

**Changes** (every one outside this module is listed under "Changes outside the module"):

1. `SettlementSettings`: new budget `lod1_shadows` (false at detail 0 = low / mobile);
   `SettlementProvider` casts LOD1 shadows only when it is set. LOD0 (the 100 m around you)
   still casts shadows.
2. `SettlementSettings`: low / mobile LOD ranges 110 → 100 m (full detail) and 420 → 300 m
   (simplified buildings; silhouettes beyond). 100 m still covers the half diagonal (90.5 m)
   of the camera's own 128 m cell, so props never drop out next to the player
   (`test_mobile_preset_budgets`).
3. `Settings.configure_sun`: shadow level 1 (mobile / low) renders one orthogonal shadow map
   (60 m) instead of two PSSM splits — one shadow pass instead of two on tile-based GPUs;
   caster counts barely change (arena 47 → 52 shadow draws, 78k → 71k shadow primitives), so
   this is a pass-count saving, not a geometry one.
4. Earlier in the module: no FSR 1 on the Mobile renderer (Forward+ only in 4.7: it warned and
   fell back every frame), bilinear scaling instead; Compatibility maps FXAA / SMAA / TAA to
   MSAA 2× and `project.godot` sets `screen_space_aa.web=0` (no screen-space AA in WebGL);
   `WorldContent` builds one cell per frame when there are no threads (Web); `RenderCompat`.

**Before → after** (world: Water Tribe spawn, view 0, mean of 3 s; arena: idle / warm fight):

| | Mobile renderer before | Mobile renderer after | Compatibility before | Compatibility after |
| --- | --- | --- | --- | --- |
| world draw calls | 195 (+75 shadow) | 195 (+67) | 586 | 440 |
| world primitives | 1117k (+1396k shadow) | 838k (+245k) | 1117k (+1396k) | 838k (+245k) |
| world, 4 views: prims (+shadow) | 652–1117k (+1042–1396k) | 529–838k (+245–256k) | same | same |
| world frame (llvmpipe) | 552 ms | 430 ms | 1292 ms | 1051 ms |
| world census | 167 instances, 837k tris | 171 instances, 667k tris | | |
| arena draw calls | 61 (+47) | 60 (+52) | — | 183 |
| arena frame idle / warm fight | 130 / 113 ms | 109 / 107 ms | — | 650* / 187 ms |

Visible primitives −25 %, shadow primitives −82 %, Compatibility draw calls −25 % (it draws
shadowed geometry in an extra light pass, so the shadow saving shows up as draw calls).
Both renderers draw the same geometry; Compatibility reports more draw calls for it (one per
surface and light pass). *The Compatibility arena idle sample includes pipeline compilation
(p95 2.3 s); first casts of each technique hitch on every renderer (p95 0.5–0.7 s under
llvmpipe on the Mobile renderer) and run normally once warm.

World census after (Mobile, view 0): 171 visible instances, 2617 MultiMesh instances, 2 skinned
rigs (player + companion), 3 particle systems (18 particles), no dynamic lights by day; arena:
82 instances, 3 skinned rigs, 1 light. Shadows off entirely on Compatibility would save
another 82 draw calls (440 → 358) for no measurable frame-time change here, so the mobile
preset keeps its sun shadows.

**perf_polish (wave 4, docs/qa/perf_polish.md)** took the next candidates below: a phone LOD
chain for the settlements (quadrant HLOD LOD0, silhouette-kit LOD1 to 220 m, outline-less merged
LOD1 / LOD2, mesh LODs with a lower `lod_bias` for distant meshes), night glows hidden by day,
garden and far-forest caps, character mesh LODs, a 64-segment phone ocean and a shader warm-up
behind the loading screen. Worst of four views at each home spawn, mobile preset, Mobile
renderer: Water Tribe 998k → 246k primitives / 210 → 170 draws, Ba Sing Se 1055k → 231k /
403 → 196, Fire Nation 1038k → 188k / 409 → 141, Air Temple 972k → 169k / 265 → 133
(budget < 250k / < 200; Compatibility: same primitives, 247-366 draws with its light pass and
depth prepass). Measured with `perf_polish_budget` (see that doc).

**Left as they are / next candidates (before perf_polish):** the terrain clipmap (85 draws, 36k primitives — the
draw count is the clipmap's fixed tile layout); settlement silhouettes (one mesh per 128 m
sub-cell so LOD1 → LOD2 hands over exactly: 56 draws on Mobile, 159 on Compatibility) plus one
night-glow MultiMesh per sub-cell that is still submitted by day (collapsed in the vertex
shader); a lighter phone LOD1 for the big cities; a shader warm-up for the first casts.

```bash
MOBILE=1 RENDERER=mobile tools/playtest.sh mobile_perf .playtest/perf 1280x720            # + perf_mobile_mobile.json
MOBILE=1 RENDERER=gl_compatibility tools/playtest.sh mobile_perf .playtest/perf_gl 1280x720
# ELEMENT=earth|fire|air (home region), PRESET=low|medium, SHADOWS=0..4, SKIP_WORLD=1, SKIP_ARENA=1
```

## Changes outside the module

All minimal and additive; desktop behaviour is unchanged unless noted.

| File | Change |
| --- | --- |
| `src/ui/hud/hud.gd` | creates the `TouchOverlay`; `apply_touch_layout(on, left_handed)` hides the ability bar / prompt panel and moves toasts, quest tracker, companion plate; interaction prompt suppressed while touch is active |
| `src/ui/hud/hud_ability_slot.gd` | `show_prompt` (false: no key glyph; used inside touch buttons) |
| `src/ui/theme/ui_input.gd` | `ensure()` also installs `MobilePlatform` |
| `src/ui/widgets/prompt_glyph.gd` | collapses on touch; `tap_on_touch` draws a tap mark instead |
| `src/ui/widgets/input_hint_bar.gd` | hidden while the device is touch |
| `src/ui/widgets/ui_choice.gd` | on touch acts on lift and only for a tap (≤ 24 px), lets drags reach the ScrollContainer |
| `src/ui/widgets/ui_toggle.gd` | ignores the lift that ends a scroll drag |
| `src/ui/common/dialogue_box.gd` | tapping the panel advances; advance prompt shows a tap mark |
| `src/ui/menu/main_menu.gd`, `src/ui/pause/pause_menu.gd` | EXIT / QUIT TO DESKTOP hidden where quitting is impossible (Web, iOS); focus neighbours over visible options |
| `src/ui/settings/settings_schema.gd` | Controls tab: TOUCH CONTROLS section first on touch devices |
| `src/autoload/settings.gd` | FSR 1 Forward+ only; bilinear scaling on Mobile / Compatibility; Compatibility AA fallback to MSAA 2×; shadow level 1 = one orthogonal cascade |
| `project.godot` | `rendering/anti_aliasing/quality/screen_space_aa.web=0` |
| `.gitignore` | `export_presets.cfg` is versioned now |
| `src/world/content/world_content.gd` | one build job without threads (Web); MultiMeshes through `RenderCompat` |
| `src/world/vegetation/vegetation_provider.gd`, `src/world/settlements/common/settlement_fx.gd`, `src/creatures/birds/bird_flock.gd` | MultiMesh buffers / colours through `RenderCompat` (Compatibility only) |
| `src/world/settlements/common/settlement_settings.gd` | `lod1_shadows` budget; low LOD ranges 100 / 300 m |
| `src/world/settlements/common/settlement_provider.gd` | LOD1 shadow casting follows `lod1_shadows` |
| `docs/modules/settlements.md`, `docs/modules/settlements_wa.md` | budget tables updated |

## Testing

* `tools/test.sh test_mobile` — TouchActions (sources, minimum hold, analog, events,
  release_all), stick maths (dead zone, edge sprint hysteresis, base follow, on-screen
  clamp), layout (6 aspects × 4 scales × 2 hands: no overlaps, on screen, ≥ 88 px), overlay
  routing (stick + look + two buttons on four fingers at once, GUI touch events by index,
  emulated mouse ignored, empty slots, dialogue hides + releases, lock tap / cycle / hold,
  mounted mode), a real `PlayerCharacter` moved and made to jump by the overlay, haptics
  routing + throttle, back button / background, PlatformInfo, FSR flag per renderer, export
  presets and the CI workflow.
* Playtests (`MOBILE=1 RENDERER=mobile tools/playtest.sh <name> <out> 1600x720`):
  `mobile_touch` (combat arena, every control by simulated touch, 10 shots), `mobile_menus`
  (main menu, settings, element select, dialogue by tap), `mobile_world` (the world scene:
  run, look, strike, call + ride + fly + land + dismount the companion by touch),
  `mobile_perf` (measurements below; also `RENDERER=gl_compatibility`).
* `tools/export/web_smoke.mjs` — the exported Web build in headless Chromium as a Pixel 7
  (landscape, touch, device DPR 2.625; `--dpr 1` keeps SwiftShader fast): boot, main menu,
  settings by tap + drag-scroll, element select by tap, world (fails on the flat fallback
  world), stick run, strike, heavy, pause by touch, resume.
* `tools/test.sh test_mobile` also checks the mobile budgets (one shadow cascade, no LOD1
  settlement shadows, LOD ranges) — see Performance.

## Known limitations

* **No real device was tested.** Everything above ran in this container: Godot under Xvfb
  (llvmpipe for Vulkan / OpenGL) with simulated `InputEventScreenTouch` / `ScreenDrag` events,
  and the Web build in headless Chromium (SwiftShader WebGL 2) with CDP touch events. Frame
  times are software-rendering numbers; the draw-call / primitive budgets are what transfers.
* **Android APK built, never launched.** `export_android.sh debug` produces a signed,
  verified arm64-v8a APK (landscape, immersive, VIBRATE, world data inside); there is no
  emulator / device here, so install, Vulkan start-up and real haptics are unverified.
* **iOS** exports an Xcode project only; it needs an App Store Team ID and a Mac to build.
* **Web** is single-threaded (no SharedArrayBuffer needed): world streaming runs one content
  build per frame on the main thread, so first arrival in a region takes noticeably longer
  than on desktop (3–5 min from element select to control under SwiftShader). First download
  ≈ 63 MB gzipped.
* **First-use shader hitches**: the first casts of each technique compile pipelines
  (arena p95 ≈ 0.5–0.7 s under llvmpipe on the first round, normal once warm). Not addressed
  (would need a per-element warm-up pass owned by the bending / fx modules).
* **Settlements stay the heaviest thing on screen** in the Water Tribe / Ba Sing Se style
  cities even after the trims (≈ 0.5–0.6 M visible triangles at the Water Tribe spawn on the
  Mobile renderer); a lighter LOD1 mesh for phones would be the next step (settlement modules).
* The Compatibility-renderer MultiMesh colour workaround (`RenderCompat`) costs 4 extra floats
  per instance on Web; the root cause in the engine was not isolated.
* Chromium logs GL "ReadPixels / GPU stall" performance warnings during the smoke test; they
  come from the screenshot capture, not from the game.
* Haptics in mobile browsers rely on `navigator.vibrate` (Android Chrome yes, iOS Safari no).
* Touch remapping of buttons (drag to rearrange) is not offered; size, opacity and hand are.

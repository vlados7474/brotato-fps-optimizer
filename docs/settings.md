# Saffron-Turbo — settings reference

Brotato 1.2.0.3 · ModLoader 6 (bundled with the game) · version 5.3.0

Settings are stored in a real file you can edit with any text editor. Brotato
1.2.0.3 keeps its user data in **%APPDATA%** (older 1.2.0.1 kept it next to the
game exe — that no longer applies):

```
%APPDATA%\Brotato\configs\Saffron-Turbo\turbo_config.json
```

That is typically `C:\Users\<you>\AppData\Roaming\Brotato\configs\...`. The
`configs\Saffron-Turbo` folder and the file are created on first launch. Values
in the file override the built-in defaults, edits made in a ModOptions UI
(Oudstand or dami) win while that UI mod is installed, and a one-shot launch
parameter `--saffron-set=key=val` (repeatable) overrides anything for that
session only — it never writes to disk. Files written by older mod versions are
upgraded in place: missing keys are added, nothing of yours is deleted. Delete
the file to return to defaults.

The mod's log lines live in `%APPDATA%\Brotato\logs\godot.log`.

Launch parameter required by the loader itself, not by this mod:

```
--enable-mods
```

## How to confirm a value actually took effect

The mod prints one line at startup with the values that won (all 48 keys, so an
automated check can parse any token):

```
Saffron-Turbo active config: adaptive_quality=true cache_weapon_targets=true ... | editable file: <exact path on your machine>
```

The `editable file:` part prints the exact location on your machine — if you
cannot find the file, read that line in the log instead of guessing. If your
edit is not in `active config`, the file is not where the mod looks, or it is
not valid JSON (the mod then falls back to defaults and logs a warning).

## Targeting and per-tick costs — default ON, no gameplay change

| Key | Default | Meaning |
|---|---|---|
| `cache_weapon_targets` | `true` | Reuse the chosen target for a few physics ticks instead of running a full nearest-enemy scan every tick. The point, distance and angle to that target are still recomputed every tick, and the scan is never skipped on ticks where the weapon can fire. |
| `target_cache_frames` | `3` | How many physics ticks a target choice may be reused (minimum 1). |
| `stagger_target_scans` | `true` | Spreads remaining full scans across frames so many weapons do not all rescan on the same tick. |
| `fast_nearest_scan` | `true` | Replaces the engine call `distance_squared_to` in nearest-enemy scans with plain scalar math and an axis pre-filter — same result, no per-enemy method dispatch. |
| `cache_manual_aim` | `true` | Caches the manual aim point between ticks instead of resolving it per weapon per tick. |
| `throttle_slow_scans` | `true` | Slow area scans (scaling-stat weapons scanning every enemy) run at most once per interval. |
| `slow_scan_interval_ms` | `250` | That interval in milliseconds. |
| `guard_weapon_property_writes` | `true` | Skips weapon sprite/property writes on ticks where nothing changed. |
| `guard_unit_transforms` | `true` | Skips unit transform writes when the value did not change. |
| `disable_object_picking` | `true` | Sets `root.physics_object_picking = false`. Brotato ships no pick handlers, yet the engine still runs a point query against every pickable body on each mouse event — and mouse aiming produces those continuously. It affects the whole viewport while it is on. |

## Effects, particles, crowd — default ON, picture only

| Key | Default | Meaning |
|---|---|---|
| `pool_projectile_effects` | `true` | Reuses projectile effect scenes instead of instantiating and freeing them per shot. |
| `scale_explosion_smoke` | `true` | Shrinks explosion/smoke particles (scale 0.55) — fewer pixels for the same effect. |
| `throttle_particle_sim_fps` | `true` | Lets the governor lower the particle simulation rate while frames are late, instead of only shrinking amounts. |
| `cull_offscreen_effects` | `true` | Effects whose spawn point is outside the camera rectangle (plus `cull_margin`) are never created. The rectangle is recomputed once per physics tick, not per effect. |
| `cull_margin` | `160` | Extra pixels of tolerance around the visible rectangle, so effects do not visibly pop in at the screen edge. |
| `throttle_damage_numbers` | `true` | Caps how many floating damage texts exist at once and decides the skip before vanilla builds the string and the world position. |
| `max_floating_texts` | `40` | Cap on concurrent damage numbers (minimum 1). In Stream Potato the cap is 10. |
| `batch_damage_numbers` | `true` | When the cap is approached, merges further hits into existing text nodes instead of spawning new ones; crits on a calm frame still get their own number. |
| `throttle_flashes` | `true` | Throttles hit flashes, which are also costly for a video encoder. |
| `flash_interval_ms` | `100` | Minimum gap between flashes. |
| `batch_friendly_flash` | `true` | Merges flash writes for friendly units within the same interval window. |
| `limit_screenshake` | `true` | Replaces vanilla screen shake with capped, rate-limited, integer-quantized camera offsets. Subpixel shake makes the Remote Play encoder re-encode the whole frame on every shake. |
| `screenshake_max_intensity` | `1.5` | Shake amplitude cap in pixels while limiting is on (the governor clamps it to 1 at tier ≥ 3). |
| `screenshake_min_interval_ms` | `150` | Minimum gap between shake triggers; extra triggers inside the window are dropped (0–∞). |
| `pause_crowd_idle_anim` | `true` | Pauses idle animations of enemies when the crowd is large — alive-looking picture during light phases, no wasted redraws during hordes. |
| `crowd_anim_threshold` | `60` | Enemy count above which idle animations pause (10–1000). |
| `particle_budget_scale` | `1.0` | Multiplier on particle amounts (0.05–1.0). The adaptive governor lowers it further while frames are actually late. |

## Audio — default ON

| Key | Default | Meaning |
|---|---|---|
| `dedup_audio` | `true` | Collapses duplicate sound triggers inside the Haas stereo-fusion window (~22–45 ms) and culls offscreen 2D sounds at tier ≥ 2 before the audio server even sets up the stream. Drains queued sounds at up to 3 per frame. |

## Burning spread — default ON, fixes idle cost without changing fire

| Key | Default | Meaning |
|---|---|---|
| `fix_idle_burn_spread` | `true` | A burning unit's fire-spread area is enabled only while the fire is actually alive. Vanilla leaves thousands of spread areas permanently registered. When this is `false` the mod stays out of burning entirely (vanilla behaviour, vanilla cost). |

## Adaptive governor — default ON

| Key | Default | Meaning |
|---|---|---|
| `adaptive_quality` | `true` | The governor watches real frame time (respecting vsync and the game's own FPS limit) and tightens visual budgets in tiers 0–4, then relaxes them again. It cuts visuals; the simulation tick rate moves only through `potato_physics` and `spiral_guard` (see below), never through enemy count. |
| `min_tier` | `0` | Floor for the governor (0–4). `0` means nothing is reduced until the frame time actually degrades. |
| `load_spike_enemies` | `300` | Enemy count at which the governor pre-emptively holds at least tier 2, before frame time drops. `0` disables the pre-emptive path. |
| `spiral_guard` | `true` | Two jobs, and the second one changes the game. (1) Anti-oscillation: once frame time collapses, budgets stay held down until the frame time genuinely recovers instead of flapping between tiers. (2) If the smoothed frame time stays at or above 50 ms for a second while `potato_physics` is off, it runs the physics at **30 Hz** until frame time recovers below 28 ms — the engine's catch-up loop can never climb out of a spiral below `60 / 8 = 7.5` fps, and halving the tick rate moves that cliff to 3.75 fps. Set `false` to keep 60 Hz through a collapse and take the deeper stall instead. |
| `potato_physics` | `true` | **Changes the simulation.** While the governor is in a heavy tier it runs physics at 45 Hz (tier 2), 30 Hz (tier 3) and `emergency_physics_hz` (tier 4), and restores 60 Hz when the load clears. Spawn pacing counts ticks, knockback is a per-tick lerp and cooldowns decay per tick, so those windows feel different — it is not just fewer pixels. **Honest 60 Hz at all times needs `potato_physics` AND `spiral_guard` both `false`.** |
| `emergency_physics_hz` | `20` | Tick rate used at tier 4 while `potato_physics` is on (0–60; `0` keeps 30 Hz there). |

## Streaming presets — default OFF, they change the game's own options

| Key | Default | Meaning |
|---|---|---|
| `stream_potato` | `false` | One switch that tightens everything visual at once: damage-number cap 10, no shake, no flashes, particle scale ≤ 0.25. Deliberately explicit — it trades picture for stability. |
| `fps_limit` | `0` | `0` leaves your setting alone, `1` turns on the game's own 60 FPS limit, `-1` turns it off. A steady 60 feeds the Steam Remote Play encoder far better than 124 with spikes. **This writes the game's own option and stays set after the mod is removed.** |
| `native_switches` | `false` | Uses the game's own `visual_effects` and `screenshake` switches instead of only the mod's budgets. Bigger win, but it flips settings in the game's own options menu. **Stays set after the mod is removed.** Implied by `stream_potato`. |
| `disable_vsync` | `false` | Turns off vsync so the frame rate is uncapped. Leave off unless you know your monitor and your encoder can use the extra frames. |

## Diagnostics — default OFF

| Key | Default | Meaning |
|---|---|---|
| `agent_telemetry` | `false` | Writes per-run metrics to `%APPDATA%\Brotato\logs\saffron_agent_telemetry.jsonl` (also enabled by the `--saffron-telemetry` launch parameter). For QA runs, not needed to play. |

## What this mod does not do

It does not change damage, health, prices, drops, economy, enemy AI, wave
timings, bosses, challenges, saves or unlocks. Two switches move the physics
tick rate, and both only do it **while the frame time is already collapsing**:
`potato_physics` (tiers 2–4) and `spiral_guard` (30 Hz during a sustained
>= 50 ms stall). At all other times physics runs at the game's normal 60 Hz,
and every change is written to the log with the key that caused it
(`physics tick rate 60 -> 30 Hz. Reason: ...`).

## Removing the mod

Delete the zip (or unsubscribe). The game's own options changed by `fps_limit`
and `native_switches` are not reverted automatically — undo them in the game's
Options menu. The config file above is yours and is simply ignored once the
mod is gone.

## v5.3.0 Engine, Render & Opt-in Endless Keys (8 New Keys)

| Key | Default | Range / Type | Description |
| :--- | :---: | :---: | :--- |
| `enable_worker_thread` | `false` | bool | Opt-in background `Thread` spatial hash builder (`turbo_worker.gd`) using zero-allocation `int` instance IDs. |
| `worker_min_enemies` | `120` | 40-1000 | Minimum live enemy count before submitting snapshots to the background worker thread. |
| `pool_outline_materials` | `true` | bool | Shares pooled `ShaderMaterial` outlines (O(1) LRU, 256 cap) across identical enemies and projectiles to restore 2D batching. |
| `fast_canvas_damage_numbers` | `true` | bool | Renders plain damage numbers via a single 1-draw-call `Node2D._draw()` canvas; icons, player hits, and translated labels stay on vanilla `FloatingText`. |
| `compress_excess_fruits` | `false` | bool | Opt-in Endless fruit stacker (merges excess common ground fruits above `max_ground_fruits` while replaying Farmer/Glutton/Spicy Sauce triggers; excludes crates, DLC fruits, and Druid poisoned fruits). |
| `max_ground_fruits` | `40` | 10-200 | Ground fruit threshold before `compress_excess_fruits` merges new common fruits into stacks (up to 12x). |
| `relax_enemy_collisions` | `false` | bool | Opt-in Endless enemy-vs-enemy collision relaxation above `relax_collision_threshold` (preserves player/weapon/projectile hitboxes, bosses, elites, loot, and charmed enemies). |
| `relax_collision_threshold` | `140` | 50-1000 | Enemy count threshold (with 15-enemy hysteresis) for `relax_enemy_collisions`. |

## Included Presets (`presets/`)

Copy any JSON preset over `user://configs/Saffron-Turbo/turbo_config.json`:
- `presets/vanilla_60hz.json` — Strict 60 Hz (`potato_physics: false`, `spiral_guard: false`).
- `presets/turbo_balanced.json` — Release defaults with `potato_physics: false` (and `spiral_guard: true` as the emergency shield): stays at 60 Hz outside a sustained collapse.
- `presets/endless_max.json` — Deep Endless (Wave 50+ / 200+): enables worker thread, `potato_physics`, `relax_enemy_collisions`, and `compress_excess_fruits`.
- `presets/remote_play.json` — Stream / Steam Remote Play profile (`stream_potato: true`, `fps_limit: 1`, `min_tier: 1`).
- `presets/engine_override_sample.ini` — Optional Godot engine settings sample (copy manually next to `Brotato.exe` as `override.cfg` if desired).

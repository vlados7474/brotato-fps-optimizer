# Saffron-Turbo 5.3.1 Release Notes

Target: Brotato 1.2.0.3 (Godot 3.5.3) | ModLoader 6 | 49 config keys (48 user-facing) | 17 script extensions | 31 self-test assertions

## What this release is

5.3.1 is the audited release line of the 5.3.x rewrite. It fixes two
release-blocking defects found in the 5.3.0 fork and one defect inherited by
every 5.0.x release, and restores the 30 Hz physics ladder as the default.

## Fixed against 5.0.2

1. **Double-run of vanilla `_physics_process` (defect #12).** Probes on the real
   3.5.3 engine with ModLoader's exact takeover sequence showed that after
   `take_over_path` the parent script's `_physics_process` still runs every frame
   after the extension's body. The inlined vanilla bodies in
   `entity_birth.gd` / `burning_particles.gd` / `entity_spawner.gd` therefore ran
   the vanilla logic twice per tick: births at half duration, doubled
   `birth_timeout`, and a non-consuming `_spawn_entity_from_request` spawning
   about twice as many enemies. In 5.3.1 both extension bodies are additive-only
   and the entity_spawner extension is removed entirely; vanilla spawn logic runs
   exactly once, exactly as the game ships it. Live confirmation on the same
   seed: 57-60 hatches per window vs 142-156 in previously published 5.0.2 runs.
2. **`ProgressData.increment_stat` arity** in `extensions/main.gd` — the fork
   called it with 2 arguments while the game declares 1..1 (parse error). Fixed
   to the vanilla single-argument call; verified by an offline arity checker
   against all 35 game autoloads.
3. **`enemy_projectile` extension path/extends** — the extension sat in the wrong
   folder and extended a nonexistent path. ModLoader 6's `apply_extension` does
   not null-check `get_base_script()`, so one broken extends aborted the whole
   extension install loop (remaining extensions never installed; the ERROR line
   names `mods-unpacked`, which feeds the game's crash-safe mode). Path and
   `extends` fixed; extension set is now 17, ordered parent-before-child
   (Entity -> Unit -> Enemy -> Pursuer).
4. **`potato_physics` default restored to `true`** — the 45/30/20 Hz ladder is
   the factory default again, aimed at Remote Play hosts. The 5.0.x migration
   that rewrote an existing user's saved `potato_physics` choice on disk is gone;
   a saved choice is never rewritten.
5. **Key sync 1-to-1** (`config_version` added to `config_schema`): code
   DEFAULTS 49 == manifest config_defaults 49 == schema 49; UI carries the 48
   user-facing keys (config_version is a const, not a setting); the four presets
   in `presets/` are complete and inside schema bounds.

## New from the 5.3.x rewrite

- Background worker thread for the spatial hash grid (opt-in,
  `enable_worker_thread`, off by default).
- Pooled ShaderMaterials for outlines/projectiles (2D batching,
  `pool_outline_materials`).
- 1-draw-call Canvas damage numbers (`fast_canvas_damage_numbers`).
- Endless opt-in tools that DO change gameplay and stay off by default:
  `compress_excess_fruits` / `max_ground_fruits` (Fruit Compressor) and
  `relax_enemy_collisions` / `relax_collision_threshold`.
- Presets shipped in the zip: `presets/remote_play.json`,
  `turbo_balanced.json`, `endless_max.json`, `vanilla_60hz.json`.

## Verification (2026-11-22)

- Offline release gate: 29/34 PASS (remaining FAILs are long-standing
  gate-contract debts shared with 5.0.x, not regressions).
- Engine compile pass: 29 scripts, real Godot 3.5.3 binary, 0 errors.
- Live 3x3 bench on pinned release defaults (wave200, seed 20261118): vanilla
  fps mean 7.77 vs turbo mean 92.97 (median 90.5), paired ratio x12.0; 0%
  catch-up spiral, 0% below 15 fps; all 6 legs valid, census CONTAMINATED
  (advisory) on all, none INVALID. The governor logged the potato tier ladder
  (60->45->30->20 Hz) in every turbo leg.
- Two independent critic reviews; the only MAJOR claim (missing
  `Thread.is_alive()` in 3.5.3) was refuted by an engine probe.

extends Reference
# =============================================================================
# Saffron-Turbo 5.6.1 - Flat Zero-Overhead Shared Runtime State
# -----------------------------------------------------------------------------
# Bound once per extension node in _ready(). Eliminates all hot-path
# Engine.get_main_loop().get_meta() hash lookups and Dictionary allocations.
# =============================================================================

const HOLDER: Dictionary = {}

var tier: int = 0
var phys_hz: int = 60
var in_run: bool = false

var adaptive_quality: bool = true
var cull_offscreen: bool = true
var cull_margin: float = 160.0
var cull_extra_margin: float = 0.0

var throttle_damage_numbers: bool = true
var max_floating_texts: int = 40
var text_cap: int = 40
var batch_damage_numbers: bool = true

var particle_budget_scale: float = 1.0
var particle_scale: float = 1.0
var scale_explosion_smoke: bool = true
var explode_smoke_scale: float = 0.55
var throttle_particle_sim_fps: bool = true
var fx_sim_fps: int = 0
var fx_per_frame: int = 0
var fx_alive_cap: int = 100
var fx_lifetime_scale: float = 1.0

var cache_weapon_targets: bool = true
var target_cache_frames: int = 3
var cache_extra_frames: int = 0
var stagger_target_scans: bool = true
var fast_nearest_scan: bool = true
var pool_projectile_effects: bool = true
var force_fresh_scan: bool = false
var guard_weapon_property_writes: bool = true
var cache_manual_aim: bool = true

var throttle_slow_scans: bool = true
var slow_scan_interval_ms: int = 250

var throttle_flashes: bool = true
var flash_interval_ms: int = 100
var disable_flash: bool = false
var batch_friendly_flash: bool = true

var guard_unit_transforms: bool = true
var fix_idle_burn_spread: bool = true
var dedup_audio: bool = true

var pause_crowd_idle_anim: bool = true
var crowd_anim_threshold: int = 60
var spiral_guard: bool = true
var agent_telemetry: bool = false

var limit_screenshake: bool = true
var screenshake_max_intensity: float = 1.5
var screenshake_min_interval_ms: int = 150
var disable_shake: bool = false

var stream_potato: bool = false
var potato_physics: bool = true
var emergency_physics_hz: int = 20
var fps_limit: int = 0
var native_switches: bool = false
var min_tier: int = 0
var disable_vsync: bool = false
var load_spike_enemies: int = 300
var disable_object_picking: bool = true
var enable_worker_thread: bool = false
var worker_min_enemies: int = 120
var pool_outline_materials: bool = true
var fast_canvas_damage_numbers: bool = true
var compress_excess_fruits: bool = false
var max_ground_fruits: int = 40
var relax_enemy_collisions: bool = false
var relax_collision_threshold: int = 140

# 5.4.0 feature flags
var enable_interpolation: bool = true
var max_visible_burns: int = 24
var isolate_enemy_hitbox_layer: bool = true
var z_bucket_shadows_gold: bool = true
var optimize_projectiles: bool = true
var optimize_attack_behaviors: bool = true
var optimize_hud_inventory: bool = true
var prewarm_pools: bool = true

# 5.4.0 runtime fields & EngineSnapshot
var burn_vis_active: int = 0
var burn_vis_cap: int = 24
var interpolator = null
var stepper = null
var orig_object_picking: bool = true
var orig_jitter_fix: float = 0.5
var orig_jitter_fix_captured: bool = false

# 5.5.0 per-tick physics snapshot (populated once/tick in TurboGovernor)
var tick_enemy_tf: float = 1.0
var tick_zone_valid: bool = false
var tick_zone_min_x: float = 0.0
var tick_zone_min_y: float = 0.0
var tick_zone_max_x: float = 0.0
var tick_zone_max_y: float = 0.0
var tick_p0 = null
var tick_p0_x: float = 0.0
var tick_p0_y: float = 0.0
var tick_p0_pos: Vector2 = Vector2.ZERO
var orig_object_picking_captured: bool = false
var orig_vsync: bool = true
var orig_visual_effects: bool = true
var orig_screenshake: bool = true
var orig_snapshot_captured: bool = false
var config_rev: int = 0
var tier_rev: int = 0

var cam_rect: Rect2 = Rect2()
var cam_rect_unit: Rect2 = Rect2()
var cam_valid: bool = false
var cam_frame: int = -1

var grid = null
var worker = null
var next_phase: int = 0

var census_enemies: int = 0
var census_bosses: int = 0
var census_spawn_queue: int = 0
var census_projectiles: int = 0
var census_effects: int = 0
var census_texts: int = 0
var census_ft_fast_ms: float = 0.0
var census_ft_ms: float = 0.0
var census_ft_p95_ms: float = 0.0
var census_ft_worst_1s_ms: float = 0.0
var census_est_ms: float = 0.0
var census_est_v2_ms: float = 0.0
var spiral_rescue_active: bool = false

var _raw_throttle_flashes: bool = true
var _raw_limit_screenshake: bool = true
var _raw_screenshake_max_intensity: float = 1.5
var _raw_native_switches: bool = false


func _init() -> void:
	recompute_effective()


static func instance():
	if HOLDER.has("state") and HOLDER["state"] != null:
		return HOLDER["state"]
	var scr = load("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
	var created = scr.new()
	HOLDER["state"] = created
	return created


func capture_engine_snapshot(root_vp: Viewport, progress_data) -> void:
	if orig_snapshot_captured:
		return
	if root_vp != null and not orig_object_picking_captured:
		orig_object_picking = root_vp.physics_object_picking
		orig_object_picking_captured = true
	orig_vsync = OS.vsync_enabled
	if progress_data != null:
		var settings = progress_data.get("settings")
		if typeof(settings) == TYPE_DICTIONARY:
			if settings.has("visual_effects"):
				orig_visual_effects = bool(settings["visual_effects"])
			if settings.has("screenshake"):
				orig_screenshake = bool(settings["screenshake"])
	orig_snapshot_captured = true


func claim_phase() -> int:
	var phase: int = next_phase
	next_phase = (phase + 1) & 0x3FFFFFFF
	return phase


func apply_tier(new_tier: int) -> void:
	var clamped: int = int(clamp(new_tier, 0, 4))
	if tier == clamped:
		return
	tier = clamped
	tier_rev = (tier_rev + 1) & 0x3FFFFFFF
	recompute_effective()


func recompute_effective() -> void:
	var gov_particle: float = 1.0
	var gov_text_cap: int = 1000
	var gov_cache_extra: int = 0
	var gov_cull_extra: float = 0.0
	var gov_fx_per_frame: int = 0
	var gov_no_shake: bool = false
	var gov_no_flash: bool = false
	var gov_alive_cap: int = 100
	var gov_life_scale: float = 1.0
	var gov_sim_fps: int = 0
	var gov_burn_cap: int = 1000

	if adaptive_quality:
		match tier:
			0:
				gov_burn_cap = 24
			1:
				gov_particle = 0.85
				gov_text_cap = 30
				gov_cache_extra = 2
				gov_cull_extra = 200.0
				gov_alive_cap = 75
				gov_life_scale = 0.85
				gov_sim_fps = 0
				gov_burn_cap = 20
			2:
				gov_particle = 0.65
				gov_text_cap = 20
				gov_cache_extra = 4
				gov_cull_extra = 400.0
				gov_fx_per_frame = 24
				gov_alive_cap = 50
				gov_life_scale = 0.70
				gov_sim_fps = 30
				gov_burn_cap = 14
			3:
				gov_particle = 0.35
				gov_text_cap = 12
				gov_cache_extra = 6
				gov_cull_extra = 600.0
				gov_fx_per_frame = 10
				gov_alive_cap = 30
				gov_life_scale = 0.55
				gov_sim_fps = 24
				gov_burn_cap = 8
			4:
				gov_particle = 0.15
				gov_text_cap = 0
				gov_cache_extra = 8
				gov_cull_extra = 800.0
				gov_fx_per_frame = 4
				gov_no_shake = true
				gov_no_flash = true
				gov_alive_cap = 14
				gov_life_scale = 0.40
				gov_sim_fps = 20
				gov_burn_cap = 4

	var user_p_scale: float = clamp(particle_budget_scale, 0.05, 1.0)
	if stream_potato:
		user_p_scale = min(user_p_scale, 0.25)
		gov_alive_cap = int(min(gov_alive_cap, 16))
		gov_life_scale = min(gov_life_scale, 0.50)
		gov_burn_cap = int(min(gov_burn_cap, 4))
		if gov_fx_per_frame <= 0 or gov_fx_per_frame > 12:
			gov_fx_per_frame = 12
		if gov_sim_fps == 0 or gov_sim_fps > 24:
			gov_sim_fps = 24
	particle_scale = min(gov_particle, user_p_scale)

	# Static explosion smoke ratio (tier-independent so pooled _explosions never
	# change CPUParticles2D.amount across tiers or trigger multimesh_allocate).
	if scale_explosion_smoke:
		explode_smoke_scale = 0.25 if stream_potato else min(user_p_scale, 0.55)
	else:
		explode_smoke_scale = 1.0

	fx_sim_fps = gov_sim_fps if throttle_particle_sim_fps else 0

	if throttle_damage_numbers:
		var base_t_cap: int = 10 if stream_potato else int(max(1, max_floating_texts))
		text_cap = int(min(base_t_cap, gov_text_cap))
	else:
		text_cap = 100000

	var user_burn_cap: int = int(clamp(max_visible_burns, 0, 200))
	burn_vis_cap = int(min(user_burn_cap, gov_burn_cap))

	if cull_extra_margin != gov_cull_extra:
		cull_extra_margin = gov_cull_extra
		cam_frame = -1

	cache_extra_frames = gov_cache_extra
	fx_per_frame = gov_fx_per_frame
	fx_alive_cap = gov_alive_cap
	fx_lifetime_scale = gov_life_scale

	throttle_flashes = true if stream_potato else _raw_throttle_flashes
	disable_flash = true if stream_potato else gov_no_flash

	limit_screenshake = true if stream_potato else _raw_limit_screenshake
	screenshake_max_intensity = 0.0 if stream_potato else _raw_screenshake_max_intensity
	native_switches = true if stream_potato else _raw_native_switches
	disable_shake = true if stream_potato else gov_no_shake

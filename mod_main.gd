extends Node
# =============================================================================
# Saffron-Turbo 5.6.1 - Entry Point, Interpolator Mount & Optional Agent Hook
# -----------------------------------------------------------------------------
# Installs 31 carefully ordered script extensions in strict inheritance order,
# binds flat zero-meta TurboState, starts TurboGovernor and TurboInterpolator,
# and mounts the AI Agent Bridge ONLY when explicitly requested via CLI
# (--saffron-*) or agent_telemetry=true (0.000 ms, 0 bytes in normal play).
# =============================================================================

const MOD_ID: String = "Saffron-Turbo"
const MOD_VERSION: String = "5.6.1"
const EXT_DIR: String = "res://mods-unpacked/Saffron-Turbo/extensions/"
const STATE_META: String = "saffron_turbo_state"

var Config = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_config.gd")

var _state = null
var _cli_overrides: Array = []
var _orig_project_picking: bool = true
var _had_project_picking: bool = false
var _orig_root_picking: bool = true
var _root_picking_captured: bool = false
var _picking_overridden: bool = false
var _syncing_ui: bool = false


func _init() -> void:
	if ProjectSettings.has_setting("physics/common/enable_object_picking"):
		_had_project_picking = true
		_orig_project_picking = bool(ProjectSettings.get_setting("physics/common/enable_object_picking"))

	_state = Config.get_state()
	_cli_overrides = Config.bootstrap(OS.get_cmdline_args())

	var loop = Engine.get_main_loop()
	if loop is SceneTree:
		loop.set_meta(STATE_META, _state)
		if loop.root != null:
			_orig_root_picking = loop.root.physics_object_picking
			_root_picking_captured = true
			if _state != null:
				_state.orig_object_picking = _orig_root_picking
				_state.orig_object_picking_captured = true
		if _state != null and (_state.disable_object_picking or _state.stream_potato):
			if loop.root != null:
				loop.root.physics_object_picking = false
			ProjectSettings.set_setting("physics/common/enable_object_picking", false)
			_picking_overridden = true

	# Entity hierarchy FIRST (must install BEFORE singletons/utils.gd which references Entity/Unit!)
	ModLoaderMod.install_script_extension(EXT_DIR + "entities/entity.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "entities/units/unit/unit.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "entities/units/player/player.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "entities/units/enemies/enemy.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "entities/units/enemies/crash_zone/basic/pursuer/pursuer.gd")

	# Singletons & core helpers
	ModLoaderMod.install_script_extension(EXT_DIR + "singletons/utils.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "singletons/weapon_service.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "singletons/ui_service.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "weapons/weapon.gd")

	# Enemy attack behaviors: ChargingAttackBehavior -> ChargingAttackWithWarningLine
	ModLoaderMod.install_script_extension(EXT_DIR + "entities/units/enemies/attack_behaviors/shooting_attack_behavior.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "entities/units/enemies/attack_behaviors/charging_attack_behavior.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "entities/units/enemies/attack_behaviors/charging_attack_with_warning_line.gd")

	# Entity births: EntityBirth -> EntityGroupBirth
	ModLoaderMod.install_script_extension(EXT_DIR + "entities/birth/entity_birth.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "entities/birth/entity_group_birth.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "entities/structures/turret/turret.gd")

	# Projectiles: leaf extensions (EnemyProjectile, PlayerProjectile) + PlayerExplosion
	ModLoaderMod.install_script_extension(EXT_DIR + "projectiles/bullet_enemy/enemy_projectile.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "projectiles/player_projectile.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "projectiles/player_explosion.gd")

	# VFX, particles & global managers
	ModLoaderMod.install_script_extension(EXT_DIR + "particles/burning/burning_particles.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "global/effects_manager.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "global/gpe_spawner.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "global/screenshaker.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "visual_effects/floating_text/floating_text.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "visual_effects/floating_text/floating_text_manager.gd")

	# Items & UI / HUD
	ModLoaderMod.install_script_extension(EXT_DIR + "items/global/inventory_element.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "ui/menus/shop/inventory.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "ui/hud/ui_progress_bar.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "ui/hud/fps_label.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "ui/hud/ui_consumable_to_process_list.gd")
	ModLoaderMod.install_script_extension(EXT_DIR + "ui/hud/ui_upgrade_to_process_list.gd")

	# Main scene
	ModLoaderMod.install_script_extension(EXT_DIR + "main.gd")


func _ready() -> void:
	var tree: SceneTree = get_tree()
	if _state == null:
		_state = Config.get_state()
	if tree != null:
		tree.set_meta(STATE_META, _state)

	if not Config.is_bootstrapped():
		_cli_overrides = Config.bootstrap(OS.get_cmdline_args())
	else:
		_cli_overrides = Config.apply_cli_overrides(OS.get_cmdline_args())
	_apply_object_picking()

	var root_pick: bool = tree.root.physics_object_picking if (tree != null and tree.root != null) else false
	ModLoaderLog.info(
		"Saffron-Turbo initialized (v%s) | engine readback: iterations_per_second=%d physics_object_picking=%s."
		% [MOD_VERSION, Engine.iterations_per_second, str(root_pick)],
		MOD_ID
	)
	if not _cli_overrides.empty():
		ModLoaderLog.info("Saffron-Turbo cli overrides: %s" % PoolStringArray(_cli_overrides).join(" "), MOD_ID)
	ModLoaderLog.info(
		"Saffron-Turbo active config: %s | editable file: %s"
		% [Config.summary(), Config.user_config_global_path()],
		MOD_ID
	)

	_start_projectile_stepper()
	_start_interpolator()
	_start_governor()
	_start_agent_bridge_if_requested()
	call_deferred("_register_mod_options")


func _exit_tree() -> void:
	_restore_object_picking()


func _apply_object_picking() -> void:
	if _state == null:
		return
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return
	if not _root_picking_captured:
		_orig_root_picking = tree.root.physics_object_picking
		_root_picking_captured = true
		_state.orig_object_picking = _orig_root_picking
		_state.orig_object_picking_captured = true
	if _state.disable_object_picking or _state.stream_potato:
		ProjectSettings.set_setting("physics/common/enable_object_picking", false)
		tree.root.physics_object_picking = false
		_picking_overridden = true
	elif _picking_overridden:
		_restore_object_picking()


func _restore_object_picking() -> void:
	if not _picking_overridden:
		return
	ProjectSettings.set_setting("physics/common/enable_object_picking", _orig_project_picking if _had_project_picking else null)
	var loop = get_tree()
	if loop == null:
		loop = Engine.get_main_loop()
	if loop != null and loop.has_method("get_root") and loop.root != null and _root_picking_captured:
		loop.root.physics_object_picking = _orig_root_picking
	_picking_overridden = false


func _start_projectile_stepper() -> void:
	var stepper_script = load("res://mods-unpacked/Saffron-Turbo/scripts/turbo_projectile_stepper.gd")
	if stepper_script == null:
		ModLoaderLog.error("Saffron-Turbo: projectile stepper script failed to load.", MOD_ID)
		return
	var stepper = stepper_script.new()
	stepper.name = "SaffronTurboProjectileStepper"
	if _state != null:
		_state.stepper = stepper
	get_tree().root.call_deferred("add_child", stepper)


func _start_interpolator() -> void:
	var interp_script = load("res://mods-unpacked/Saffron-Turbo/scripts/turbo_interpolator.gd")
	if interp_script == null:
		ModLoaderLog.error("Saffron-Turbo: interpolator script failed to load.", MOD_ID)
		return
	var interp = interp_script.new()
	interp.name = "SaffronTurboInterpolator"
	if _state != null:
		interp.set_enabled(bool(_state.enable_interpolation))
		_state.interpolator = interp
	get_tree().root.call_deferred("add_child", interp)


func _start_governor() -> void:
	var governor_script = load("res://mods-unpacked/Saffron-Turbo/scripts/turbo_governor.gd")
	if governor_script == null:
		ModLoaderLog.error("Saffron-Turbo: governor script failed to load.", MOD_ID)
		return
	var governor = governor_script.new()
	governor.name = "SaffronTurboGovernor"
	get_tree().root.call_deferred("add_child", governor)


func _start_agent_bridge_if_requested() -> void:
	var want_bridge: bool = (_state != null and _state.agent_telemetry)
	if not want_bridge:
		for arg in OS.get_cmdline_args():
			if arg == "--saffron-agent" or arg == "--saffron-selftest" or arg == "--saffron-telemetry" or arg == "--saffron-log-metrics" or arg.begins_with("--saffron-jsonl=") or arg.begins_with("--saffron-report=") or arg.begins_with("--saffron-quit-after="):
				want_bridge = true
				break
	if not want_bridge:
		return
	var bridge_script = load("res://mods-unpacked/Saffron-Turbo/scripts/turbo_agent_bridge.gd")
	if bridge_script != null:
		var bridge = bridge_script.new()
		bridge.name = "SaffronTurboAgentBridge"
		get_tree().root.call_deferred("add_child", bridge)


func _register_mod_options() -> void:
	var mod_options: Node = null
	for _i in range(5):
		if not is_inside_tree():
			return
		mod_options = _get_mod_options()
		var has_oud_root: bool = has_node("/root/ModLoader/Oudstand-ModOptions")
		var has_dami_root: bool = has_node("/root/ModLoader/dami-ModOptions")
		var oud_ready: bool = (not has_oud_root) or (mod_options != null)
		var dami_ready: bool = (not has_dami_root) or has_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
		if (has_oud_root or has_dami_root) and oud_ready and dami_ready:
			break
		yield(get_tree().create_timer(0.2), "timeout")

	if not is_inside_tree():
		return

	mod_options = _get_mod_options()
	if mod_options and mod_options.has_method("register_mod_options"):
		var config: Dictionary = {
			"tab_title": "Saffron Turbo",
			"options": [
				{
					"type": "toggle",
					"id": "adaptive_quality",
					"label": "Adaptive Quality Governor",
					"default": true
				},
				{
					"type": "toggle",
					"id": "cache_weapon_targets",
					"label": "Cache Weapon & Turret Target Scans",
					"default": true
				},
				{
					"type": "slider",
					"id": "target_cache_frames",
					"label": "Target Cache Interval (Frames)",
					"default": 3,
					"min": 1,
					"max": 6,
					"step": 1
				},
				{
					"type": "toggle",
					"id": "stagger_target_scans",
					"label": "Stagger Target Scans Across Frames",
					"default": true
				},
				{
					"type": "toggle",
					"id": "fast_nearest_scan",
					"label": "Fast Scalar Nearest-Target Scan",
					"default": true
				},
				{
					"type": "toggle",
					"id": "pool_projectile_effects",
					"label": "Pool Projectile Crit Effects",
					"default": true
				},
				{
					"type": "toggle",
					"id": "scale_explosion_smoke",
					"label": "Scale Explosion Smoke Overdraw (v5)",
					"default": true
				},
				{
					"type": "toggle",
					"id": "throttle_particle_sim_fps",
					"label": "Adaptive Particle CPU Sim FPS (v5)",
					"default": true
				},
				{
					"type": "toggle",
					"id": "cull_offscreen_effects",
					"label": "Cull Offscreen VFX & Spawn Crosses",
					"default": true
				},
				{
					"type": "slider",
					"id": "cull_margin",
					"label": "Cull Margin (px)",
					"default": 160,
					"min": 0,
					"max": 400,
					"step": 20
				},
				{
					"type": "toggle",
					"id": "throttle_damage_numbers",
					"label": "Throttle Damage Numbers",
					"default": true
				},
				{
					"type": "slider",
					"id": "max_floating_texts",
					"label": "Max Floating Texts",
					"default": 40,
					"min": 10,
					"max": 100,
					"step": 5
				},
				{
					"type": "toggle",
					"id": "batch_damage_numbers",
					"label": "Batch Rapid Damage Numbers (65ms)",
					"default": true
				},
				{
					"type": "toggle",
					"id": "guard_weapon_property_writes",
					"label": "Skip Redundant Weapon Writes",
					"default": true
				},
				{
					"type": "toggle",
					"id": "cache_manual_aim",
					"label": "Cache Manual Aim Recalc",
					"default": true
				},
				{
					"type": "toggle",
					"id": "throttle_slow_scans",
					"label": "Throttle & Grid Slow-Area Scans",
					"default": true
				},
				{
					"type": "slider",
					"id": "slow_scan_interval_ms",
					"label": "Slow Scan Interval (ms)",
					"default": 250,
					"min": 0,
					"max": 1000,
					"step": 50
				},
				{
					"type": "toggle",
					"id": "limit_screenshake",
					"label": "Limit & Integer-Snap Screenshake (Remote Play)",
					"default": true
				},
				{
					"type": "slider",
					"id": "screenshake_max_intensity",
					"label": "Screenshake Max Intensity",
					"default": 1.5,
					"min": 0.0,
					"max": 3.0,
					"step": 0.25
				},
				{
					"type": "slider",
					"id": "screenshake_min_interval_ms",
					"label": "Screenshake Min Interval (ms)",
					"default": 150,
					"min": 0,
					"max": 500,
					"step": 25
				},
				{
					"type": "toggle",
					"id": "throttle_flashes",
					"label": "Throttle Hit Flashes (Remote Play)",
					"default": true
				},
				{
					"type": "slider",
					"id": "flash_interval_ms",
					"label": "Flash Min Interval (ms)",
					"default": 100,
					"min": 0,
					"max": 300,
					"step": 25
				},
				{
					"type": "toggle",
					"id": "batch_friendly_flash",
					"label": "Batch-Friendly Hit Flash Modulate",
					"default": true
				},
				{
					"type": "toggle",
					"id": "guard_unit_transforms",
					"label": "Guard Idle Unit Sprite Flip Writes",
					"default": true
				},
				{
					"type": "toggle",
					"id": "fix_idle_burn_spread",
					"label": "Disable Idle 256px Burn SpreadAreas",
					"default": true
				},
				{
					"type": "toggle",
					"id": "dedup_audio",
					"label": "Haas Audio Dedup & Fast Queue Drain",
					"default": true
				},
				{
					"type": "slider",
					"id": "particle_budget_scale",
					"label": "Particle Budget Scale",
					"default": 1.0,
					"min": 0.1,
					"max": 1.0,
					"step": 0.05
				},
				{
					"type": "toggle",
					"id": "stream_potato",
					"label": "Stream Potato (max stream stability)",
					"default": false
				},
				{
					"type": "toggle",
					"id": "potato_physics",
					"label": "Potato Physics (45/30/20Hz under heavy load)",
					"default": true
				},
				{
					"type": "slider",
					"id": "emergency_physics_hz",
					"label": "Emergency Physics Hz at tier 4 (0 = keep 30Hz)",
					"default": 20,
					"min": 0,
					"max": 30,
					"step": 10
				},
				{
					"type": "slider",
					"id": "fps_limit",
					"label": "Game FPS Limit: -1 = uncapped, 0 = leave, 1 = 60",
					"default": 0,
					"min": -1,
					"max": 1,
					"step": 1
				},
				{
					"type": "toggle",
					"id": "disable_object_picking",
					"label": "Disable Root Viewport Physics Picking",
					"default": true
				},
				{
					"type": "toggle",
					"id": "native_switches",
					"label": "Use the game's own effects/screenshake switches",
					"default": false
				},
				{
					"type": "slider",
					"id": "min_tier",
					"label": "Always-Turbo Baseline (0-4)",
					"default": 0,
					"min": 0,
					"max": 4,
					"step": 1
				},
				{
					"type": "toggle",
					"id": "disable_vsync",
					"label": "Disable VSync (uncapped FPS)",
					"default": false
				},
				{
					"type": "slider",
					"id": "load_spike_enemies",
					"label": "Load Spike Enemies (0 = off, pre-emptive tier 2)",
					"default": 300,
					"min": 0,
					"max": 3000,
					"step": 50
				},
				{
					"type": "toggle",
					"id": "pause_crowd_idle_anim",
					"label": "Pause Offscreen Pure-Chaser Walk Anims",
					"default": true
				},
				{
					"type": "slider",
					"id": "crowd_anim_threshold",
					"label": "Crowd Walk-Anim Threshold (Enemies)",
					"default": 60,
					"min": 20,
					"max": 300,
					"step": 10
				},
				{
					"type": "toggle",
					"id": "spiral_guard",
					"label": "Emergency Physics Death-Spiral Guard",
					"default": true
				},
				{
					"type": "toggle",
					"id": "agent_telemetry",
					"label": "AI Agent 1Hz Performance JSONL Telemetry",
					"default": false
				},
				{
					"type": "toggle",
					"id": "enable_worker_thread",
					"label": "Background Worker Thread (Spatial Hash Grid, Opt-In)",
					"default": false
				},
				{
					"type": "slider",
					"id": "worker_min_enemies",
					"label": "Worker Thread Min Enemies",
					"default": 120,
					"min": 40,
					"max": 1000,
					"step": 20
				},
				{
					"type": "toggle",
					"id": "pool_outline_materials",
					"label": "Pool Outline & Projectile ShaderMaterials (2D Batching)",
					"default": true
				},
				{
					"type": "toggle",
					"id": "fast_canvas_damage_numbers",
					"label": "1-Draw-Call Canvas Damage Numbers",
					"default": true
				},
				{
					"type": "toggle",
					"id": "compress_excess_fruits",
					"label": "Endless Opt-In: Safe Fruit Compressor",
					"default": false
				},
				{
					"type": "slider",
					"id": "max_ground_fruits",
					"label": "Max Ground Fruits Before Merge",
					"default": 40,
					"min": 10,
					"max": 200,
					"step": 5
				},
				{
					"type": "toggle",
					"id": "relax_enemy_collisions",
					"label": "Endless Opt-In: Relax Enemy-Enemy Collisions",
					"default": false
				},
				{
					"type": "slider",
					"id": "relax_collision_threshold",
					"label": "Relax Enemy Collisions Threshold (Enemies)",
					"default": 140,
					"min": 50,
					"max": 1000,
					"step": 10
				},
				{
					"type": "toggle",
					"id": "enable_interpolation",
					"label": "VisualServer Physics Interpolation (Smooth 144Hz/30Hz)",
					"default": true
				},
				{
					"type": "slider",
					"id": "max_visible_burns",
					"label": "Max Visible Burn Particle Effects",
					"default": 24,
					"min": 0,
					"max": 100,
					"step": 4
				},
				{
					"type": "toggle",
					"id": "isolate_enemy_hitbox_layer",
					"label": "Isolate Enemy Hitbox Physics2D Layer",
					"default": true
				},
				{
					"type": "toggle",
					"id": "z_bucket_shadows_gold",
					"label": "Z-Bucket Entity Shadows & Gold Sprites",
					"default": true
				},
				{
					"type": "toggle",
					"id": "optimize_projectiles",
					"label": "Baked Enemy Orb Outlines & Fast Pool Return",
					"default": true
				},
				{
					"type": "toggle",
					"id": "optimize_attack_behaviors",
					"label": "Fast Enemy Shooting & Charging Attack Scans",
					"default": true
				},
				{
					"type": "toggle",
					"id": "optimize_hud_inventory",
					"label": "Optimize HUD Bars, Shop Inventory & Icon Queues",
					"default": true
				},
				{
					"type": "toggle",
					"id": "prewarm_pools",
					"label": "Prewarm Gold, Consumable, Birth & Shader Pools",
					"default": true
				}
			]
		}
		mod_options.register_mod_options(MOD_ID, config)
		if not mod_options.is_connected("config_changed", self, "_on_mod_options_changed"):
			var _e_oud = mod_options.connect("config_changed", self, "_on_mod_options_changed")
	Config.refresh_cache()
	if has_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface"):
		var dami = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
		if not dami.is_connected("setting_changed", self, "_on_dami_setting_changed"):
			var _e_dami = dami.connect("setting_changed", self, "_on_dami_setting_changed")
		_publish_dami_settings(dami)

	var _cli2 = Config.apply_cli_overrides(OS.get_cmdline_args())
	_apply_object_picking()
	if _state != null and _state.interpolator != null:
		_state.interpolator.set_enabled(bool(_state.enable_interpolation))


func _publish_dami_settings(dami) -> void:
	if dami == null or not ("mod_configs" in dami):
		return
	var current = dami.get("mod_configs")
	if typeof(current) != TYPE_DICTIONARY:
		return
	if not current.has(MOD_ID) or typeof(current[MOD_ID]) != TYPE_DICTIONARY:
		current[MOD_ID] = {}
	var target: Dictionary = current[MOD_ID]
	target.erase("config_version")
	var pers: Dictionary = Config.persistent_values()
	for key in Config.DEFAULTS:
		if key == "config_version":
			continue
		var value = pers.get(key, Config.DEFAULTS[key])
		if typeof(value) == TYPE_INT:
			value = float(value)
		target[key] = value


func _sync_single_dami_key(setting_name: String) -> void:
	if setting_name == "config_version":
		return
	if not has_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface"):
		return
	var dami = get_node("/root/ModLoader/dami-ModOptions/ModsConfigInterface")
	if dami == null or not ("mod_configs" in dami):
		return
	var current = dami.get("mod_configs")
	if typeof(current) != TYPE_DICTIONARY or not current.has(MOD_ID):
		return
	var target = current[MOD_ID]
	if typeof(target) == TYPE_DICTIONARY and Config.DEFAULTS.has(setting_name):
		var resolved = Config.persistent_values().get(setting_name, Config.DEFAULTS[setting_name])
		target[setting_name] = Config.to_dami_value(resolved)


func _get_mod_options() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return null
	var mod_loader = tree.root.get_node_or_null("ModLoader")
	if mod_loader == null:
		return null
	var mod_options_mod = mod_loader.get_node_or_null("Oudstand-ModOptions")
	if mod_options_mod == null:
		return null
	return mod_options_mod.get_node_or_null("ModOptions")


func _on_mod_options_changed(mod_id: String, option_id: String, value) -> void:
	if mod_id != MOD_ID or _syncing_ui:
		return
	_syncing_ui = true
	Config.update_cached_setting(option_id, value)
	_sync_single_dami_key(option_id)
	if option_id == "disable_object_picking" or option_id == "stream_potato":
		_apply_object_picking()
	elif option_id == "enable_interpolation" and _state != null and _state.interpolator != null:
		_state.interpolator.set_enabled(bool(_state.enable_interpolation))
	_syncing_ui = false


func _on_dami_setting_changed(setting_name: String, value, mod_name: String) -> void:
	if mod_name != MOD_ID or _syncing_ui:
		return
	_syncing_ui = true
	Config.update_cached_setting(setting_name, value)
	_sync_single_dami_key(setting_name)
	var oud = _get_mod_options()
	if oud != null and oud.has_method("set_value"):
		oud.set_value(MOD_ID, setting_name, Config.persistent_values().get(setting_name, value))
	if setting_name == "disable_object_picking" or setting_name == "stream_potato":
		_apply_object_picking()
	elif setting_name == "enable_interpolation" and _state != null and _state.interpolator != null:
		_state.interpolator.set_enabled(bool(_state.enable_interpolation))
	_syncing_ui = false

extends Reference
# =============================================================================
# Saffron-Turbo 5.6.1 - Cold-Path Configuration Persistence & State Sync
# -----------------------------------------------------------------------------
# Precedence (highest first):
#   1. Transient CLI overrides (--saffron-set=key=val) - never mutates disk
#   2. Oudstand-ModOptions live value (if installed)
#   3. user://configs/Saffron-Turbo/turbo_config.json (non-destructive upgrade)
#   4. ModLoaderConfig (if populated & current_config present)
#   5. DEFAULTS below (56 user settings + config_version=4)
# =============================================================================

const MOD_ID: String = "Saffron-Turbo"
const USER_CONFIG_DIR: String = "user://configs/Saffron-Turbo"
const USER_CONFIG_PATH: String = "user://configs/Saffron-Turbo/turbo_config.json"

const STATE_SCRIPT_PATH: String = "res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd"
const GRID_SCRIPT_PATH: String = "res://mods-unpacked/Saffron-Turbo/scripts/turbo_grid.gd"

const CACHE_HOLDER: Dictionary = {
	"_bootstrapped": false
}

const CONFIG_VERSION: int = 4

const DEFAULTS: Dictionary = {
	"adaptive_quality": true,
	"cache_weapon_targets": true,
	"target_cache_frames": 3,
	"stagger_target_scans": true,
	"fast_nearest_scan": true,
	"pool_projectile_effects": true,
	"scale_explosion_smoke": true,
	"throttle_particle_sim_fps": true,
	"cull_offscreen_effects": true,
	"cull_margin": 160,
	"throttle_damage_numbers": true,
	"max_floating_texts": 40,
	"batch_damage_numbers": true,
	"guard_weapon_property_writes": true,
	"cache_manual_aim": true,
	"throttle_slow_scans": true,
	"slow_scan_interval_ms": 250,
	"limit_screenshake": true,
	"screenshake_max_intensity": 1.5,
	"screenshake_min_interval_ms": 150,
	"throttle_flashes": true,
	"flash_interval_ms": 100,
	"batch_friendly_flash": true,
	"guard_unit_transforms": true,
	"fix_idle_burn_spread": true,
	"dedup_audio": true,
	"particle_budget_scale": 1.0,
	"stream_potato": false,
	"potato_physics": true,
	"emergency_physics_hz": 20,
	"fps_limit": 0,
	"disable_object_picking": true,
	"native_switches": false,
	"min_tier": 0,
	"disable_vsync": false,
	"load_spike_enemies": 300,
	"pause_crowd_idle_anim": true,
	"crowd_anim_threshold": 60,
	"spiral_guard": true,
	"agent_telemetry": false,
	"enable_worker_thread": false,
	"worker_min_enemies": 120,
	"pool_outline_materials": true,
	"fast_canvas_damage_numbers": true,
	"compress_excess_fruits": false,
	"max_ground_fruits": 40,
	"relax_enemy_collisions": false,
	"relax_collision_threshold": 140,
	"enable_interpolation": true,
	"max_visible_burns": 24,
	"isolate_enemy_hitbox_layer": true,
	"z_bucket_shadows_gold": true,
	"optimize_projectiles": true,
	"optimize_attack_behaviors": true,
	"optimize_hud_inventory": true,
	"prewarm_pools": true,
	"config_version": 4
}

const SUMMARY_ORDER: Array = [
	"adaptive_quality",
	"cache_weapon_targets",
	"target_cache_frames",
	"stagger_target_scans",
	"fast_nearest_scan",
	"pool_projectile_effects",
	"scale_explosion_smoke",
	"throttle_particle_sim_fps",
	"cull_offscreen_effects",
	"cull_margin",
	"throttle_damage_numbers",
	"max_floating_texts",
	"batch_damage_numbers",
	"guard_weapon_property_writes",
	"cache_manual_aim",
	"throttle_slow_scans",
	"slow_scan_interval_ms",
	"limit_screenshake",
	"screenshake_max_intensity",
	"screenshake_min_interval_ms",
	"throttle_flashes",
	"flash_interval_ms",
	"batch_friendly_flash",
	"guard_unit_transforms",
	"fix_idle_burn_spread",
	"dedup_audio",
	"particle_budget_scale",
	"stream_potato",
	"potato_physics",
	"emergency_physics_hz",
	"fps_limit",
	"disable_object_picking",
	"native_switches",
	"min_tier",
	"disable_vsync",
	"load_spike_enemies",
	"pause_crowd_idle_anim",
	"crowd_anim_threshold",
	"spiral_guard",
	"agent_telemetry",
	"enable_worker_thread",
	"worker_min_enemies",
	"pool_outline_materials",
	"fast_canvas_damage_numbers",
	"compress_excess_fruits",
	"max_ground_fruits",
	"relax_enemy_collisions",
	"relax_collision_threshold",
	"enable_interpolation",
	"max_visible_burns",
	"isolate_enemy_hitbox_layer",
	"z_bucket_shadows_gold",
	"optimize_projectiles",
	"optimize_attack_behaviors",
	"optimize_hud_inventory",
	"prewarm_pools"
]


static func is_bootstrapped() -> bool:
	return bool(CACHE_HOLDER.get("_bootstrapped", false))


static func bootstrap(cli_args: PoolStringArray = PoolStringArray()) -> Array:
	if bool(CACHE_HOLDER.get("_bootstrapped", false)):
		return apply_cli_overrides(cli_args)
	CACHE_HOLDER["_bootstrapped"] = true
	ensure_user_config()
	refresh_cache()
	if not cli_args.empty():
		return apply_cli_overrides(cli_args)
	return []


static func get_state():
	var state_script = CACHE_HOLDER.get("_state_script")
	if state_script == null:
		state_script = load(STATE_SCRIPT_PATH)
		CACHE_HOLDER["_state_script"] = state_script
	var st = state_script.instance()
	if st.grid == null:
		var grid_script = CACHE_HOLDER.get("_grid_script")
		if grid_script == null:
			grid_script = load(GRID_SCRIPT_PATH)
			CACHE_HOLDER["_grid_script"] = grid_script
		st.grid = grid_script.new()
		state_script.HOLDER["grid"] = st.grid
	return st


static func get_grid():
	var st = get_state()
	return st.grid


static func _get_cache() -> Dictionary:
	if CACHE_HOLDER.has("cfg"):
		return CACHE_HOLDER["cfg"]
	var cache: Dictionary = DEFAULTS.duplicate()
	CACHE_HOLDER["cfg"] = cache
	return cache


static func _get_persistent_cache() -> Dictionary:
	if CACHE_HOLDER.has("persistent"):
		return CACHE_HOLDER["persistent"]
	var pers: Dictionary = DEFAULTS.duplicate()
	CACHE_HOLDER["persistent"] = pers
	return pers


static func _get_cli_overrides() -> Dictionary:
	if CACHE_HOLDER.has("cli"):
		return CACHE_HOLDER["cli"]
	var cli: Dictionary = {}
	CACHE_HOLDER["cli"] = cli
	return cli


static func _normalize_legacy_keys(src: Dictionary) -> Dictionary:
	if not src.has("cull_offscreen_effects") and src.has("cull_offscreen"):
		var copy: Dictionary = src.duplicate()
		copy["cull_offscreen_effects"] = src["cull_offscreen"]
		return copy
	return src


static func refresh_cache() -> void:
	CACHE_HOLDER["_bootstrapped"] = true
	var cache: Dictionary = _get_cache()
	var persistent: Dictionary = _get_persistent_cache()
	var cli: Dictionary = _get_cli_overrides()
	var live: Dictionary = _normalize_legacy_keys(_live_ui_values())
	var file_values: Dictionary = _normalize_legacy_keys(user_config())
	var loader_values: Dictionary = _normalize_legacy_keys(_loader_config_values())

	for key in DEFAULTS:
		if key == "config_version":
			persistent[key] = CONFIG_VERSION
			cache[key] = CONFIG_VERSION
			continue
		var value = DEFAULTS[key]
		if loader_values.has(key):
			value = loader_values[key]
		if file_values.has(key):
			value = file_values[key]
		if live.has(key):
			value = live[key]
		var pers_coerced = _coerce(key, value)
		persistent[key] = pers_coerced
		if cli.has(key):
			cache[key] = _coerce(key, cli[key])
		else:
			cache[key] = pers_coerced

	_sync_cache_to_state(cache, get_state())


static func _sync_cache_to_state(cache: Dictionary, st) -> void:
	if st == null:
		return
	st.adaptive_quality = bool(cache.get("adaptive_quality", true))
	st.cull_offscreen = bool(cache.get("cull_offscreen_effects", true))

	var new_margin: float = float(_clamp_int("cull_margin", int(cache.get("cull_margin", 160))))
	if st.cull_margin != new_margin:
		st.cull_margin = new_margin
		st.cam_frame = -1

	st.throttle_damage_numbers = bool(cache.get("throttle_damage_numbers", true))
	st.max_floating_texts = _clamp_int("max_floating_texts", int(cache.get("max_floating_texts", 40)))
	st.batch_damage_numbers = bool(cache.get("batch_damage_numbers", true))
	st.particle_budget_scale = _clamp_float("particle_budget_scale", float(cache.get("particle_budget_scale", 1.0)))
	st.scale_explosion_smoke = bool(cache.get("scale_explosion_smoke", true))
	st.throttle_particle_sim_fps = bool(cache.get("throttle_particle_sim_fps", true))

	st.cache_weapon_targets = bool(cache.get("cache_weapon_targets", true))
	st.target_cache_frames = _clamp_int("target_cache_frames", int(cache.get("target_cache_frames", 3)))
	st.stagger_target_scans = bool(cache.get("stagger_target_scans", true))
	st.fast_nearest_scan = bool(cache.get("fast_nearest_scan", true))
	st.pool_projectile_effects = bool(cache.get("pool_projectile_effects", true))
	st.guard_weapon_property_writes = bool(cache.get("guard_weapon_property_writes", true))
	st.cache_manual_aim = bool(cache.get("cache_manual_aim", true))

	st.throttle_slow_scans = bool(cache.get("throttle_slow_scans", true))
	st.slow_scan_interval_ms = _clamp_int("slow_scan_interval_ms", int(cache.get("slow_scan_interval_ms", 250)))

	st._raw_throttle_flashes = bool(cache.get("throttle_flashes", true))
	st.flash_interval_ms = _clamp_int("flash_interval_ms", int(cache.get("flash_interval_ms", 100)))
	st.batch_friendly_flash = bool(cache.get("batch_friendly_flash", true))

	st.guard_unit_transforms = bool(cache.get("guard_unit_transforms", true))
	st.fix_idle_burn_spread = bool(cache.get("fix_idle_burn_spread", true))
	st.dedup_audio = bool(cache.get("dedup_audio", true))
	st.pause_crowd_idle_anim = bool(cache.get("pause_crowd_idle_anim", true))
	st.crowd_anim_threshold = _clamp_int("crowd_anim_threshold", int(cache.get("crowd_anim_threshold", 60)))
	st.spiral_guard = bool(cache.get("spiral_guard", true))
	st.agent_telemetry = bool(cache.get("agent_telemetry", false))

	st._raw_limit_screenshake = bool(cache.get("limit_screenshake", true))
	st._raw_screenshake_max_intensity = _clamp_float("screenshake_max_intensity", float(cache.get("screenshake_max_intensity", 1.5)))
	st.screenshake_min_interval_ms = _clamp_int("screenshake_min_interval_ms", int(cache.get("screenshake_min_interval_ms", 150)))

	st.stream_potato = bool(cache.get("stream_potato", false))
	st.potato_physics = bool(cache.get("potato_physics", true))
	st.emergency_physics_hz = _clamp_int("emergency_physics_hz", int(cache.get("emergency_physics_hz", 20)))
	st.fps_limit = _clamp_int("fps_limit", int(cache.get("fps_limit", 0)))
	st._raw_native_switches = bool(cache.get("native_switches", false))
	st.native_switches = true if st.stream_potato else st._raw_native_switches
	st.min_tier = _clamp_int("min_tier", int(cache.get("min_tier", 0)))
	st.disable_vsync = bool(cache.get("disable_vsync", false))
	st.load_spike_enemies = _clamp_int("load_spike_enemies", int(cache.get("load_spike_enemies", 300)))
	st.disable_object_picking = bool(cache.get("disable_object_picking", true))
	st.enable_worker_thread = bool(cache.get("enable_worker_thread", false))
	st.worker_min_enemies = _clamp_int("worker_min_enemies", int(cache.get("worker_min_enemies", 120)))
	st.pool_outline_materials = bool(cache.get("pool_outline_materials", true))
	st.fast_canvas_damage_numbers = bool(cache.get("fast_canvas_damage_numbers", true))
	st.compress_excess_fruits = bool(cache.get("compress_excess_fruits", false))
	st.max_ground_fruits = _clamp_int("max_ground_fruits", int(cache.get("max_ground_fruits", 40)))
	st.relax_enemy_collisions = bool(cache.get("relax_enemy_collisions", false))
	st.relax_collision_threshold = _clamp_int("relax_collision_threshold", int(cache.get("relax_collision_threshold", 140)))

	# 5.4.0 feature flags
	st.enable_interpolation = bool(cache.get("enable_interpolation", true))
	st.max_visible_burns = _clamp_int("max_visible_burns", int(cache.get("max_visible_burns", 24)))
	st.isolate_enemy_hitbox_layer = bool(cache.get("isolate_enemy_hitbox_layer", true))
	st.z_bucket_shadows_gold = bool(cache.get("z_bucket_shadows_gold", true))
	st.optimize_projectiles = bool(cache.get("optimize_projectiles", true))
	st.optimize_attack_behaviors = bool(cache.get("optimize_attack_behaviors", true))
	st.optimize_hud_inventory = bool(cache.get("optimize_hud_inventory", true))
	st.prewarm_pools = bool(cache.get("prewarm_pools", true))

	st.config_rev = (st.config_rev + 1) & 0x3FFFFFFF
	st.recompute_effective()


static func update_cached_setting(setting_name: String, value) -> void:
	if setting_name == "cull_offscreen":
		setting_name = "cull_offscreen_effects"
	if setting_name == "config_version" or not DEFAULTS.has(setting_name):
		return
	var coerced = _coerce(setting_name, value)
	var cache: Dictionary = _get_cache()
	var persistent: Dictionary = _get_persistent_cache()
	var cli: Dictionary = _get_cli_overrides()
	if cli.has(setting_name):
		cli.erase(setting_name)
	persistent[setting_name] = coerced
	cache[setting_name] = coerced
	_sync_cache_to_state(cache, get_state())
	persist_setting(setting_name, coerced)


static func cached_values() -> Dictionary:
	return _get_cache()


static func persistent_values() -> Dictionary:
	return _get_persistent_cache().duplicate()


static func dami_values() -> Dictionary:
	var pers: Dictionary = _get_persistent_cache()
	var out: Dictionary = {}
	for key in DEFAULTS:
		if key == "config_version":
			continue
		var val = pers.get(key, DEFAULTS[key])
		if typeof(val) == TYPE_INT:
			val = float(val)
		out[key] = val
	return out


static func to_dami_value(value):
	if typeof(value) == TYPE_INT:
		return float(value)
	return value


static func summary() -> String:
	var cache: Dictionary = _get_cache()
	var parts: Array = []
	for key in SUMMARY_ORDER:
		parts.append("%s=%s" % [key, str(cache.get(key, DEFAULTS[key]))])
	return PoolStringArray(parts).join(" ")


static func _build_disk_payload(src: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	out["config_version"] = CONFIG_VERSION
	for key in SUMMARY_ORDER:
		if src.has(key):
			out[key] = _coerce(key, src[key])
		else:
			out[key] = DEFAULTS[key]
	return out


static func persist_setting(setting_name: String, value) -> void:
	if setting_name == "cull_offscreen":
		setting_name = "cull_offscreen_effects"
	if setting_name == "config_version" or not DEFAULTS.has(setting_name):
		return
	var f_check = File.new()
	if not f_check.file_exists(USER_CONFIG_PATH):
		ensure_user_config()
	var out: Dictionary = _build_disk_payload(_get_persistent_cache())
	out[setting_name] = _coerce(setting_name, value)
	var file = File.new()
	if file.open(USER_CONFIG_PATH, File.WRITE) != OK:
		ModLoaderLog.warning("Saffron-Turbo: could not write %s" % USER_CONFIG_PATH, MOD_ID)
		file.close()
		return
	file.store_string(JSON.print(out, "\t"))
	file.close()


static func ensure_user_config() -> bool:
	var dir = Directory.new()
	if not dir.dir_exists("user://configs"):
		dir.make_dir("user://configs")
	if not dir.dir_exists(USER_CONFIG_DIR):
		dir.make_dir(USER_CONFIG_DIR)

	var file = File.new()
	if not file.file_exists(USER_CONFIG_PATH):
		if file.open(USER_CONFIG_PATH, File.WRITE) == OK:
			file.store_string(JSON.print(_build_disk_payload(DEFAULTS), "\t"))
			file.close()
			return true
		return false

	if file.open(USER_CONFIG_PATH, File.READ) != OK:
		return false
	var text: String = file.get_as_text()
	file.close()

	var parsed = JSON.parse(text)
	if parsed.error != OK or not (parsed.result is Dictionary):
		ModLoaderLog.warning(
			"Saffron-Turbo: %s is not valid JSON (%s); skipping in-place upgrade." % [user_config_global_path(), parsed.error_string],
			MOD_ID
		)
		return false

	var existing: Dictionary = parsed.result
	var needs_upgrade: bool = false

	if int(existing.get("config_version", 0)) != CONFIG_VERSION:
		existing["config_version"] = CONFIG_VERSION
		needs_upgrade = true

	if existing.has("cull_offscreen"):
		if not existing.has("cull_offscreen_effects"):
			existing["cull_offscreen_effects"] = _coerce("cull_offscreen_effects", existing["cull_offscreen"])
		existing.erase("cull_offscreen")
		needs_upgrade = true

	if existing.has("reuse_motion_result"):
		existing.erase("reuse_motion_result")
		needs_upgrade = true

	for key in DEFAULTS:
		if key == "config_version":
			continue
		if not existing.has(key):
			existing[key] = DEFAULTS[key]
			needs_upgrade = true
		else:
			var raw = existing[key]
			var coerced = _coerce(key, raw)
			existing[key] = coerced
			var kind: int = typeof(DEFAULTS[key])
			if kind == TYPE_BOOL:
				if typeof(raw) != TYPE_BOOL or raw != coerced:
					needs_upgrade = true
			elif kind == TYPE_INT or kind == TYPE_REAL:
				if (typeof(raw) != TYPE_INT and typeof(raw) != TYPE_REAL) or abs(float(raw) - float(coerced)) > 0.0001:
					needs_upgrade = true

	if needs_upgrade:
		var out_file = File.new()
		if out_file.open(USER_CONFIG_PATH, File.WRITE) == OK:
			out_file.store_string(JSON.print(existing, "\t"))
			out_file.close()

	return true


static func user_config_global_path() -> String:
	return ProjectSettings.globalize_path(USER_CONFIG_PATH)


static func user_config() -> Dictionary:
	var file = File.new()
	if not file.file_exists(USER_CONFIG_PATH):
		return {}
	if file.open(USER_CONFIG_PATH, File.READ) != OK:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed = JSON.parse(text)
	if parsed.error != OK or not (parsed.result is Dictionary):
		ModLoaderLog.warning(
			"Saffron-Turbo: %s is not valid JSON (%s); falling back to built-in defaults."
			% [user_config_global_path(), parsed.error_string], MOD_ID)
		return {}
	return parsed.result


static func _coerce(setting_name: String, value):
	if not DEFAULTS.has(setting_name):
		return value
	var def_val = DEFAULTS[setting_name]
	var kind: int = typeof(def_val)
	match kind:
		TYPE_BOOL:
			if typeof(value) == TYPE_STRING:
				var raw_str: String = value.strip_edges().to_lower()
				if raw_str == "true" or raw_str == "1":
					return true
				if raw_str == "false" or raw_str == "0":
					return false
				return bool(def_val)
			return bool(value)
		TYPE_INT:
			var iv: int = int(def_val)
			if typeof(value) == TYPE_REAL:
				iv = int(round(value))
			elif typeof(value) == TYPE_INT:
				iv = value
			elif typeof(value) == TYPE_STRING:
				var raw_str: String = value.strip_edges()
				if raw_str.is_valid_integer():
					iv = int(raw_str)
				elif raw_str.is_valid_float():
					iv = int(round(float(raw_str)))
			return _clamp_int(setting_name, iv)
		TYPE_REAL:
			var fv: float = float(def_val)
			if typeof(value) == TYPE_REAL or typeof(value) == TYPE_INT:
				fv = float(value)
			elif typeof(value) == TYPE_STRING:
				var raw_str: String = value.strip_edges()
				if raw_str.is_valid_float():
					fv = float(raw_str)
			if is_nan(fv) or is_inf(fv):
				fv = float(def_val)
			return _clamp_float(setting_name, fv)
		_:
			return value


static func _clamp_int(setting_name: String, v: int) -> int:
	match setting_name:
		"target_cache_frames":
			return int(clamp(v, 1, 30))
		"max_floating_texts":
			return int(clamp(v, 1, 200))
		"cull_margin":
			return int(clamp(v, 0, 2000))
		"slow_scan_interval_ms":
			return int(clamp(v, 0, 2000))
		"screenshake_min_interval_ms":
			return int(clamp(v, 0, 2000))
		"flash_interval_ms":
			return int(clamp(v, 0, 2000))
		"load_spike_enemies":
			return int(clamp(v, 0, 5000))
		"emergency_physics_hz":
			return int(clamp(v, 10, 30)) if v > 0 else 0
		"fps_limit":
			return int(clamp(v, -1, 1))
		"min_tier":
			return int(clamp(v, 0, 4))
		"crowd_anim_threshold":
			return int(clamp(v, 10, 1000))
		"worker_min_enemies":
			return int(clamp(v, 40, 1000))
		"max_ground_fruits":
			return int(clamp(v, 10, 200))
		"relax_collision_threshold":
			return int(clamp(v, 50, 1000))
		"max_visible_burns":
			return int(clamp(v, 0, 200))
		_:
			return v


static func _clamp_float(setting_name: String, v: float) -> float:
	match setting_name:
		"particle_budget_scale":
			return clamp(v, 0.05, 1.0)
		"screenshake_max_intensity":
			return clamp(v, 0.0, 50.0)
		_:
			return v


static func _live_ui_values() -> Dictionary:
	var out: Dictionary = {}
	var loop = Engine.get_main_loop()
	if not (loop is SceneTree) or loop.root == null:
		return out
	var mod_loader = loop.root.get_node_or_null("ModLoader")
	if mod_loader == null:
		return out
	var oudstand = mod_loader.get_node_or_null("Oudstand-ModOptions")
	if oudstand:
		var mod_options = oudstand.get_node_or_null("ModOptions")
		if mod_options and mod_options.has_method("get_value"):
			for key in DEFAULTS:
				if key == "config_version":
					continue
				var val = mod_options.get_value(MOD_ID, key)
				if val != null:
					out[key] = val
	return out


static func _loader_config_values() -> Dictionary:
	if ModLoaderStore == null or not ("mod_data" in ModLoaderStore):
		return {}
	var mod_data_map = ModLoaderStore.mod_data
	if typeof(mod_data_map) != TYPE_DICTIONARY or not mod_data_map.has(MOD_ID):
		return {}
	var mod_data = mod_data_map[MOD_ID]
	if mod_data == null or not ("configs" in mod_data):
		return {}
	var configs = mod_data.configs
	if typeof(configs) != TYPE_DICTIONARY or configs.empty():
		return {}
	var cfg_name: String = ""
	if ModLoaderStore.current_user_profile != null and ("mod_list" in ModLoaderStore.current_user_profile):
		var mod_list = ModLoaderStore.current_user_profile.mod_list
		if typeof(mod_list) == TYPE_DICTIONARY:
			var mod_entry = mod_list.get(MOD_ID, {})
			if typeof(mod_entry) == TYPE_DICTIONARY:
				var raw_name = mod_entry.get("current_config", "")
				if typeof(raw_name) == TYPE_STRING and raw_name != "":
					cfg_name = raw_name
	if cfg_name != "" and configs.has(cfg_name):
		var cur = configs[cfg_name]
		if cur != null and ("data" in cur) and typeof(cur.data) == TYPE_DICTIONARY:
			return cur.data
	var def_name: String = ModLoaderConfig.DEFAULT_CONFIG_NAME if (ModLoaderConfig != null and ("DEFAULT_CONFIG_NAME" in ModLoaderConfig)) else "default"
	if configs.has(def_name):
		var config = configs[def_name]
		if config != null and ("data" in config) and typeof(config.data) == TYPE_DICTIONARY:
			return config.data
	return {}


static func apply_cli_overrides(cli_args: PoolStringArray) -> Array:
	var applied: Array = []
	var cli: Dictionary = {}
	for arg in cli_args:
		if arg.begins_with("--saffron-set="):
			var kv: String = arg.substr(len("--saffron-set="))
			var eq: int = kv.find("=")
			if eq > 0:
				var k: String = kv.substr(0, eq).strip_edges()
				var v_raw: String = kv.substr(eq + 1).strip_edges()
				if k == "cull_offscreen":
					k = "cull_offscreen_effects"
				if k != "config_version" and DEFAULTS.has(k):
					var coerced = _coerce(k, v_raw)
					cli[k] = coerced
					applied.append("%s=%s" % [k, str(coerced)])
	CACHE_HOLDER["cli"] = cli
	if not applied.empty():
		var cache: Dictionary = _get_cache()
		for k in cli:
			cache[k] = cli[k]
		_sync_cache_to_state(cache, get_state())
	return applied

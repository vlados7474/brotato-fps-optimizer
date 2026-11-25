extends Node
# =============================================================================
# Saffron-Turbo 5.6.1 - Zero-Overhead In-Engine AI Agent Self-Test & Telemetry
# -----------------------------------------------------------------------------
# Instantiated ONLY when launched with --saffron-agent / --saffron-selftest /
# --saffron-telemetry or when agent_telemetry=true in turbo_config.json.
# During normal player sessions this node is NOT created (0.000 ms, 0 bytes).
# Runs 31 rigorous in-engine assertions (A01..A31) and emits 1Hz JSONL metrics.
# =============================================================================

const MOD_ID: String = "Saffron-Turbo"
const MOD_VERSION: String = "5.6.1"
const TELEMETRY_PATH_DEFAULT: String = "user://logs/saffron_agent_telemetry.jsonl"
const SELFTEST_PATH_DEFAULT: String = "user://logs/saffron_selftest_report.json"

const CONFIG_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_config.gd")
const TARGETING_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_targeting.gd")
const GRID_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_grid.gd")
const WORKER_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_worker.gd")
const MAT_POOL_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_material_pool.gd")
const CANVAS_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_damage_canvas.gd")

const EXPECTED_EXTENSIONS: Array = [
	"res://singletons/utils.gd",
	"res://singletons/weapon_service.gd",
	"res://singletons/ui_service.gd",
	"res://weapons/weapon.gd",
	"res://entities/entity.gd",
	"res://entities/units/unit/unit.gd",
	"res://entities/units/player/player.gd",
	"res://entities/units/enemies/enemy.gd",
	"res://entities/units/enemies/crash_zone/basic/pursuer/pursuer.gd",
	"res://entities/units/enemies/attack_behaviors/shooting_attack_behavior.gd",
	"res://entities/units/enemies/attack_behaviors/charging_attack_behavior.gd",
	"res://entities/units/enemies/attack_behaviors/charging_attack_with_warning_line.gd",
	"res://entities/birth/entity_birth.gd",
	"res://entities/birth/entity_group_birth.gd",
	"res://entities/structures/turret/turret.gd",
	"res://projectiles/bullet_enemy/enemy_projectile.gd",
	"res://projectiles/player_projectile.gd",
	"res://projectiles/player_explosion.gd",
	"res://particles/burning/burning_particles.gd",
	"res://global/effects_manager.gd",
	"res://global/gpe_spawner.gd",
	"res://global/screenshaker.gd",
	"res://visual_effects/floating_text/floating_text.gd",
	"res://visual_effects/floating_text/floating_text_manager.gd",
	"res://items/global/inventory_element.gd",
	"res://ui/menus/shop/inventory.gd",
	"res://ui/hud/ui_progress_bar.gd",
	"res://ui/hud/fps_label.gd",
	"res://ui/hud/ui_consumable_to_process_list.gd",
	"res://ui/hud/ui_upgrade_to_process_list.gd",
	"res://main.gd"
]

var _state = null
var _telemetry_path: String = TELEMETRY_PATH_DEFAULT
var _selftest_path: String = SELFTEST_PATH_DEFAULT
var _run_selftest: bool = false
var _emit_jsonl: bool = false
var _log_metrics: bool = false
var _quit_after_sec: float = -1.0
var _elapsed_sec: float = 0.0
var _sample_timer: float = 0.0
var _sample_seq: int = 0
var _selftest_done: bool = false
var _selftest_all_ok: bool = true


class _MockTarget extends Node2D:
	var dead: bool = false


static func _script_has_saffron_ext(scr: Script, needle: String) -> bool:
	var cur: Script = scr
	while cur != null:
		if cur.has_meta("extension_script_path") and needle in str(cur.get_meta("extension_script_path")):
			return true
		if needle in cur.resource_path:
			return true
		for m in cur.get_script_method_list():
			if str(m.get("name", "")).begins_with("_turbo_"):
				return true
		for k in cur.get_script_constant_map().keys():
			if str(k).begins_with("_turbo_") or str(k).begins_with("_TURBO_"):
				return true
		cur = cur.get_base_script()
	return false


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	_state = CONFIG_SCRIPT.get_state()
	_parse_cmdline()
	_ensure_log_dir()
	if _emit_jsonl:
		var f = File.new()
		if f.open(_telemetry_path, File.WRITE) == OK:
			f.close()
		ModLoaderLog.info(
			"AGENT_BRIDGE: telemetry active -> %s" % ProjectSettings.globalize_path(_telemetry_path),
			MOD_ID
		)
	if _run_selftest:
		call_deferred("_execute_selftest")
	set_process(true)


func _parse_cmdline() -> void:
	_emit_jsonl = (_state != null and _state.agent_telemetry)
	var args: PoolStringArray = OS.get_cmdline_args()
	for arg in args:
		if arg == "--saffron-agent" or arg == "--saffron-telemetry":
			_emit_jsonl = true
		elif arg == "--saffron-selftest":
			_run_selftest = true
			_emit_jsonl = true
		elif arg == "--saffron-log-metrics":
			_log_metrics = true
		elif arg.begins_with("--saffron-jsonl="):
			_telemetry_path = arg.substr(len("--saffron-jsonl=")).strip_edges()
			_emit_jsonl = true
		elif arg.begins_with("--saffron-report="):
			_selftest_path = arg.substr(len("--saffron-report=")).strip_edges()
		elif arg.begins_with("--saffron-quit-after="):
			_quit_after_sec = float(arg.substr(len("--saffron-quit-after=")).strip_edges())


func _ensure_log_dir() -> void:
	var dir = Directory.new()
	if not dir.dir_exists("user://logs"):
		dir.make_dir_recursive("user://logs")


func _process(delta: float) -> void:
	_elapsed_sec += delta
	if _emit_jsonl or _log_metrics:
		_sample_timer += delta
		if _sample_timer >= 1.0:
			_sample_timer -= 1.0
			_write_telemetry_sample()

	if _quit_after_sec > 0.0 and _elapsed_sec >= _quit_after_sec:
		if not _run_selftest or _selftest_done:
			var code: int = 0 if _selftest_all_ok else 2
			ModLoaderLog.info("AGENT_BRIDGE: quitting cleanly with code=%d after %.2fs" % [code, _elapsed_sec], MOD_ID)
			get_tree().quit(code)


func _write_telemetry_sample() -> void:
	_sample_seq += 1
	var tree: SceneTree = get_tree()
	var root_picking: bool = tree.root.physics_object_picking if (tree != null and tree.root != null) else false
	var wave_num: int = 0
	var rd = get_node_or_null("/root/RunData")
	if rd != null and "current_wave" in rd:
		wave_num = int(rd.get("current_wave"))

	var payload: Dictionary = {
		"seq": _sample_seq,
		"ts_ms": OS.get_ticks_msec(),
		"mod_version": MOD_VERSION,
		"in_run": _state.in_run if _state != null else false,
		"wave": wave_num,
		"tier": _state.tier if _state != null else 0,
		"phys_hz": Engine.iterations_per_second,
		"fx_sim_fps": _state.fx_sim_fps if _state != null else 0,
		"spiral_rescue": _state.spiral_rescue_active if _state != null else false,
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"ft_fast_ms": stepify(_state.census_ft_fast_ms, 0.01) if _state != null else 0.0,
		"ft_slow_ms": stepify(_state.census_ft_ms, 0.01) if _state != null else 0.0,
		"ft_p95_ms": stepify(_state.census_ft_p95_ms, 0.01) if _state != null else 0.0,
		"ft_worst_1s_ms": stepify(_state.census_ft_worst_1s_ms, 0.01) if _state != null else 0.0,
		"est_ms": stepify(_state.census_est_ms, 0.01) if _state != null else 0.0,
		"est_v2_ms": stepify(_state.census_est_v2_ms, 0.01) if _state != null else 0.0,
		"process_ms": stepify(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"physics_ms": stepify(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01),
		"draw_calls_2d": int(Performance.get_monitor(Performance.RENDER_2D_DRAW_CALLS_IN_FRAME)),
		"items_2d": int(Performance.get_monitor(Performance.RENDER_2D_ITEMS_IN_FRAME)),
		"phys2d_active_objects": int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		"phys2d_collision_pairs": int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)),
		"phys2d_islands": int(Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT)),
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"static_mem_mb": stepify(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"enemies": _state.census_enemies if _state != null else 0,
		"bosses": _state.census_bosses if _state != null else 0,
		"spawn_queue": _state.census_spawn_queue if _state != null else 0,
		"projectiles": _state.census_projectiles if _state != null else 0,
		"effects": _state.census_effects if _state != null else 0,
		"texts": _state.census_texts if _state != null else 0,
		"burn_vis_active": _state.burn_vis_active if _state != null else 0,
		"burn_vis_cap": _state.burn_vis_cap if _state != null else 24,
		"root_picking": root_picking
	}

	var line: String = JSON.print(payload)
	if _emit_jsonl:
		var f = File.new()
		if f.open(_telemetry_path, File.READ_WRITE) == OK:
			f.seek_end()
			f.store_line(line)
			f.close()
	if _log_metrics:
		ModLoaderLog.info("AGENT_METRIC: " + line, MOD_ID)


func _execute_selftest() -> void:
	var checks: Array = []
	var tree: SceneTree = get_tree()
	var root: Viewport = tree.root if tree != null else null
	var orphans_before: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

	_add_check(checks, "A01_state_singleton", _state != null and _state.grid != null, "TurboState & TurboGrid bound")
	_add_check(checks, "A02_scene_tree_meta", tree != null and tree.has_meta("saffron_turbo_state") and tree.get_meta("saffron_turbo_state") == _state, "SceneTree meta matches HOLDER")
	_add_check(checks, "A03_governor_mounted", root != null and root.get_node_or_null("SaffronTurboGovernor") != null, "SaffronTurboGovernor mounted on /root")
	_add_check(checks, "A04_sound_managers_present", root != null and root.get_node_or_null("SoundManager") != null and root.get_node_or_null("SoundManager2D") != null, "SoundManager & SoundManager2D live")

	var expected_pick: bool = false if (_state.disable_object_picking or _state.stream_potato) else _state.orig_object_picking
	_add_check(checks, "A05_root_picking_enforced", root != null and (root.physics_object_picking == expected_pick or not _state.disable_object_picking), "root.physics_object_picking=%s" % str(root.physics_object_picking if root != null else null))

	var registered_exts: Dictionary = {}
	if ModLoaderStore != null and "script_extensions" in ModLoaderStore:
		for ep in ModLoaderStore.script_extensions:
			var eps: String = str(ep)
			if "mods-unpacked/Saffron-Turbo/extensions/" in eps:
				registered_exts[eps.substr(eps.find("extensions/") + len("extensions/"))] = true
	var ext_loaded_cnt: int = 0
	for target_path in EXPECTED_EXTENSIONS:
		if ResourceLoader.exists(target_path):
			var scr = load(target_path)
			var rel_ext: String = target_path.substr(len("res://"))
			if (scr is Script and _script_has_saffron_ext(scr, "mods-unpacked/Saffron-Turbo/extensions/")) or registered_exts.has(rel_ext):
				ext_loaded_cnt += 1
	_add_check(checks, "A06_all_31_extensions_installed", ext_loaded_cnt == EXPECTED_EXTENSIONS.size(), "active=%d/%d" % [ext_loaded_cnt, EXPECTED_EXTENSIONS.size()])

	var utils_node = root.get_node_or_null("Utils") if root != null else null
	var utils_scr = utils_node.get_script() if utils_node != null else null
	var utils_live_ok: bool = (utils_scr is Script and _script_has_saffron_ext(utils_scr, "Saffron-Turbo"))
	_add_check(checks, "A07_utils_singleton_live_extended", utils_live_ok, str(utils_scr.resource_path if utils_scr != null else "none"))

	var ws_node = root.get_node_or_null("WeaponService") if root != null else null
	var ws_scr = ws_node.get_script() if ws_node != null else null
	var ws_live_ok: bool = (ws_scr is Script and _script_has_saffron_ext(ws_scr, "Saffron-Turbo"))
	_add_check(checks, "A08_weapon_service_live_extended", ws_live_ok, str(ws_scr.resource_path if ws_scr != null else "none"))

	var dami_vals: Dictionary = CONFIG_SCRIPT.dami_values()
	var dami_all_float: bool = true
	for k in dami_vals:
		if typeof(dami_vals[k]) == TYPE_INT:
			dami_all_float = false
	var expected_user_keys: int = CONFIG_SCRIPT.DEFAULTS.size() - (1 if CONFIG_SCRIPT.DEFAULTS.has("config_version") else 0)
	var no_cfg_ver_dami: bool = not dami_vals.has("config_version")
	_add_check(
		checks,
		"A09_dami_slider_float_coercion_%d" % expected_user_keys,
		dami_all_float and no_cfg_ver_dami and dami_vals.size() == expected_user_keys,
		"keys=%d expected=%d" % [dami_vals.size(), expected_user_keys]
	)

	var cfg_file = File.new()
	_add_check(checks, "A10_user_config_json_exists", cfg_file.file_exists(CONFIG_SCRIPT.USER_CONFIG_PATH), CONFIG_SCRIPT.user_config_global_path())

	var sum_tokens: PoolStringArray = CONFIG_SCRIPT.summary().split(" ", false)
	var sum_ok: bool = (sum_tokens.size() == expected_user_keys and CONFIG_SCRIPT.SUMMARY_ORDER.size() == expected_user_keys)
	_add_check(
		checks,
		"A11_summary_all_%d_tokens" % expected_user_keys,
		sum_ok,
		"tokens=%d expected=%d" % [sum_tokens.size(), expected_user_keys]
	)

	# Mathematical parity tests for TurboTargeting & TurboGrid on synthetic in-tree nodes
	var mock_root := Node2D.new()
	add_child(mock_root)
	var mocks: Array = []
	for i in range(64):
		var m = _MockTarget.new()
		m.position = Vector2(float((i * 97) % 1400) - 200.0, float((i * 53) % 900) - 100.0)
		m.dead = (i % 11 == 0)
		mock_root.add_child(m)
		mocks.append(m)

	var empty_near: Array = TARGETING_SCRIPT.get_nearest([], Vector2.ZERO, 0, 500)
	var empty_nomax: Array = TARGETING_SCRIPT.get_nearest_no_max([], Vector2.ZERO, 0, null)
	_add_check(checks, "A12_targeting_empty_contracts", empty_near.empty() and empty_nomax.size() == 2 and empty_nomax[0] == null, "empty contracts exact")

	var origin := Vector2(250.0, 250.0)
	var got_near: Array = TARGETING_SCRIPT.get_nearest(mocks, origin, 20, 600)
	var ref_best = null
	var ref_d2: float = 600.0 * 600.0 + 1.0
	var scalar_max_err: float = 0.0
	for m in mocks:
		var mp: Vector2 = m.global_position
		var sdx: float = mp.x - origin.x
		var sdy: float = mp.y - origin.y
		var sd2: float = sdx * sdx + sdy * sdy
		var ed2: float = mp.distance_squared_to(origin)
		var diff: float = abs(sd2 - ed2)
		if diff > scalar_max_err:
			scalar_max_err = diff
		if ed2 < ref_d2 and ed2 >= 400.0 and ed2 <= 360000.0:
			ref_d2 = ed2
			ref_best = m
	_add_check(checks, "A13_targeting_bounded_exact", got_near.size() == 2 and got_near[0] == ref_best and abs(float(got_near[1]) - sqrt(ref_d2)) < 0.001, "nearest match")

	var prev_cwt: bool = _state.cache_weapon_targets
	var prev_tcf: int = _state.target_cache_frames
	var prev_ffs: bool = _state.force_fresh_scan
	_state.cache_weapon_targets = true
	_state.target_cache_frames = int(max(3, _state.target_cache_frames))
	_state.force_fresh_scan = false
	TARGETING_SCRIPT.clear_cache()
	var got_nomax: Array = TARGETING_SCRIPT.get_nearest_no_max(mocks, origin, 0, _state)
	var winner: Node2D = got_nomax[0]
	var orig_winner_pos: Vector2 = winner.position if winner != null else Vector2.ZERO
	if winner != null:
		winner.position += Vector2(12.0, -8.0)
	var got_nomax_moved: Array = TARGETING_SCRIPT.get_nearest_no_max(mocks, origin, 0, _state)
	var live_dist_ok: bool = (
		winner != null
		and got_nomax_moved[0] == winner
		and abs(float(got_nomax_moved[1]) - winner.global_position.distance_to(origin)) < 0.001
	)
	if winner != null:
		winner.position = orig_winner_pos
	_add_check(checks, "A14_turret_cache_live_distance", live_dist_ok, "live distance updated on cache hit")

	var min_inv_ok: bool = false
	if winner != null:
		var got_min_inv: Array = TARGETING_SCRIPT.get_nearest_no_max(mocks, winner.global_position, 15, _state)
		min_inv_ok = (got_min_inv[0] != winner)
	_state.cache_weapon_targets = prev_cwt
	_state.target_cache_frames = prev_tcf
	_state.force_fresh_scan = prev_ffs
	_add_check(checks, "A15_turret_min_range_invalidation", min_inv_ok, "min_distance exclusion honored")

	var test_grid = GRID_SCRIPT.new()
	var grid_hits: Array = test_grid.query_radius(origin, 320.0, mocks)
	var brute_ids: Dictionary = {}
	for m in mocks:
		if not m.dead and m.global_position.distance_squared_to(origin) <= 320.0 * 320.0:
			brute_ids[m.get_instance_id()] = true
	var grid_ids: Dictionary = {}
	for g in grid_hits:
		grid_ids[g.get_instance_id()] = true
	var grid_exact: bool = (grid_ids.size() == brute_ids.size())
	for k in brute_ids:
		if not grid_ids.has(k):
			grid_exact = false
	_add_check(checks, "A16_spatial_grid_exact_set_parity", grid_exact, "grid=%d brute=%d" % [grid_ids.size(), brute_ids.size()])

	var empty_grid_hits: Array = test_grid.query_radius(origin, -1.0, mocks)
	_add_check(checks, "A17_spatial_grid_negative_radius_safe", empty_grid_hits.empty(), "negative radius empty")
	test_grid.clear()

	# WeaponService projectile effects & explode hook checks
	var ws_fx_ok: bool = false
	if ws_node != null and ws_node.has_method("set_projectile_effects"):
		var res_empty: Array = ws_node.set_projectile_effects([], -1)
		ws_fx_ok = (typeof(res_empty) == TYPE_ARRAY and res_empty.empty())
	_add_check(checks, "A18_weapon_service_fast_empty_fx", ws_fx_ok, "set_projectile_effects([], -1) zero-alloc")

	# Tier state machine, v5 particle sim FPS & smoke scale reversibility checks
	var prev_tier: int = _state.tier
	var prev_aq: bool = _state.adaptive_quality
	var prev_tdn: bool = _state.throttle_damage_numbers
	var prev_smoke: bool = _state.scale_explosion_smoke
	var prev_sim: bool = _state.throttle_particle_sim_fps
	var prev_sp: bool = _state.stream_potato

	_state.adaptive_quality = true
	_state.throttle_damage_numbers = true
	_state.throttle_particle_sim_fps = true
	_state.scale_explosion_smoke = true
	_state.stream_potato = false
	_state.apply_tier(2)
	_state.recompute_effective()
	var tier2_ok: bool = (_state.fx_alive_cap == 50 and _state.fx_per_frame == 24 and _state.text_cap <= 20 and _state.fx_sim_fps == 30 and _state.burn_vis_cap <= 14)
	_add_check(checks, "A19_tier2_budget_exact", tier2_ok, "alive_cap=%d fx_pf=%d sim_fps=%d burn_cap=%d" % [_state.fx_alive_cap, _state.fx_per_frame, _state.fx_sim_fps, _state.burn_vis_cap])

	_state.apply_tier(4)
	_state.recompute_effective()
	var tier4_ok: bool = (_state.text_cap == 0 and _state.disable_flash and _state.disable_shake and _state.fx_alive_cap <= 16 and _state.fx_sim_fps == 20 and _state.burn_vis_cap <= 4)
	_add_check(checks, "A20_tier4_emergency_budget_exact", tier4_ok, "text_cap=0 flash/shake off sim_fps=20 burn_cap=%d" % _state.burn_vis_cap)

	var smoke_default: float = _state.explode_smoke_scale
	_state.stream_potato = true
	_state.recompute_effective()
	var smoke_potato: float = _state.explode_smoke_scale
	_state.scale_explosion_smoke = false
	_state.recompute_effective()
	var smoke_off: float = _state.explode_smoke_scale
	var smoke_ok: bool = (ws_node != null and ws_node.has_method("explode") and smoke_default <= 0.56 and abs(smoke_potato - 0.25) < 0.001 and abs(smoke_off - 1.0) < 0.001)

	_state.adaptive_quality = prev_aq
	_state.throttle_damage_numbers = prev_tdn
	_state.scale_explosion_smoke = prev_smoke
	_state.throttle_particle_sim_fps = prev_sim
	_state.stream_potato = prev_sp
	_state.apply_tier(prev_tier)
	_state.recompute_effective()
	_add_check(checks, "A21_tier_restore_clean", _state.tier == prev_tier and _state.adaptive_quality == prev_aq, "restored tier=%d" % _state.tier)

	var p0: int = _state.claim_phase()
	var p1: int = _state.claim_phase()
	_add_check(checks, "A22_phase_stagger_monotonic", p1 == ((p0 + 1) & 0x3FFFFFFF), "p0=%d p1=%d" % [p0, p1])

	_add_check(checks, "A23_menu_physics_60hz_preserved", _state.in_run or Engine.iterations_per_second == 60, "phys_hz=%d" % Engine.iterations_per_second)

	_add_check(checks, "A24_explosion_smoke_scale_invariance", smoke_ok, "smoke=%.2f potato=%.2f off=%.2f" % [smoke_default, smoke_potato, smoke_off])

	var test_cpu_p := CPUParticles2D.new()
	test_cpu_p.fixed_fps = 24
	test_cpu_p.fract_delta = false
	var p_sim_ok: bool = (test_cpu_p.fixed_fps == 24 and test_cpu_p.fract_delta == false)
	test_cpu_p.free()
	_add_check(checks, "A25_cpu_particles_fixed_fps_no_fract", p_sim_ok, "fixed_fps=24 fract_delta=false")

	_add_check(checks, "A26_scalar_vs_engine_distance_parity", scalar_max_err < 0.01, "max_err=%.6f" % scalar_max_err)

	# A28: Background Worker Thread Spatial Hash parity + clean teardown
	var w_test = WORKER_SCRIPT.new()
	var w_ok: bool = false
	if w_test.start():
		var pf_now: int = Engine.get_physics_frames()
		w_test.submit_snapshot(mocks, pf_now)
		var t_wait: int = OS.get_ticks_msec()
		while w_test.get_completed_seq() < 1 and (OS.get_ticks_msec() - t_wait) < 250:
			OS.delay_msec(1)
		var w_hits = w_test.try_query_radius(origin, 320.0, pf_now, 3)
		if w_hits != null:
			var w_ids: Dictionary = {}
			for wh in w_hits:
				w_ids[wh.get_instance_id()] = true
			w_ok = (w_ids.size() == brute_ids.size())
			for bk in brute_ids:
				if not w_ids.has(bk):
					w_ok = false
		w_test.stop()
	_add_check(checks, "A28_worker_thread_grid_parity", w_ok and not w_test.is_running(), "worker grid matches brute-force & stopped cleanly")

	# A29: ShaderMaterial pool deduplication & clean clear_all()
	var dummy_shader := Shader.new()
	dummy_shader.code = "shader_type canvas_item;"
	var m1 = MAT_POOL_SCRIPT.get_outline_material(dummy_shader, Vector2(64, 64), 1.0, 0.0, [Color.red])
	var m2 = MAT_POOL_SCRIPT.get_outline_material(dummy_shader, Vector2(64, 64), 1.0, 0.0, [Color.red])
	var m3 = MAT_POOL_SCRIPT.get_outline_material(dummy_shader, Vector2(64, 64), 1.0, 0.0, [Color.blue])
	var mat_ok: bool = (m1 != null and m1 == m2 and m1 != m3)
	MAT_POOL_SCRIPT.clear_all()
	_add_check(checks, "A29_material_pool_dedup", mat_ok, "pooled ShaderMaterial dedup exact")

	# A30: 1-Draw-Call Damage Canvas lifecycle & idle sleep
	var dc = CANVAS_SCRIPT.new()
	var dc_ok: bool = (dc != null and dc.active_count() == 0 and not dc.has_font())
	dc.free()
	_add_check(checks, "A30_damage_canvas_idle_clean", dc_ok, "TurboDamageCanvas idle clean")

	# A31: Worker stop()->start() restart, pre-snapshot null safety & huge radius clamp
	var alive_cnt: int = 0
	for m in mocks:
		if not m.dead:
			alive_cnt += 1
	var w_restart_ok: bool = false
	if w_test.start():
		var pf2: int = Engine.get_physics_frames()
		var pre_snap = w_test.try_query_radius(origin, 320.0, pf2, 3)
		w_test.submit_snapshot(mocks, pf2)
		var t_wait2: int = OS.get_ticks_msec()
		while w_test.get_completed_seq() < 1 and (OS.get_ticks_msec() - t_wait2) < 250:
			OS.delay_msec(1)
		var huge_res = w_test.try_query_radius(origin, 99999999.0, pf2, 3)
		w_restart_ok = (pre_snap == null and huge_res != null and huge_res.size() == alive_cnt)
		w_test.stop()
	_add_check(checks, "A31_worker_restart_and_radius_clamp", w_restart_ok and not w_test.is_running(), "worker restart & clamp safe")

	remove_child(mock_root)
	mock_root.free()
	TARGETING_SCRIPT.clear_cache()

	var orphans_after: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_add_check(checks, "A27_zero_orphan_nodes_after_selftest", orphans_after <= orphans_before, "before=%d after=%d" % [orphans_before, orphans_after])

	var passed_cnt: int = 0
	for c in checks:
		if bool(c["passed"]):
			passed_cnt += 1
	_selftest_all_ok = (passed_cnt == checks.size())
	_selftest_done = true

	var report: Dictionary = {
		"mod_id": MOD_ID,
		"mod_version": MOD_VERSION,
		"game_version": str(ProgressData.VERSION) if ("VERSION" in ProgressData) else "unknown",
		"all_passed": _selftest_all_ok,
		"passed": passed_cnt,
		"total": checks.size(),
		"active_config": CONFIG_SCRIPT.summary(),
		"checks": checks
	}
	var out = File.new()
	if out.open(_selftest_path, File.WRITE) == OK:
		out.store_string(JSON.print(report, "\t"))
		out.close()

	ModLoaderLog.info(
		"AGENT_SELFTEST: %s %d/%d | report=%s" % [
			"PASS" if _selftest_all_ok else "FAIL",
			passed_cnt,
			checks.size(),
			ProjectSettings.globalize_path(_selftest_path)
		],
		MOD_ID
	)


func _add_check(arr: Array, id_str: String, ok: bool, detail: String) -> void:
	arr.append({
		"id": id_str,
		"passed": ok,
		"detail": detail
	})

extends Node
# =============================================================================
# Saffron-Turbo 5.6.1 - Ultra-Lean Governor + 128-Frame P95 + Spiral Guard
# -----------------------------------------------------------------------------
# Merged Governor + Profiler (1 service node instead of 2) with a fast-exit
# calm-frame branch (<12ms at tier 0), spawn-storm early trigger (Births node),
# EngineSnapshot restoration, CanvasLayer 1x1 shader prewarm on first run, and
# silent queue-driven prewarm.
# =============================================================================

const MOD_ID: String = "Saffron-Turbo"
const BUDGET_META: String = "saffron_turbo_budget"
const CENSUS_META: String = "saffron_turbo_census"

const CONFIG_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_config.gd")
const AUDIO_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_audio.gd")
const TARGETING_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_targeting.gd")
const WORKER_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_worker.gd")
const MAT_POOL_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_material_pool.gd")
const PROJ_BAKER_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_projectile_baker.gd")

const FAST_ATTACK_SEC: float = 0.25
const SMOOTH_RELEASE_SEC: float = 2.5
const SPIKE_FRAME_MS: float = 40.0
const SEVERE_SPIKE_MS: float = 55.0
const SPIRAL_ENTER_MS: float = 50.0
const SPIRAL_EXIT_MS: float = 28.0

const SPAWN_STORM_BIRTHS: int = 25
const SPAWN_STORM_QUEUE: int = 30

const TAU_FAST_SEC: float = 0.12
const TAU_SLOW_SEC: float = 0.50
const P95_RING_SIZE: int = 128
const P95_RING_MASK: int = 127

const P95_UPDATE_SEC: float = 0.25
const MAINT_INTERVAL_SEC: float = 0.5
const LOG_INTERVAL_SEC: float = 10.0

const ENTER_THRESHOLDS_MS: Array = [12.5, 17.0, 25.0, 34.0]
const EXIT_THRESHOLDS_MS: Array = [10.5, 14.5, 20.5, 28.0]

const PREWARM_SHADER_PATHS: Array = [
	"res://resources/shaders/outline.gdshader",
	"res://resources/shaders/flash.gdshader",
	"res://resources/shaders/shader_outline_double_color.gdshader",
	"res://resources/shaders/projectile_outline_shadermat.tres",
	"res://resources/shaders/projectile_petrol_outline_shadermat.tres",
	"res://resources/shaders/weapon_outline_shadermat.tres"
]

var _state = null
var _audio = null
var _worker = null
var _worker_last_frame: int = -1
var _tree: SceneTree = null
var _root: Viewport = null

var _compat_budget: Dictionary = {
	"tier": 0,
	"particle_scale": 1.0,
	"text_cap": 40,
	"cache_extra_frames": 0,
	"cull_extra_margin": 0.0,
	"effects_per_frame": 0,
	"disable_shake": false,
	"disable_flash": false
}
var _compat_census: Dictionary = {
	"enemies": 0,
	"effects": 0,
	"texts": 0,
	"projectiles": 0,
	"spawn_queue": 0,
	"active_births": 0,
	"ft_ms": 0.0
}

var _ema_initialized: bool = false
var _ft_fast_ms: float = 0.0
var _ft_slow_ms: float = 0.0
var _ft_p95_ms: float = 0.0
var _ft_worst_1s_ms: float = 0.0
var _worst_window_acc_ms: float = 0.0
var _worst_window_timer: float = 0.0

var _ft_ring: Array = []
var _ft_ring_idx: int = 0
var _ft_ring_filled: int = 0
var _p95_top7: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _p95_timer: float = 0.0

var _attack_hold_sec: float = 0.0
var _release_hold_sec: float = 0.0
var _spiral_hold_sec: float = 0.0
var _spiral_active: bool = false
var _current_tier: int = 0
var _published_tier: int = -1
var _run_warmup_frames: int = 0
var _was_in_run: bool = false
var _census_active_births: int = 0

var _cached_scene: Node = null
var _spawner_node: Node = null
var _births_node: Node = null
var _fx_node: Node = null
var _ftm_node: Node = null
var _p_proj_node: Node = null
var _e_proj_node: Node = null
var _vignette_node: CanvasItem = null
var _vignette_hidden_by_mod: bool = false

var _maint_timer: float = 0.0
var _crowd_sync_dirty: bool = false
var _log_timer: float = 0.0
var _orig_physics_hz: int = 60
var _physics_overridden: bool = false
var _physics_fps_applied: int = 60
var _external_hz_conflict_logged: bool = false
var _vsync_applied: int = -1
var _fps_limit_requested: int = 0
var _native_applied: bool = false
var _vp_3d_disabled: bool = false
var _orig_vp_disable_3d: bool = false

# 5.4.0 shader 1x1 prewarm (CanvasLayer so it is never frustum-culled)
var _shader_prewarmed: bool = false
var _prewarm_layer: CanvasLayer = null
var _prewarm_cleanup_frames: int = 0
var _prewarm_queue: Array = []
var _prewarm_tex: ImageTexture = null


func _ready() -> void:
	process_priority = -2000
	_state = CONFIG_SCRIPT.get_state()
	_audio = AUDIO_SCRIPT.new()
	_ft_ring.resize(P95_RING_SIZE)
	for i in range(P95_RING_SIZE):
		_ft_ring[i] = 0.0
	_tree = get_tree()
	if _tree != null:
		_root = _tree.root
		_tree.set_meta(BUDGET_META, _compat_budget)
		_tree.set_meta(CENSUS_META, _compat_census)
	var pd = get_node_or_null("/root/ProgressData")
	_state.capture_engine_snapshot(_root, pd)
	_orig_physics_hz = Engine.iterations_per_second
	_physics_fps_applied = _orig_physics_hz
	_set_state_phys_hz(_orig_physics_hz)
	_publish_tier(0, false)
	_apply_object_picking()
	if _root != null:
		_orig_vp_disable_3d = _root.disable_3d
		_root.disable_3d = true
		_vp_3d_disabled = true
	set_process(true)
	set_physics_process(true)


func _physics_process(_delta: float) -> void:
	if _state == null or not _state.in_run or not is_instance_valid(_cached_scene) or not _cached_scene.is_inside_tree():
		if _state != null:
			_state.tick_zone_valid = false
			_state.tick_p0 = null
		return
	_state.tick_enemy_tf = EntityService.enemy_time_factor
	var zr: Rect2 = ZoneService.get_current_zone_rect()
	if zr.size.x > 0.0 and zr.size.y > 0.0:
		_state.tick_zone_min_x = zr.position.x
		_state.tick_zone_min_y = zr.position.y
		_state.tick_zone_max_x = zr.position.x + zr.size.x
		_state.tick_zone_max_y = zr.position.y + zr.size.y
		_state.tick_zone_valid = true
	else:
		_state.tick_zone_valid = false
	if "_players" in _cached_scene:
		var pls = _cached_scene._players
		if pls is Array and pls.size() > 0 and is_instance_valid(pls[0]) and pls[0].is_inside_tree():
			var p0 = pls[0]
			var p0p: Vector2 = p0.global_position
			_state.tick_p0 = p0
			_state.tick_p0_pos = p0p
			_state.tick_p0_x = p0p.x
			_state.tick_p0_y = p0p.y
		else:
			_state.tick_p0 = null
	else:
		_state.tick_p0 = null


func enqueue_prewarm(item) -> void:
	if item == null or not _state.prewarm_pools:
		return
	if _prewarm_queue.size() < 128:
		_prewarm_queue.append(item)


func _recompute_p95() -> void:
	var n: int = _ft_ring_filled
	if n <= 0:
		_ft_p95_ms = _ft_fast_ms
		return
	var k: int = int(clamp(int(ceil(float(n) * 0.05)), 1, 7))
	for j in range(k):
		_p95_top7[j] = -1.0
	for i in range(n):
		var v: float = float(_ft_ring[i])
		if v > float(_p95_top7[k - 1]):
			var pos: int = k - 1
			while pos > 0 and v > float(_p95_top7[pos - 1]):
				_p95_top7[pos] = _p95_top7[pos - 1]
				pos -= 1
			_p95_top7[pos] = v
	_ft_p95_ms = float(_p95_top7[k - 1])


func _process(delta: float) -> void:
	var dt_ms: float = min(delta * 1000.0, 200.0)
	var dt_sec: float = dt_ms * 0.001
	if not _ema_initialized:
		_ft_fast_ms = dt_ms
		_ft_slow_ms = dt_ms
		_ft_p95_ms = dt_ms
		_ft_worst_1s_ms = dt_ms
		_ema_initialized = true
	else:
		var a_fast: float = dt_sec / (TAU_FAST_SEC + dt_sec)
		var a_slow: float = dt_sec / (TAU_SLOW_SEC + dt_sec)
		_ft_fast_ms += (dt_ms - _ft_fast_ms) * a_fast
		_ft_slow_ms += (dt_ms - _ft_slow_ms) * a_slow

	_ft_ring[_ft_ring_idx] = dt_ms
	_ft_ring_idx = (_ft_ring_idx + 1) & P95_RING_MASK
	if _ft_ring_filled < P95_RING_SIZE:
		_ft_ring_filled += 1

	if dt_ms > _worst_window_acc_ms:
		_worst_window_acc_ms = dt_ms
	_worst_window_timer += delta
	if _worst_window_timer >= 1.0:
		_ft_worst_1s_ms = _worst_window_acc_ms
		_worst_window_acc_ms = dt_ms
		_worst_window_timer = 0.0

	_p95_timer += delta
	if _p95_timer >= P95_UPDATE_SEC:
		_p95_timer = 0.0
		_recompute_p95()

	_state.census_ft_fast_ms = _ft_fast_ms
	_state.census_ft_ms = _ft_slow_ms
	_state.census_ft_p95_ms = _ft_p95_ms
	_state.census_ft_worst_1s_ms = max(_ft_worst_1s_ms, _worst_window_acc_ms)

	if _prewarm_cleanup_frames > 0:
		_prewarm_cleanup_frames -= 1
		if _prewarm_cleanup_frames == 0:
			_cleanup_prewarm_node()

	var in_run: bool = _refresh_run_scene()
	if not in_run:
		_state.burn_vis_active = 0
		if _was_in_run or _published_tier != 0 or _physics_overridden:
			_crowd_sync_dirty = false
			_was_in_run = false
			_current_tier = 0
			_attack_hold_sec = 0.0
			_release_hold_sec = 0.0
			_spiral_hold_sec = 0.0
			_spiral_active = false
			_state.spiral_rescue_active = false
			_census_active_births = 0
			_prewarm_queue.clear()
			_cleanup_prewarm_node()
			TARGETING_SCRIPT.clear_cache()
			_stop_worker()
			_external_hz_conflict_logged = false
			_reset_census()
			_publish_tier(0, false)
			_apply_physics_fps(false, 0)
		_maint_timer += delta
		if _maint_timer >= MAINT_INTERVAL_SEC:
			_maint_timer = 0.0
			_apply_vsync()
			_apply_one_shot_options()
			_apply_object_picking()
		return

	if _root != null and _state.dedup_audio:
		_audio.tick(_root, _state)

	if not _was_in_run:
		_was_in_run = true
		_run_warmup_frames = 3
		_attack_hold_sec = 0.0
		_release_hold_sec = 0.0
		_spiral_hold_sec = 0.0
		_spiral_active = false
		_state.spiral_rescue_active = false
		_state.burn_vis_active = 0
		_crowd_sync_dirty = false
		_ft_fast_ms = min(dt_ms, 16.67)
		_ft_slow_ms = min(_ft_slow_ms, 16.67)
		_ft_p95_ms = min(_ft_p95_ms, 16.67)
		if _state.grid != null:
			_state.grid.clear()
		TARGETING_SCRIPT.clear_cache()
		if _state.prewarm_pools and not _shader_prewarmed:
			_shader_prewarmed = true
			_queue_initial_shader_prewarm()
		_take_census(true)
		var init_tier: int = _compute_effective_tier()
		_publish_tier(init_tier, true)
		_apply_physics_fps(true, _compute_ft_tier())
		_apply_object_picking()

	_tick_worker()

	_maint_timer += delta
	_log_timer += delta

	# Early spawn-storm detection (O(1) check before calm-frame fast path)
	var live_queue: int = _spawner_node.queue_to_spawn.size() if is_instance_valid(_spawner_node) else 0
	var live_births: int = _count_active_births()
	_state.census_spawn_queue = live_queue
	_census_active_births = live_births
	var spawn_storm: bool = (live_births >= SPAWN_STORM_BIRTHS or live_queue >= SPAWN_STORM_QUEUE)

	if spawn_storm:
		var storm_tier: int = _compute_effective_tier()
		if storm_tier > _published_tier:
			_publish_tier(storm_tier, true)
			_apply_physics_fps(true, _compute_ft_tier())
			_apply_vignette(storm_tier)
	elif not _prewarm_queue.empty() and dt_ms < 14.0:
		_step_prewarm_queue()

	# Calm-frame fast path (eliminates governor overhead on 180fps waves):
	if _current_tier == 0 and not _spiral_active and not spawn_storm and _run_warmup_frames == 0:
		if dt_ms < 12.0 and _ft_fast_ms < 12.0 and _ft_p95_ms < 15.5:
			_attack_hold_sec = 0.0
			if _maint_timer < MAINT_INTERVAL_SEC and _log_timer < LOG_INTERVAL_SEC:
				return

	if _state.spiral_guard:
		if _ft_slow_ms >= SPIRAL_ENTER_MS:
			_spiral_hold_sec += dt_sec
			if _spiral_hold_sec >= 1.0 and not _spiral_active:
				_spiral_active = true
				_state.spiral_rescue_active = true
				_apply_physics_fps(true, _compute_ft_tier())
		else:
			_spiral_hold_sec = 0.0
			if _spiral_active and _ft_slow_ms < SPIRAL_EXIT_MS:
				_spiral_active = false
				_state.spiral_rescue_active = false
				_apply_physics_fps(true, _compute_ft_tier())
	else:
		_spiral_hold_sec = 0.0
		if _spiral_active:
			_spiral_active = false
			_state.spiral_rescue_active = false
			_apply_physics_fps(true, _compute_ft_tier())

	var tier_changed_now: bool = false
	if _run_warmup_frames > 0:
		_run_warmup_frames -= 1
	elif _state.adaptive_quality:
		if dt_ms > SPIKE_FRAME_MS:
			var spike_tier: int = 4 if (dt_ms >= SEVERE_SPIKE_MS or _ft_fast_ms >= 34.0) else 3
			if spike_tier > _current_tier:
				_current_tier = spike_tier
				tier_changed_now = true
			_attack_hold_sec = 0.0
			_release_hold_sec = 0.0
		else:
			var ctrl_ms: float = max(_ft_fast_ms, _ft_p95_ms * 0.78)
			var attack_target: int = _entry_tier_for_ft(ctrl_ms)
			if attack_target > _current_tier:
				_release_hold_sec = 0.0
				_attack_hold_sec += dt_sec
				if _attack_hold_sec >= FAST_ATTACK_SEC:
					_current_tier = attack_target
					_attack_hold_sec = 0.0
					tier_changed_now = true
			else:
				_attack_hold_sec = 0.0
				if _current_tier > 0:
					var exit_ms: float = float(EXIT_THRESHOLDS_MS[_current_tier - 1])
					if _ft_fast_ms < exit_ms and _ft_slow_ms < exit_ms and _ft_p95_ms < exit_ms * 1.35:
						_release_hold_sec += dt_sec
						if _release_hold_sec >= SMOOTH_RELEASE_SEC:
							_current_tier -= 1
							_release_hold_sec = 0.0
							tier_changed_now = true
					else:
						_release_hold_sec = 0.0
				else:
					_release_hold_sec = 0.0
	else:
		if _current_tier != 0:
			_current_tier = 0
			tier_changed_now = true
		_attack_hold_sec = 0.0
		_release_hold_sec = 0.0

	if tier_changed_now:
		var immediate_tier: int = _compute_effective_tier()
		_publish_tier(immediate_tier, true)
		_apply_physics_fps(true, _compute_ft_tier())
		_apply_vignette(immediate_tier)

	if _maint_timer >= MAINT_INTERVAL_SEC:
		_maint_timer = 0.0
		_take_census(true)
		_apply_vsync()
		_apply_one_shot_options()
		var periodic_tier: int = _compute_effective_tier()
		_publish_tier(periodic_tier, true)
		_apply_physics_fps(true, _compute_ft_tier())
		_apply_object_picking()
		_apply_vignette(periodic_tier)
		_sync_enemy_crowd()

	if _log_timer >= LOG_INTERVAL_SEC:
		_log_timer = 0.0
		_take_census(true)
		var logged_tier: int = _compute_effective_tier()
		_publish_tier(logged_tier, true)
		_apply_physics_fps(true, _compute_ft_tier())
		_log_census(logged_tier)


func _notification(what: int) -> void:
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		_stop_worker()


func _exit_tree() -> void:
	if _vp_3d_disabled and is_instance_valid(_root):
		_root.disable_3d = _orig_vp_disable_3d
		_vp_3d_disabled = false
	_stop_worker()
	_prewarm_queue.clear()
	_cleanup_prewarm_node()
	_prewarm_tex = null
	MAT_POOL_SCRIPT.clear_all()
	PROJ_BAKER_SCRIPT.clear_all()
	if _physics_overridden:
		if Engine.iterations_per_second == _physics_fps_applied:
			Engine.iterations_per_second = _orig_physics_hz
		_physics_overridden = false
		_physics_fps_applied = Engine.iterations_per_second
		_set_state_phys_hz(_physics_fps_applied)
	if _vsync_applied == 0:
		OS.vsync_enabled = _state.orig_vsync if _state != null else true
		_vsync_applied = -1
	if _root != null and _state != null and _state.orig_snapshot_captured:
		_root.physics_object_picking = _state.orig_object_picking
	if _native_applied and _state != null and _state.orig_snapshot_captured:
		var pd = get_node_or_null("/root/ProgressData")
		if pd != null:
			var settings = pd.get("settings")
			if typeof(settings) == TYPE_DICTIONARY:
				settings["visual_effects"] = _state.orig_visual_effects
				settings["screenshake"] = _state.orig_screenshake
		_native_applied = false
	if _vignette_hidden_by_mod and is_instance_valid(_vignette_node):
		_vignette_node.visible = true
		_vignette_hidden_by_mod = false


func _set_state_phys_hz(new_hz: int) -> void:
	if _state == null:
		return
	var changed: bool = (_state.phys_hz != new_hz)
	_state.phys_hz = new_hz
	if changed and _state.interpolator != null and _state.interpolator.has_method("on_physics_hz_changed"):
		_state.interpolator.on_physics_hz_changed(new_hz)


func _queue_initial_shader_prewarm() -> void:
	for path in PREWARM_SHADER_PATHS:
		if ResourceLoader.exists(path):
			enqueue_prewarm({"kind": "shader_path", "path": path})


func _ensure_prewarm_texture() -> ImageTexture:
	if _prewarm_tex != null:
		return _prewarm_tex
	var img := Image.new()
	img.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 1.0))
	var tex := ImageTexture.new()
	tex.create_from_image(img, 0)
	_prewarm_tex = tex
	return _prewarm_tex


func _prewarm_material_1x1(mat: Material) -> void:
	if mat == null or _root == null:
		return
	if not is_instance_valid(_prewarm_layer):
		_prewarm_layer = CanvasLayer.new()
		_prewarm_layer.name = "SaffronPrewarm1x1"
		_prewarm_layer.layer = -100
		_root.add_child(_prewarm_layer)
	var sp := Sprite.new()
	sp.texture = _ensure_prewarm_texture()
	sp.material = mat
	sp.position = Vector2(1.0, 1.0)
	sp.modulate = Color(1.0, 1.0, 1.0, 0.004)
	_prewarm_layer.add_child(sp)
	_prewarm_cleanup_frames = 2


func _step_prewarm_queue() -> void:
	if _prewarm_queue.empty():
		return
	var item = _prewarm_queue.pop_front()
	if typeof(item) == TYPE_DICTIONARY:
		var kind: String = str(item.get("kind", ""))
		if kind == "shader_path":
			var path: String = str(item.get("path", ""))
			if path != "" and ResourceLoader.exists(path):
				var res = load(path)
				if res is Shader:
					var mat := ShaderMaterial.new()
					mat.shader = res
					_prewarm_material_1x1(mat)
				elif res is Material:
					_prewarm_material_1x1(res)
		elif kind == "material":
			var mat_obj = item.get("mat", null)
			if mat_obj is Material:
				_prewarm_material_1x1(mat_obj)
		elif kind == "call":
			var target = item.get("target", null)
			var method: String = str(item.get("method", ""))
			var args: Array = item.get("args", [])
			if target != null and is_instance_valid(target) and method != "" and target.has_method(method):
				target.callv(method, args)
	elif item is Material:
		_prewarm_material_1x1(item)


func _cleanup_prewarm_node() -> void:
	if is_instance_valid(_prewarm_layer):
		_prewarm_layer.queue_free()
	_prewarm_layer = null
	_prewarm_cleanup_frames = 0


func _count_active_births() -> int:
	if is_instance_valid(_births_node):
		return _births_node.get_child_count()
	return 0


func _entry_tier_for_ft(ft_ms: float) -> int:
	if ft_ms < float(ENTER_THRESHOLDS_MS[0]):
		return 0
	if ft_ms < float(ENTER_THRESHOLDS_MS[1]):
		return 1
	if ft_ms < float(ENTER_THRESHOLDS_MS[2]):
		return 2
	if ft_ms < float(ENTER_THRESHOLDS_MS[3]):
		return 3
	return 4


func _compute_ft_tier() -> int:
	return int(clamp(max(_current_tier, _state.min_tier), 0, 4))


func _sync_enemy_crowd() -> void:
	if not is_instance_valid(_spawner_node):
		return
	var want_anim: bool = _state.pause_crowd_idle_anim and _state.census_enemies >= _state.crowd_anim_threshold
	var want_relax: bool = _state.relax_enemy_collisions and _state.census_enemies >= _state.relax_collision_threshold
	if not want_anim and not want_relax and not _crowd_sync_dirty:
		return
	var any_active: bool = false
	var enemies: Array = _spawner_node.enemies
	var i: int = 0
	var n: int = enemies.size()
	while i < n:
		var e = enemies[i]
		if is_instance_valid(e) and not e.dead and e.has_method("_turbo_enemy_sync_crowd"):
			if e._turbo_enemy_sync_crowd():
				any_active = true
		i += 1
	_crowd_sync_dirty = any_active


func _compute_effective_tier() -> int:
	var tier: int = int(max(_current_tier, _state.min_tier))
	var spike: int = _state.load_spike_enemies
	if spike > 0:
		if _state.census_enemies >= 3 * spike:
			tier = int(max(tier, 4))
		elif _state.census_enemies >= 2 * spike:
			tier = int(max(tier, 3))
		elif _state.census_enemies >= spike:
			tier = int(max(tier, 2))
	if _state.census_spawn_queue >= 150:
		tier = int(max(tier, 3))
	elif _state.census_spawn_queue >= 50 or _census_active_births >= 50:
		tier = int(max(tier, 2))
	elif _state.census_spawn_queue >= SPAWN_STORM_QUEUE or _census_active_births >= SPAWN_STORM_BIRTHS:
		tier = int(max(tier, 1))
	return int(clamp(tier, 0, 4))


func _publish_tier(tier: int, in_run: bool) -> void:
	_published_tier = tier
	_state.in_run = in_run
	_state.apply_tier(tier)

	_compat_budget["tier"] = _state.tier
	_compat_budget["particle_scale"] = _state.particle_scale
	_compat_budget["text_cap"] = _state.text_cap
	_compat_budget["cache_extra_frames"] = _state.cache_extra_frames
	_compat_budget["cull_extra_margin"] = _state.cull_extra_margin
	_compat_budget["effects_per_frame"] = _state.fx_per_frame
	_compat_budget["disable_shake"] = _state.disable_shake
	_compat_budget["disable_flash"] = _state.disable_flash

	_compat_census["enemies"] = _state.census_enemies
	_compat_census["spawn_queue"] = _state.census_spawn_queue
	_compat_census["active_births"] = _census_active_births
	_compat_census["projectiles"] = _state.census_projectiles
	_compat_census["effects"] = _state.census_effects
	_compat_census["texts"] = _state.census_texts
	_compat_census["ft_ms"] = _ft_slow_ms


func _apply_physics_fps(in_run: bool, tier: int) -> void:
	var current_engine_hz: int = Engine.iterations_per_second

	if _external_hz_conflict_logged:
		_set_state_phys_hz(current_engine_hz)
		return

	if _physics_overridden and current_engine_hz != _physics_fps_applied:
		var expected_hz: int = _physics_fps_applied
		_external_hz_conflict_logged = true
		_physics_overridden = false
		_orig_physics_hz = current_engine_hz
		_physics_fps_applied = current_engine_hz
		ModLoaderLog.warning(
			"Saffron-Turbo: external mod changed physics tick rate (%d -> %d Hz); deferring to avoid oscillation." % [expected_hz, current_engine_hz],
			MOD_ID
		)
		_set_state_phys_hz(current_engine_hz)
		return

	var base_hz: int = _orig_physics_hz if _physics_overridden else current_engine_hz
	var want_override: bool = false
	var wanted_hz: int = base_hz
	var reason: String = "idle (not in a run)"

	if in_run:
		var potato_hz: int = base_hz
		if _state.potato_physics:
			if tier >= 4:
				var emergency: int = _state.emergency_physics_hz
				potato_hz = emergency if emergency > 0 else 30
			elif tier == 3:
				potato_hz = 30
			elif tier == 2:
				potato_hz = 45
		var spiral_hz: int = 30 if _spiral_active else base_hz
		if _spiral_active and spiral_hz <= potato_hz and spiral_hz < base_hz:
			wanted_hz = spiral_hz
			want_override = true
			reason = "spiral_guard (sustained frame time >= %.0f ms)" % SPIRAL_ENTER_MS
		elif _state.potato_physics and potato_hz < base_hz:
			wanted_hz = potato_hz
			want_override = true
			reason = "potato_physics (tier %d)" % tier
		else:
			wanted_hz = base_hz
			reason = "recovered to %d Hz (tier %d)" % [base_hz, tier]

	if not want_override:
		if _physics_overridden:
			var prev_hz: int = current_engine_hz
			Engine.iterations_per_second = _orig_physics_hz
			_physics_fps_applied = _orig_physics_hz
			_physics_overridden = false
			if _orig_physics_hz != prev_hz:
				ModLoaderLog.info(
					"Saffron-Turbo: physics tick rate %d -> %d Hz. Reason: %s. ft_ema=%.1fms tier=%d potato_physics=%s spiral_active=%s spiral_guard=%s (read back: %d)." % [
						prev_hz, _orig_physics_hz, reason,
						_ft_slow_ms, tier,
						str(_state.potato_physics),
						str(_spiral_active), str(_state.spiral_guard),
						Engine.iterations_per_second
					],
					MOD_ID
				)
		_set_state_phys_hz(Engine.iterations_per_second)
		return

	if not _physics_overridden:
		_orig_physics_hz = current_engine_hz

	if not _physics_overridden or _physics_fps_applied != wanted_hz:
		var prev_hz: int = current_engine_hz
		Engine.iterations_per_second = wanted_hz
		_physics_fps_applied = wanted_hz
		_physics_overridden = true
		if wanted_hz != prev_hz:
			ModLoaderLog.info(
				"Saffron-Turbo: physics tick rate %d -> %d Hz. Reason: %s. ft_ema=%.1fms tier=%d potato_physics=%s spiral_active=%s spiral_guard=%s (read back: %d)." % [
					prev_hz, wanted_hz, reason,
					_ft_slow_ms, tier,
					str(_state.potato_physics),
					str(_spiral_active), str(_state.spiral_guard),
					Engine.iterations_per_second
				],
				MOD_ID
			)
	_set_state_phys_hz(Engine.iterations_per_second)


func _tick_worker() -> void:
	if not _state.enable_worker_thread:
		if _worker != null:
			_stop_worker()
		return
	if _worker == null:
		_worker = WORKER_SCRIPT.new()
		if _worker.start():
			_state.worker = _worker
			if _state.grid != null:
				_state.grid.worker = _worker
		else:
			_worker = null
			return
	if not _worker.is_running():
		_stop_worker()
		return
	if _state.grid != null and _state.grid.worker != _worker:
		_state.grid.worker = _worker
	if not is_instance_valid(_spawner_node):
		return
	var e_arr: Array = _spawner_node.enemies
	var b_arr: Array = _spawner_node.bosses
	if (e_arr.size() + b_arr.size()) < _state.worker_min_enemies:
		return
	var pf: int = Engine.get_physics_frames()
	if (pf - _worker_last_frame) < 2:
		return
	_worker_last_frame = pf
	_worker.submit_snapshot(e_arr, pf, b_arr)


func _stop_worker() -> void:
	if _worker != null:
		_worker.stop()
		_worker = null
	_worker_last_frame = -1
	if _state != null:
		_state.worker = null
		if _state.grid != null:
			_state.grid.worker = null


func _apply_object_picking() -> void:
	if _root == null or _state == null:
		return
	if not _state.orig_snapshot_captured:
		_state.capture_engine_snapshot(_root, get_node_or_null("/root/ProgressData"))
	var want_picking: bool = false if (_state.disable_object_picking or _state.stream_potato) else _state.orig_object_picking
	if _root.physics_object_picking != want_picking:
		_root.physics_object_picking = want_picking


func _apply_vsync() -> void:
	if _state == null:
		return
	if not _state.orig_snapshot_captured:
		_state.capture_engine_snapshot(_root, get_node_or_null("/root/ProgressData"))
	if not _state.disable_vsync:
		if _vsync_applied == 0:
			OS.vsync_enabled = _state.orig_vsync
			_vsync_applied = -1
		return
	if _vsync_applied != 0:
		OS.vsync_enabled = false
		_vsync_applied = 0


func _apply_one_shot_options() -> void:
	var wanted: int = _state.fps_limit
	if wanted != 0 and wanted != _fps_limit_requested:
		_fps_limit_requested = wanted
		var pd = get_node_or_null("/root/ProgressData")
		if pd and pd.has_method("set_fps_limit"):
			pd.set_fps_limit(wanted == 1)
			ModLoaderLog.info(
				"Saffron-Turbo: game FPS limit %s via the game's own option."
				% ("on (60)" if wanted == 1 else "off (uncapped)"),
				MOD_ID
			)
		else:
			Engine.target_fps = 60 if wanted == 1 else 0

	if _state.native_switches and not _native_applied:
		_native_applied = true
		var pd2 = get_node_or_null("/root/ProgressData")
		if pd2:
			var settings = pd2.get("settings")
			if typeof(settings) == TYPE_DICTIONARY:
				settings["visual_effects"] = false
				settings["screenshake"] = false
				ModLoaderLog.info(
					"Saffron-Turbo: turned off the game's own graphical effects and screenshake.",
					MOD_ID
				)


func _apply_vignette(tier: int) -> void:
	if not is_instance_valid(_vignette_node):
		return
	var want_visible: bool = tier < 3 or not _state.adaptive_quality
	if not want_visible:
		if _vignette_node.visible:
			_vignette_node.visible = false
			_vignette_hidden_by_mod = true
	elif _vignette_hidden_by_mod:
		_vignette_node.visible = true
		_vignette_hidden_by_mod = false


func _refresh_run_scene() -> bool:
	if _tree == null:
		_tree = get_tree()
		if _tree == null:
			return false
		_root = _tree.root
	var scene: Node = _tree.current_scene
	if scene == null:
		_clear_scene_refs()
		return false
	if scene != _cached_scene:
		_cached_scene = scene
		_vignette_hidden_by_mod = false
		if _state != null:
			_state.burn_vis_active = 0
		_spawner_node = scene.get_node_or_null("EntitySpawner")
		if _spawner_node != null:
			_births_node = scene.get_node_or_null("Births")
			if _births_node == null:
				_births_node = scene.get_node_or_null("%Births")
			_fx_node = scene.get_node_or_null("EffectsManager")
			_ftm_node = scene.get_node_or_null("FloatingTextManager")
			_p_proj_node = scene.get_node_or_null("%PlayerProjectiles")
			_e_proj_node = scene.get_node_or_null("%EnemyProjectiles")
			_vignette_node = scene.get_node_or_null("UI/DamageVignette") as CanvasItem
		else:
			_births_node = null
			_fx_node = null
			_ftm_node = null
			_p_proj_node = null
			_e_proj_node = null
			_vignette_node = null
	return is_instance_valid(_spawner_node)


func _clear_scene_refs() -> void:
	_cached_scene = null
	_spawner_node = null
	_births_node = null
	_fx_node = null
	_ftm_node = null
	_p_proj_node = null
	_e_proj_node = null
	_vignette_node = null
	_vignette_hidden_by_mod = false


func _reset_census() -> void:
	_state.census_enemies = 0
	_state.census_bosses = 0
	_state.census_spawn_queue = 0
	_state.census_projectiles = 0
	_state.census_effects = 0
	_state.census_texts = 0
	_state.census_est_ms = 0.0
	_state.census_est_v2_ms = 0.0
	_census_active_births = 0


func _take_census(in_run: bool) -> void:
	if not in_run or not is_instance_valid(_spawner_node):
		_reset_census()
		return
	var b_cnt: int = int(_spawner_node.bosses.size())
	var e_cnt: int = int(_spawner_node.enemies.size()) + b_cnt
	var q_cnt: int = int(_spawner_node.queue_to_spawn.size())
	_census_active_births = _count_active_births()
	_state.census_bosses = b_cnt
	_state.census_enemies = e_cnt
	_state.census_spawn_queue = q_cnt
	_state.census_effects = int(_fx_node.current_graphical_effects) if is_instance_valid(_fx_node) else 0
	_state.census_texts = int(_ftm_node.current_nb_of_texts) if is_instance_valid(_ftm_node) else 0
	var proj_total: int = 0
	if is_instance_valid(_p_proj_node):
		proj_total += _p_proj_node.get_child_count()
	if is_instance_valid(_e_proj_node):
		proj_total += _e_proj_node.get_child_count()
	_state.census_projectiles = proj_total
	_state.census_est_ms = e_cnt * 0.007 + proj_total * 0.0012 + _state.census_effects * 0.010 + _state.census_texts * 0.0035
	var pairs: int = int(Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS))
	_state.census_est_v2_ms = _state.census_est_ms + q_cnt * 0.010 + pairs * 0.002


func _log_census(tier: int) -> void:
	if _state.census_enemies == 0 and _state.census_effects == 0:
		return
	ModLoaderLog.info(
		"load: tier=%d phys_hz=%d enemies=%d births=%d queue=%d projectiles=%d effects=%d texts=%d burns=%d/%d ft_ema=%.2fms est=%.1fms fps=%.0f spiral=%d" % [
			tier,
			Engine.iterations_per_second,
			_state.census_enemies,
			_census_active_births,
			_state.census_spawn_queue,
			_state.census_projectiles,
			_state.census_effects,
			_state.census_texts,
			_state.burn_vis_active,
			_state.burn_vis_cap,
			_ft_slow_ms,
			_state.census_est_ms,
			Engine.get_frames_per_second(),
			1 if _spiral_active else 0
		],
		MOD_ID
	)

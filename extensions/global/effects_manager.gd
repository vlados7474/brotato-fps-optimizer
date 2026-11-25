extends "res://global/effects_manager.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Zero-Realloc VFX Pool, Adaptive Sim-FPS & Camera Publisher (_turbo_fx_)
# -----------------------------------------------------------------------------
# 1. Publishes cam_rect and cam_rect_unit once per physics tick into TurboState.
# 2. Caches ProgressData.settings Dictionary in _ready() for 1-hop hit checks.
# 3. Eliminates VisualServer::multimesh_allocate GPU stalls: CPUParticles2D.amount
#    is set at most once on cold instantiation and never overwritten on pool
#    reuse; effect_scale is applied via scale_amount, lifetime & _finished_timer.
# 4. Direct override of on_enemy_speed_removed(unit), safe freed-object guard,
#    and AnimatedSprite.frame = 0 reset on pool reuse.
# =============================================================================

const _turbo_fx_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_fx_UNIT_SPD_CD_MS: int = 250
const _turbo_fx_CACHE_LIMIT: int = 512

var _turbo_fx_state = null
var _turbo_fx_settings: Dictionary = {}
var _turbo_fx_camera: Camera2D = null
var _turbo_fx_rect_frame: int = -1
var _turbo_fx_spawn_idle_frame: int = -1
var _turbo_fx_spawns_this_frame: int = 0

var _turbo_fx_base_lifetimes: Dictionary = {}
var _turbo_fx_base_timer_waits: Dictionary = {}
const _turbo_fx_DORMANT_CAP: int = 24

var _turbo_fx_base_scale_amounts: Dictionary = {}
var _turbo_fx_dormant: Dictionary = {}
var _turbo_fx_speed_scene_ids: Dictionary = {}
var _turbo_fx_unit_spd_cd: Dictionary = {}
var _turbo_fx_next_speed_global_ms: int = 0
var _turbo_fx_in_speed_dispatch: bool = false


func _ready() -> void: # ADDITION
	_turbo_fx_state = _turbo_fx_STATE_SCRIPT.HOLDER.get("state")
	if typeof(ProgressData.settings) == TYPE_DICTIONARY:
		_turbo_fx_settings = ProgressData.settings
	_turbo_fx_camera = null
	_turbo_fx_rect_frame = -1
	_turbo_fx_base_lifetimes.clear()
	_turbo_fx_base_timer_waits.clear()
	_turbo_fx_base_scale_amounts.clear()
	_turbo_fx_dormant.clear()
	_turbo_fx_unit_spd_cd.clear()
	_turbo_fx_scan_speed_scenes()
	set_physics_process(true)
	var _ok: bool = _turbo_fx_refresh_rects()


func _exit_tree() -> void: # ADDITION
	if _turbo_fx_state != null:
		_turbo_fx_state.cam_valid = false
		_turbo_fx_state.cam_frame = -1
	_turbo_fx_base_lifetimes.clear()
	_turbo_fx_base_timer_waits.clear()
	_turbo_fx_base_scale_amounts.clear()
	_turbo_fx_unit_spd_cd.clear()
	_turbo_fx_dormant.clear()
	_turbo_fx_speed_scene_ids.clear()


func _physics_process(_delta: float) -> void: # ADDITION
	var _ok: bool = _turbo_fx_refresh_rects()


func _turbo_fx_get_camera() -> Camera2D:
	if not is_instance_valid(_turbo_fx_camera):
		if _main == null:
			return null
		_turbo_fx_camera = _main.get_node_or_null("Camera") as Camera2D
	return _turbo_fx_camera


func _turbo_fx_refresh_rects() -> bool:
	var s = _turbo_fx_state
	if s == null:
		return false
	var frame: int = Engine.get_physics_frames()
	if frame == _turbo_fx_rect_frame and s.cam_frame == frame:
		return s.cam_valid
	_turbo_fx_rect_frame = frame
	s.cam_frame = frame

	var camera: Camera2D = _turbo_fx_get_camera()
	if camera == null:
		s.cam_valid = false
		return false

	var centre: Vector2 = camera.get_camera_screen_center()
	var half_size: Vector2 = Vector2(Utils.project_width, Utils.project_height) * camera.zoom * 0.5
	var margin: float = s.cull_margin + (s.cull_extra_margin if s.adaptive_quality else 0.0)
	var rect: Rect2 = Rect2(centre - half_size, half_size * 2.0).grow(margin)
	s.cam_rect = rect
	s.cam_rect_unit = rect.grow(200.0)
	s.cam_valid = true
	return true


func _turbo_fx_spawn_budget_ok(per_frame: int) -> bool:
	if per_frame <= 0:
		return true
	var idle_frame: int = Engine.get_idle_frames()
	if idle_frame != _turbo_fx_spawn_idle_frame:
		_turbo_fx_spawn_idle_frame = idle_frame
		_turbo_fx_spawns_this_frame = 0
	return _turbo_fx_spawns_this_frame < per_frame


func _turbo_fx_scan_speed_scenes() -> void:
	_turbo_fx_speed_scene_ids.clear()
	if speed_removed_particles is PackedScene:
		_turbo_fx_speed_scene_ids[speed_removed_particles.get_instance_id()] = true
	for prop in get_property_list():
		var pname: String = str(prop.get("name", "")).to_lower()
		if "speed" in pname or "slow" in pname or "smoke" in pname:
			var val = get(prop["name"])
			if val is PackedScene:
				_turbo_fx_speed_scene_ids[val.get_instance_id()] = true


func _turbo_fx_allow_speed_vfx(unit_for_fx) -> bool:
	if not bool(_turbo_fx_settings.get("visual_effects", true)):
		return false
	var s = _turbo_fx_state
	var _ok: bool = _turbo_fx_refresh_rects()
	if s != null and (s.stream_potato or s.tier >= 3):
		return false
	var now_ms: int = OS.get_ticks_msec()
	if now_ms < _turbo_fx_next_speed_global_ms:
		return false
	if unit_for_fx != null and is_instance_valid(unit_for_fx) and unit_for_fx is Node2D:
		if s != null and s.cull_offscreen and s.cam_valid and not s.cam_rect_unit.has_point(unit_for_fx.global_position):
			return false
		var uid: int = unit_for_fx.get_instance_id()
		if now_ms < int(_turbo_fx_unit_spd_cd.get(uid, 0)):
			return false
		if _turbo_fx_unit_spd_cd.size() > _turbo_fx_CACHE_LIMIT:
			_turbo_fx_unit_spd_cd.clear()
		_turbo_fx_unit_spd_cd[uid] = now_ms + _turbo_fx_UNIT_SPD_CD_MS
	var global_cd: int = 120 if (s != null and s.tier >= 2) else 50
	_turbo_fx_next_speed_global_ms = now_ms + global_cd
	return true


func on_enemy_speed_removed(unit) -> void:
	if not _turbo_fx_allow_speed_vfx(unit):
		return
	_turbo_fx_in_speed_dispatch = true
	.on_enemy_speed_removed(unit)
	_turbo_fx_in_speed_dispatch = false


func _on_unit_took_damage(unit, value: int, knockback_direction: Vector2, _is_crit: bool, _is_dodge: bool, _is_protected: bool, _armor_did_something: bool, args: TakeDamageArgs, _hit_type: int, _is_one_shot: bool) -> void:
	if value <= 0 or not bool(_turbo_fx_settings.get("visual_effects", true)) or args.hide_feedback:
		return
	var s = _turbo_fx_state
	if s != null:
		if current_graphical_effects >= s.fx_alive_cap or current_graphical_effects > MAX_GRAPHICAL_EFFECTS:
			return
		if not _turbo_fx_spawn_budget_ok(s.fx_per_frame):
			return
	var upos: Vector2 = unit.global_position
	if s != null and s.cull_offscreen and _turbo_fx_refresh_rects():
		if not s.cam_rect_unit.has_point(upos):
			return
	var effect_scale: float = args.get_effect_scale()
	var effect_pos: Vector2
	if unit.aim_shape != null:
		effect_pos = unit.get_hit_feedback_position(args)
	else:
		effect_pos = upos + knockback_direction * Utils.get_effect_distance(unit)
	if unit.stats.generate_blood:
		play_hit_particles(effect_pos, knockback_direction, effect_scale)
	play_hit_effect(effect_pos, knockback_direction, effect_scale)


func on_graphical_effect_finished(object: Object) -> void:
	if not is_instance_valid(object):
		current_graphical_effects = int(max(0, current_graphical_effects - 1))
		return
	if object is CPUParticles2D:
		object.emitting = false
	elif object is AnimatedSprite:
		object.stop()
	if object is CanvasItem and object.visible:
		object.visible = false
	var can_dormant: bool = (object is AnimatedSprite) or (object is CPUParticles2D and "_finished_timer" in object and is_instance_valid(object._finished_timer))
	if can_dormant and object.has_meta("pool_id") and object.is_inside_tree():
		if object.get_meta("_turbo_dormant", false):
			return
		var pid: int = int(object.get_meta("pool_id"))
		var bucket = _turbo_fx_dormant.get(pid)
		if bucket == null:
			bucket = []
			_turbo_fx_dormant[pid] = bucket
		if bucket.size() < _turbo_fx_DORMANT_CAP and not bucket.has(object):
			object.set_meta("_turbo_dormant", true)
			if "_finished_timer" in object and is_instance_valid(object._finished_timer):
				object._finished_timer.stop()
			bucket.push_back(object)
			current_graphical_effects = int(max(0, current_graphical_effects - 1))
			return
	.on_graphical_effect_finished(object)


func play(scene: PackedScene, effect_pos: Vector2, direction: Vector2, effect_scale: float = 1.0) -> void:
	if scene == null or effect_scale <= 0.0:
		return

	var s = _turbo_fx_state
	if s == null or _main == null:
		.play(scene, effect_pos, direction, effect_scale)
		return

	if current_graphical_effects >= s.fx_alive_cap or current_graphical_effects > MAX_GRAPHICAL_EFFECTS:
		return
	if not _turbo_fx_spawn_budget_ok(s.fx_per_frame):
		return

	if s.cull_offscreen and _turbo_fx_refresh_rects() and not s.cam_rect.has_point(effect_pos):
		return

	var scene_id: int = scene.get_instance_id()
	if not _turbo_fx_in_speed_dispatch and _turbo_fx_speed_scene_ids.has(scene_id):
		if s.stream_potato or s.tier >= 3:
			return
		var now_ms: int = OS.get_ticks_msec()
		if now_ms < _turbo_fx_next_speed_global_ms:
			return
		_turbo_fx_next_speed_global_ms = now_ms + (120 if s.tier >= 2 else 50)

	_turbo_fx_spawns_this_frame += 1

	var instance = null
	var dorm_bucket = _turbo_fx_dormant.get(scene_id)
	if dorm_bucket != null:
		while not dorm_bucket.empty():
			var cand = dorm_bucket.pop_back()
			if is_instance_valid(cand) and cand.is_inside_tree():
				if cand.has_meta("_turbo_dormant"):
					cand.remove_meta("_turbo_dormant")
				instance = cand
				break
	if instance == null:
		instance = _main.get_node_from_pool(scene_id, _main._effects)
	var is_cold: bool = (instance == null)
	if is_cold:
		instance = scene.instance()
		_main.add_effect(instance)
		var _destroyed_connect = instance.connect("finished", self, "on_graphical_effect_finished")
		instance.set_meta("pool_id", scene_id)

	instance.global_position = effect_pos
	instance.rotation = direction.angle() - PI
	if not is_cold and instance is CanvasItem and not instance.visible:
		instance.visible = true

	current_graphical_effects += 1

	if instance is CPUParticles2D:
		if not _turbo_fx_base_lifetimes.has(scene_id):
			_turbo_fx_base_lifetimes[scene_id] = instance.lifetime
		if not _turbo_fx_base_scale_amounts.has(scene_id):
			_turbo_fx_base_scale_amounts[scene_id] = instance.scale_amount

		if is_cold:
			var init_scale: float = min(clamp(s.particle_budget_scale, 0.05, 1.0), 0.25 if s.stream_potato else 1.0)
			if init_scale < 0.999:
				var cold_amt: int = int(max(1, int(round(float(instance.amount) * init_scale))))
				if instance.amount != cold_amt:
					instance.amount = cold_amt
			instance.set_meta("base_amount", instance.amount)

		var sim_fps: int = s.fx_sim_fps
		if instance.fixed_fps != sim_fps:
			instance.fixed_fps = sim_fps
		var want_fract: bool = (sim_fps == 0)
		if instance.fract_delta != want_fract:
			instance.fract_delta = want_fract

		var target_scale_amt: float = float(_turbo_fx_base_scale_amounts[scene_id]) * clamp(effect_scale, 0.35, 1.6)
		if abs(instance.scale_amount - target_scale_amt) > 0.01:
			instance.scale_amount = target_scale_amt

		var base_life: float = max(0.01, float(_turbo_fx_base_lifetimes[scene_id]))
		var target_life: float = max(0.06, base_life * s.fx_lifetime_scale * clamp(effect_scale, 0.5, 1.25))
		if abs(instance.lifetime - target_life) > 0.01:
			instance.lifetime = target_life

		if "_finished_timer" in instance and is_instance_valid(instance._finished_timer):
			if not _turbo_fx_base_timer_waits.has(scene_id):
				_turbo_fx_base_timer_waits[scene_id] = instance._finished_timer.wait_time
			var ratio: float = target_life / base_life
			instance._finished_timer.wait_time = max(0.08, float(_turbo_fx_base_timer_waits[scene_id]) * ratio)

		instance.restart()
		if "_finished_timer" in instance and is_instance_valid(instance._finished_timer):
			instance._finished_timer.start()
	elif instance is AnimatedSprite:
		instance.frame = 0
		instance.play()
		if "_finished_timer" in instance and is_instance_valid(instance._finished_timer) and instance._finished_timer.is_stopped():
			instance._finished_timer.start()
	else:
		if instance.has_method("play"):
			instance.play()
		if "_finished_timer" in instance and is_instance_valid(instance._finished_timer) and instance._finished_timer.is_stopped():
			instance._finished_timer.start()

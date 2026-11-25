extends "res://particles/burning/burning_particles.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - BurningParticles SpreadArea, Visual Budget & Sim FPS (_turbo_burn_)
# -----------------------------------------------------------------------------
# Overrides start_emitting/stop_emitting/activate_spread/deactivate_spread so
# logical burning never sleeps while visuals are suppressed, visible=true is
# restored when re-entering view, burn_vis_active never leaks, and SpreadArea
# is untouched when fix_idle_burn_spread == false.
# =============================================================================

const _turbo_burn_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_burn_STAGGER_MASK: int = 3
const _turbo_burn_SHARED_MATS: Dictionary = {}

var _turbo_burn_state = null
var _turbo_burn_initialized: bool = false
var _turbo_burn_spread_area: Area2D = null
var _turbo_burn_spread_shapes: Array = []
var _turbo_burn_particle_nodes: Array = []
var _turbo_burn_secondary: Node = null
var _turbo_burn_owner_unit: Node = null
var _turbo_burn_timer: Timer = null

var _turbo_burn_orig_monitorable: bool = false
var _turbo_burn_spread_active: bool = false
var _turbo_burn_last_defer_frame: int = -1
var _turbo_burn_frame_slot: int = 0
var _turbo_burn_base_uses_physics: bool = false

var _turbo_burn_logical_emitting: bool = false
var _turbo_burn_holds_vis_slot: bool = false
var _turbo_burn_vis_suppressed: bool = false
var _turbo_burn_in_vis_sync: bool = false
var _turbo_burn_last_sim_fps: int = -1


func _ready() -> void: # ADDITION
	_turbo_burn_state = _turbo_burn_STATE_SCRIPT.HOLDER.get("state")
	_turbo_burn_base_uses_physics = is_physics_processing()
	_turbo_burn_frame_slot = int(abs(get_instance_id())) & _turbo_burn_STAGGER_MASK
	_turbo_burn_cache_nodes()
	_turbo_burn_connect_signals()
	_turbo_burn_initialized = true
	_turbo_burn_sync_state(true)
	_turbo_burn_update_processing()


func _enter_tree() -> void: # ADDITION
	if not _turbo_burn_initialized:
		return
	_turbo_burn_sync_state(true)
	_turbo_burn_update_processing()


func _exit_tree() -> void: # ADDITION
	_turbo_burn_release_vis_slot()
	_turbo_burn_logical_emitting = false
	_turbo_burn_vis_suppressed = false
	if _turbo_burn_spread_active:
		_turbo_burn_apply_spread(false, true)
	else:
		_turbo_burn_clear_bodies()


func start_emitting() -> void:
	_turbo_burn_logical_emitting = true
	_turbo_burn_in_vis_sync = true
	.start_emitting()
	_turbo_burn_in_vis_sync = false
	if _turbo_burn_initialized:
		_turbo_burn_sync_visual(false)
		if _turbo_burn_state == null or _turbo_burn_state.fix_idle_burn_spread:
			_turbo_burn_apply_spread(_turbo_burn_want_spread(), false)
		_turbo_burn_update_processing()


func stop_emitting() -> void:
	_turbo_burn_logical_emitting = false
	_turbo_burn_vis_suppressed = false
	_turbo_burn_release_vis_slot()
	_turbo_burn_in_vis_sync = true
	.stop_emitting()
	_turbo_burn_in_vis_sync = false
	if _turbo_burn_initialized:
		if _turbo_burn_state == null or _turbo_burn_state.fix_idle_burn_spread:
			_turbo_burn_apply_spread(false, false)
		_turbo_burn_update_processing()


func activate_spread() -> void:
	.activate_spread()
	if _turbo_burn_initialized:
		if _turbo_burn_state == null or _turbo_burn_state.fix_idle_burn_spread:
			_turbo_burn_apply_spread(_turbo_burn_want_spread() or _spread_active, false)
		_turbo_burn_update_processing()


func deactivate_spread() -> void:
	.deactivate_spread()
	if _turbo_burn_initialized:
		if _turbo_burn_state == null or _turbo_burn_state.fix_idle_burn_spread:
			_turbo_burn_apply_spread(false, false)
		_turbo_burn_update_processing()


func _physics_process(_delta: float) -> void: # ADDITION
	if sleep_when_idle and not emitting and not visible and not _spread_active and not _turbo_burn_spread_active and not _turbo_burn_logical_emitting:
		if _turbo_burn_holds_vis_slot:
			_turbo_burn_release_vis_slot()
		set_physics_process(false)
		return

	if not _turbo_burn_initialized:
		return
	if not _turbo_burn_is_owner_active():
		_turbo_burn_logical_emitting = false
		_turbo_burn_vis_suppressed = false
		_turbo_burn_release_vis_slot()
		if _turbo_burn_spread_active and (_turbo_burn_state == null or _turbo_burn_state.fix_idle_burn_spread):
			_turbo_burn_apply_spread(false, false)
		_turbo_burn_apply_particle_visuals(false, _turbo_burn_state, false)
		_turbo_burn_update_processing()
		return
	if ((Engine.get_physics_frames() + _turbo_burn_frame_slot) & _turbo_burn_STAGGER_MASK) != 0:
		return
	_turbo_burn_sync_state(false)


func _turbo_burn_cache_nodes() -> void:
	_turbo_burn_spread_shapes.clear()
	_turbo_burn_particle_nodes.clear()

	var spread_area_node: Node = null
	if "_spread_area" in self and is_instance_valid(get("_spread_area")):
		spread_area_node = get("_spread_area")
	elif "spread_area" in self and is_instance_valid(get("spread_area")):
		spread_area_node = get("spread_area")
	else:
		spread_area_node = get_node_or_null("SpreadArea")
	if spread_area_node == null:
		for child in get_children():
			if child is Area2D:
				spread_area_node = child
				break

	if spread_area_node is Area2D:
		_turbo_burn_spread_area = spread_area_node
		_turbo_burn_orig_monitorable = _turbo_burn_spread_area.monitorable
		for child in _turbo_burn_spread_area.get_children():
			if child is CollisionShape2D or child is CollisionPolygon2D:
				_turbo_burn_spread_shapes.push_back(child)

	if "emitting" in self:
		_turbo_burn_particle_nodes.push_back(self)
		_turbo_burn_apply_shared_material(self)
	_turbo_burn_secondary = null
	for child in get_children():
		if is_instance_valid(child) and "emitting" in child and not _turbo_burn_particle_nodes.has(child):
			_turbo_burn_particle_nodes.push_back(child)
			if _turbo_burn_secondary == null:
				_turbo_burn_secondary = child
			_turbo_burn_apply_shared_material(child)

	_turbo_burn_owner_unit = _turbo_burn_find_owner()
	if is_instance_valid(_turbo_burn_owner_unit):
		if "_burning_timer" in _turbo_burn_owner_unit and _turbo_burn_owner_unit.get("_burning_timer") is Timer:
			_turbo_burn_timer = _turbo_burn_owner_unit.get("_burning_timer")
		else:
			var t_node: Node = _turbo_burn_owner_unit.get_node_or_null("BurningTimer")
			if t_node is Timer:
				_turbo_burn_timer = t_node


func _turbo_burn_apply_shared_material(node: Node) -> void:
	if not (node is CanvasItem):
		return
	var cur_mat = node.material
	if cur_mat == null or not (cur_mat is CanvasItemMaterial):
		return
	var cm: CanvasItemMaterial = cur_mat as CanvasItemMaterial
	var key: String = "%d|%d|%d|%d|%d|%d" % [
		cm.blend_mode,
		cm.light_mode,
		1 if cm.particles_animation else 0,
		cm.particles_anim_h_frames,
		cm.particles_anim_v_frames,
		1 if cm.particles_anim_loop else 0
	]
	var shared = _turbo_burn_SHARED_MATS.get(key)
	if shared == null:
		var nm := CanvasItemMaterial.new()
		nm.blend_mode = cm.blend_mode
		nm.light_mode = cm.light_mode
		nm.particles_animation = cm.particles_animation
		nm.particles_anim_h_frames = cm.particles_anim_h_frames
		nm.particles_anim_v_frames = cm.particles_anim_v_frames
		nm.particles_anim_loop = cm.particles_anim_loop
		if _turbo_burn_SHARED_MATS.size() >= 64:
			_turbo_burn_SHARED_MATS.clear()
		_turbo_burn_SHARED_MATS[key] = nm
		shared = nm
	if node.material != shared:
		node.material = shared


func _turbo_burn_find_owner() -> Node:
	var cur: Node = get_parent()
	var depth: int = 0
	while is_instance_valid(cur) and depth < 4:
		if "_burning" in cur or "_burnings" in cur or cur.has_method("take_damage"):
			return cur
		cur = cur.get_parent()
		depth += 1
	return get_parent()


func _turbo_burn_connect_signals() -> void:
	if not is_connected("visibility_changed", self, "_turbo_burn_on_vis_changed"):
		var _e0 = connect("visibility_changed", self, "_turbo_burn_on_vis_changed")

	if not is_instance_valid(_turbo_burn_owner_unit):
		return
	if _turbo_burn_owner_unit is CanvasItem:
		if not _turbo_burn_owner_unit.is_connected("visibility_changed", self, "_turbo_burn_on_owner_vis"):
			var _e1 = _turbo_burn_owner_unit.connect("visibility_changed", self, "_turbo_burn_on_owner_vis")

	if _turbo_burn_owner_unit.has_signal("died") and not _turbo_burn_owner_unit.is_connected("died", self, "_turbo_burn_on_owner_died"):
		var _e2 = _turbo_burn_owner_unit.connect("died", self, "_turbo_burn_on_owner_died")

	for s_name in ["burning_started", "burning_stopped"]:
		if _turbo_burn_owner_unit.has_signal(s_name) and not _turbo_burn_owner_unit.is_connected(s_name, self, "_turbo_burn_on_owner_event"):
			var _e3 = _turbo_burn_owner_unit.connect(s_name, self, "_turbo_burn_on_owner_event")

	if is_instance_valid(_turbo_burn_timer) and not _turbo_burn_timer.is_connected("timeout", self, "_turbo_burn_on_timer"):
		var _e4 = _turbo_burn_timer.connect("timeout", self, "_turbo_burn_on_timer")


func _turbo_burn_on_vis_changed() -> void:
	if not _turbo_burn_initialized or _turbo_burn_in_vis_sync:
		return
	if not is_visible_in_tree() and not _turbo_burn_is_owner_active():
		_turbo_burn_logical_emitting = false
		_turbo_burn_vis_suppressed = false
		_turbo_burn_release_vis_slot()
		if _turbo_burn_state == null or _turbo_burn_state.fix_idle_burn_spread:
			_turbo_burn_apply_spread(false, false)
	else:
		_turbo_burn_sync_state(false)
	_turbo_burn_update_processing()


func _turbo_burn_on_owner_died(_a = null, _b = null, _c = null, _d = null) -> void:
	_turbo_burn_logical_emitting = false
	_turbo_burn_vis_suppressed = false
	_turbo_burn_release_vis_slot()
	if _turbo_burn_state == null or _turbo_burn_state.fix_idle_burn_spread:
		_turbo_burn_apply_spread(false, true)
	_turbo_burn_apply_particle_visuals(false, _turbo_burn_state, false)
	_turbo_burn_update_processing()


func _turbo_burn_on_owner_vis() -> void:
	if not _turbo_burn_is_owner_active():
		_turbo_burn_logical_emitting = false
		_turbo_burn_vis_suppressed = false
		_turbo_burn_release_vis_slot()
		if _turbo_burn_state == null or _turbo_burn_state.fix_idle_burn_spread:
			_turbo_burn_apply_spread(false, true)
		_turbo_burn_apply_particle_visuals(false, _turbo_burn_state, false)
	else:
		_turbo_burn_sync_state(true)
	_turbo_burn_update_processing()


func _turbo_burn_on_owner_event(_a = null, _b = null, _c = null, _d = null, _e = null, _f = null, _g = null, _h = null, _i = null, _j = null) -> void:
	_turbo_burn_sync_state(false)
	_turbo_burn_update_processing()


func _turbo_burn_on_timer() -> void:
	call_deferred("_turbo_burn_deferred_sync")


func _turbo_burn_deferred_sync() -> void:
	if is_inside_tree():
		_turbo_burn_sync_state(false)
		_turbo_burn_update_processing()


func _turbo_burn_update_processing() -> void:
	if sleep_when_idle:
		var need_physics: bool = is_inside_tree() and (emitting or visible or _spread_active or _turbo_burn_spread_active or _turbo_burn_logical_emitting)
		if is_physics_processing() != need_physics:
			set_physics_process(need_physics)
		return
	if _turbo_burn_base_uses_physics:
		return
	var active: bool = _turbo_burn_is_owner_active()
	if is_physics_processing() != active:
		set_physics_process(active)


func _turbo_burn_is_owner_active() -> bool:
	if not is_inside_tree():
		return false
	if not is_instance_valid(_turbo_burn_owner_unit):
		return is_visible_in_tree()
	if not _turbo_burn_owner_unit.is_inside_tree():
		return false
	if _turbo_burn_owner_unit is CanvasItem and not _turbo_burn_owner_unit.visible:
		return false
	if "dead" in _turbo_burn_owner_unit and bool(_turbo_burn_owner_unit.get("dead")):
		return false
	return true


func _turbo_burn_is_burning() -> bool:
	if not _turbo_burn_is_owner_active():
		return false
	if is_instance_valid(_turbo_burn_owner_unit):
		if _turbo_burn_owner_unit.has_method("is_burning"):
			return bool(_turbo_burn_owner_unit.call("is_burning"))
		if "_is_burning" in _turbo_burn_owner_unit:
			return bool(_turbo_burn_owner_unit.get("_is_burning"))
	if is_instance_valid(_turbo_burn_timer):
		return not _turbo_burn_timer.is_stopped()
	if _turbo_burn_logical_emitting:
		return true
	for p_node in _turbo_burn_particle_nodes:
		if is_instance_valid(p_node) and bool(p_node.get("emitting")):
			return true
	return false


func _turbo_burn_is_onscreen(s) -> bool:
	if s == null or not s.cam_valid:
		return true
	var pos: Vector2
	if is_instance_valid(_turbo_burn_owner_unit) and _turbo_burn_owner_unit is Node2D:
		pos = _turbo_burn_owner_unit.global_position
	else:
		pos = global_position
	return s.cam_rect_unit.has_point(pos)


func _turbo_burn_release_vis_slot() -> void:
	if not _turbo_burn_holds_vis_slot:
		return
	_turbo_burn_holds_vis_slot = false
	var s = _turbo_burn_state
	if s == null:
		s = _turbo_burn_STATE_SCRIPT.HOLDER.get("state")
		_turbo_burn_state = s
	if s != null:
		s.burn_vis_active = int(max(0, s.burn_vis_active - 1))


func _turbo_burn_apply_particle_visuals(want_vis: bool, s, force: bool) -> void:
	var target_fps: int = 0
	if s != null and s.fx_sim_fps > 0:
		target_fps = s.fx_sim_fps
	var target_fract: bool = (target_fps == 0)
	var update_sim: bool = force or (target_fps != _turbo_burn_last_sim_fps)
	if update_sim:
		_turbo_burn_last_sim_fps = target_fps

	_turbo_burn_in_vis_sync = true
	if want_vis:
		if not visible:
			visible = true
		emit_remaining = 0.0
	else:
		if _turbo_burn_logical_emitting or not _turbo_burn_is_owner_active():
			emit_remaining = 0.0
			if visible:
				visible = false
	_turbo_burn_in_vis_sync = false

	var hide_sec: bool = (not want_vis) or (s != null and (s.tier >= 2 or s.stream_potato))
	for p_node in _turbo_burn_particle_nodes:
		if not is_instance_valid(p_node):
			continue
		var node_emit: bool = want_vis
		if p_node == _turbo_burn_secondary:
			node_emit = want_vis and not hide_sec
			if p_node is CanvasItem and p_node.visible != node_emit:
				p_node.visible = node_emit
		if bool(p_node.get("emitting")) != node_emit:
			p_node.set("emitting", node_emit)
		if update_sim and p_node is CPUParticles2D:
			if p_node.fixed_fps != target_fps:
				p_node.fixed_fps = target_fps
			if p_node.fract_delta != target_fract:
				p_node.fract_delta = target_fract


func _turbo_burn_sync_visual(force: bool) -> void:
	var s = _turbo_burn_state
	if s == null:
		s = _turbo_burn_STATE_SCRIPT.HOLDER.get("state")
		_turbo_burn_state = s

	var want_vis: bool = _turbo_burn_logical_emitting and _turbo_burn_is_owner_active()
	if want_vis and not _turbo_burn_is_onscreen(s):
		want_vis = false

	if want_vis and s != null:
		var cap: int = s.burn_vis_cap
		if cap <= 0:
			_turbo_burn_release_vis_slot()
			want_vis = false
		elif _turbo_burn_holds_vis_slot:
			if s.burn_vis_active > cap:
				_turbo_burn_release_vis_slot()
				want_vis = false
		else:
			if s.burn_vis_active < cap:
				s.burn_vis_active += 1
				_turbo_burn_holds_vis_slot = true
			else:
				want_vis = false
	else:
		if _turbo_burn_holds_vis_slot:
			_turbo_burn_release_vis_slot()

	_turbo_burn_vis_suppressed = _turbo_burn_logical_emitting and not want_vis
	_turbo_burn_apply_particle_visuals(want_vis, s, force)


func _turbo_burn_extract_spread(raw_data) -> int:
	if raw_data == null:
		return 0
	var vt: int = typeof(raw_data)
	if vt == TYPE_OBJECT:
		if not is_instance_valid(raw_data):
			return 0
		if raw_data.has_method("is_not_burning") and bool(raw_data.call("is_not_burning")):
			return 0
		if "spread" in raw_data:
			return int(raw_data.get("spread"))
	elif vt == TYPE_DICTIONARY:
		if raw_data.has("spread"):
			return int(raw_data["spread"])
		var best_d: int = 0
		for val in raw_data.values():
			var sub: int = _turbo_burn_extract_spread(val)
			if sub > best_d:
				best_d = sub
		return best_d
	elif vt == TYPE_ARRAY:
		var best_a: int = 0
		for elem in raw_data:
			var sub2: int = _turbo_burn_extract_spread(elem)
			if sub2 > best_a:
				best_a = sub2
		return best_a
	return 0


func _turbo_burn_want_spread() -> bool:
	if not _turbo_burn_logical_emitting:
		return false

	var found_field: bool = false
	var max_spread: int = 0
	if "spread" in self:
		found_field = true
		max_spread = int(max(max_spread, int(get("spread"))))
	for f_name in ["_burning_data", "burning_data"]:
		if f_name in self:
			found_field = true
			max_spread = int(max(max_spread, _turbo_burn_extract_spread(get(f_name))))
	if is_instance_valid(_turbo_burn_owner_unit):
		for u_name in ["_burning", "_burnings"]:
			if u_name in _turbo_burn_owner_unit:
				found_field = true
				max_spread = int(max(max_spread, _turbo_burn_extract_spread(_turbo_burn_owner_unit.get(u_name))))
	if found_field:
		return max_spread > 0
	return _spread_active


func _turbo_burn_sync_state(force: bool) -> void:
	_turbo_burn_logical_emitting = _turbo_burn_is_burning()
	if _turbo_burn_state == null or _turbo_burn_state.fix_idle_burn_spread:
		_turbo_burn_apply_spread(_turbo_burn_want_spread(), force)
	_turbo_burn_sync_visual(force)


func _turbo_burn_clear_bodies() -> void:
	if "bodies" in self:
		var b = get("bodies")
		if b is Array:
			b.clear()


func _turbo_burn_apply_spread(enable: bool, force: bool) -> void:
	if _turbo_burn_state != null and not _turbo_burn_state.fix_idle_burn_spread:
		return
	if not enable:
		_turbo_burn_clear_bodies()
	if not is_instance_valid(_turbo_burn_spread_area):
		_turbo_burn_spread_active = enable
		return
	var needs_apply: bool = force or (enable != _turbo_burn_spread_active) or (_turbo_burn_spread_area.monitoring != enable)
	if not needs_apply:
		return
	var cur_frame: int = Engine.get_physics_frames()
	if not force and _turbo_burn_last_defer_frame == cur_frame and enable == _turbo_burn_spread_active:
		return
	_turbo_burn_spread_active = enable
	_turbo_burn_last_defer_frame = cur_frame
	var target_disabled: bool = not enable
	for shape_node in _turbo_burn_spread_shapes:
		if is_instance_valid(shape_node):
			shape_node.set_deferred("disabled", target_disabled)
	_turbo_burn_spread_area.set_deferred("monitoring", enable)
	_turbo_burn_spread_area.set_deferred("monitorable", _turbo_burn_orig_monitorable if enable else false)

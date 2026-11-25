extends Node
# =============================================================================
# Saffron-Turbo 5.6.1 - VisualServer Physics Interpolator
# -----------------------------------------------------------------------------
# Smooths Enemy, Boss, and Player rendering between physics ticks via
# VisualServer.frame_pre_draw + canvas_item_set_transform(rid, xform).
# Pause-safe (restores transforms on get_tree().paused, resyncs on resume),
# integer instance_id keys (never stores freed Objects as Dictionary keys),
# cached RIDs, offscreen skip via cam_rect_unit, and 63/58 FPS hysteresis.
# =============================================================================

const _STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const LOG_NAME: String = "Saffron-Turbo:Interpolator"
const BASE_TELEPORT_DIST: float = 128.0
const FPS_ENABLE_THRESHOLD: float = 63.0
const FPS_DISABLE_THRESHOLD: float = 58.0

var _tree: SceneTree = null
var _state = null
var _jitter_overridden: bool = false
var _orig_jitter_fix: float = 0.5
var _was_paused: bool = false
var _user_enabled: bool = true
var _governor_allowed: bool = true

var _ids: Array = []
var _nodes: Array = []
var _rids: Array = []
var _prev_pos: Array = []
var _curr_pos: Array = []
var _xforms: Array = []
var _synced_static: Array = []
var _id_idx: Dictionary = {}

var _iterating: bool = false
var _pending_unregisters: Dictionary = {}

var _screen_hz: float = 0.0
var _phys_hz: int = 60
var _teleport_dist_sq: float = 16384.0
var _fps_high_active: bool = false
var _connected: bool = false
var _hz_recheck_accum: float = 0.0
var _last_capture_frame: int = -1


func _init() -> void:
	process_priority = 9999


func _ready() -> void:
	process_priority = 9999
	_tree = get_tree()
	_state = _STATE_SCRIPT.HOLDER.get("state")
	if not _jitter_overridden:
		_orig_jitter_fix = Engine.physics_jitter_fix
	if _state != null and not _state.orig_jitter_fix_captured:
		_state.orig_jitter_fix = _orig_jitter_fix
		_state.orig_jitter_fix_captured = true
	_screen_hz = float(OS.get_screen_refresh_rate())
	_phys_hz = int(max(1, Engine.iterations_per_second))
	_update_teleport_threshold(_phys_hz)
	_update_fps_hysteresis()
	_sync_signal_connection()


func _exit_tree() -> void:
	_restore_all_server_transforms()
	if _jitter_overridden:
		Engine.physics_jitter_fix = _orig_jitter_fix
		_jitter_overridden = false
	if _connected:
		if VisualServer.is_connected("frame_pre_draw", self, "_on_frame_pre_draw"):
			VisualServer.disconnect("frame_pre_draw", self, "_on_frame_pre_draw")
		_connected = false
		ModLoaderLog.info("frame_pre_draw disconnected on exit_tree", LOG_NAME)
	_ids.clear()
	_nodes.clear()
	_rids.clear()
	_prev_pos.clear()
	_curr_pos.clear()
	_xforms.clear()
	_synced_static.clear()
	_id_idx.clear()
	_pending_unregisters.clear()


func _physics_process(_delta: float) -> void:
	if _connected:
		capture_physics_snapshot()


func _process(delta: float) -> void:
	_hz_recheck_accum += delta
	if _hz_recheck_accum >= 1.0:
		_hz_recheck_accum = 0.0
		var cur_hz: int = int(max(1, Engine.iterations_per_second))
		if cur_hz != _phys_hz:
			on_physics_hz_changed(cur_hz)
		else:
			_update_fps_hysteresis()
			_sync_signal_connection()


func is_interpolation_active() -> bool:
	return _connected


func get_registered_count() -> int:
	return _nodes.size()


func is_registered(n: Node2D) -> bool:
	return n != null and is_instance_valid(n) and _id_idx.has(n.get_instance_id())


func set_enabled(v: bool) -> void:
	if _user_enabled == v:
		return
	_user_enabled = v
	_sync_signal_connection()


func set_governor_allowed(v: bool) -> void:
	if _governor_allowed == v:
		return
	_governor_allowed = v
	_sync_signal_connection()


func on_physics_hz_changed(new_hz: int) -> void:
	var clamped_hz: int = int(max(1, new_hz))
	_phys_hz = clamped_hz
	_update_teleport_threshold(clamped_hz)
	_sync_signal_connection()


func _update_teleport_threshold(hz: int) -> void:
	var dist: float = BASE_TELEPORT_DIST * 60.0 / float(max(1, hz))
	_teleport_dist_sq = dist * dist


func _update_fps_hysteresis() -> void:
	if _screen_hz > 0.0:
		return
	var fps: float = Engine.get_frames_per_second()
	if _fps_high_active:
		if fps <= FPS_DISABLE_THRESHOLD:
			_fps_high_active = false
	else:
		if fps >= FPS_ENABLE_THRESHOLD:
			_fps_high_active = true


func _is_active() -> bool:
	if not _user_enabled or not _governor_allowed:
		return false
	if _phys_hz < 60:
		return true
	if _screen_hz > 61.0:
		return true
	if _screen_hz <= 0.0:
		return _fps_high_active
	return false


func _sync_signal_connection() -> void:
	var want: bool = _is_active()
	if want and not _connected:
		_resync_all_snapshots()
		_last_capture_frame = -1
		if not VisualServer.is_connected("frame_pre_draw", self, "_on_frame_pre_draw"):
			VisualServer.connect("frame_pre_draw", self, "_on_frame_pre_draw")
		_connected = true
		if not _jitter_overridden:
			_orig_jitter_fix = Engine.physics_jitter_fix
			Engine.physics_jitter_fix = 0.0
			_jitter_overridden = true
		ModLoaderLog.info(
			"frame_pre_draw connected (phys_hz=%d, screen_hz=%.1f, fps=%.1f)" % [_phys_hz, _screen_hz, Engine.get_frames_per_second()],
			LOG_NAME
		)
	elif not want and _connected:
		_restore_all_server_transforms()
		if VisualServer.is_connected("frame_pre_draw", self, "_on_frame_pre_draw"):
			VisualServer.disconnect("frame_pre_draw", self, "_on_frame_pre_draw")
		_connected = false
		if _jitter_overridden:
			Engine.physics_jitter_fix = _orig_jitter_fix
			_jitter_overridden = false
		ModLoaderLog.info(
			"frame_pre_draw disconnected (phys_hz=%d, screen_hz=%.1f, fps=%.1f)" % [_phys_hz, _screen_hz, Engine.get_frames_per_second()],
			LOG_NAME
		)


func _resync_all_snapshots() -> void:
	var count: int = _nodes.size()
	var i: int = 0
	_iterating = true
	while i < count:
		var n = _nodes[i]
		if is_instance_valid(n):
			var p: Vector2 = n.position
			_prev_pos[i] = p
			_curr_pos[i] = p
			_xforms[i] = n.transform
			_synced_static[i] = false
		else:
			_pending_unregisters[_ids[i]] = true
		i += 1
	_iterating = false
	_flush_pending_unregisters()


func _restore_all_server_transforms() -> void:
	var count: int = _nodes.size()
	var i: int = 0
	_iterating = true
	while i < count:
		var n = _nodes[i]
		if is_instance_valid(n):
			VisualServer.canvas_item_set_transform(_rids[i], n.transform)
		else:
			_pending_unregisters[_ids[i]] = true
		i += 1
	_iterating = false
	_flush_pending_unregisters()


func register_node(n: Node2D) -> void:
	if n == null or not is_instance_valid(n):
		return
	var nid: int = n.get_instance_id()
	if _id_idx.has(nid):
		if _pending_unregisters.has(nid):
			_pending_unregisters.erase(nid)
		var existing_idx: int = int(_id_idx[nid])
		var ep: Vector2 = n.position
		var ex: Transform2D = n.transform
		_prev_pos[existing_idx] = ep
		_curr_pos[existing_idx] = ep
		_xforms[existing_idx] = ex
		_synced_static[existing_idx] = true
		_rids[existing_idx] = n.get_canvas_item()
		VisualServer.canvas_item_set_transform(_rids[existing_idx], ex)
		return
	var p: Vector2 = n.position
	var rid: RID = n.get_canvas_item()
	_id_idx[nid] = _nodes.size()
	_ids.push_back(nid)
	_nodes.push_back(n)
	_rids.push_back(rid)
	_prev_pos.push_back(p)
	_curr_pos.push_back(p)
	_xforms.push_back(n.transform)
	_synced_static.push_back(true)


func reset_node_snapshot(n: Node2D) -> void:
	if n == null or not is_instance_valid(n):
		return
	var nid: int = n.get_instance_id()
	if not _id_idx.has(nid):
		return
	var idx: int = int(_id_idx[nid])
	var p: Vector2 = n.position
	var rx: Transform2D = n.transform
	_prev_pos[idx] = p
	_curr_pos[idx] = p
	_xforms[idx] = rx
	_synced_static[idx] = true
	VisualServer.canvas_item_set_transform(_rids[idx], rx)


func unregister_node(n: Node2D) -> void:
	if n == null or not is_instance_valid(n):
		return
	var nid: int = n.get_instance_id()
	if not _id_idx.has(nid):
		return
	if _iterating:
		_pending_unregisters[nid] = true
		return
	_remove_id_now(nid)


func _remove_id_now(nid: int) -> void:
	if not _id_idx.has(nid):
		return
	var idx: int = int(_id_idx[nid])
	var last_idx: int = _nodes.size() - 1
	if idx >= 0 and idx <= last_idx:
		var n = _nodes[idx]
		if is_instance_valid(n):
			VisualServer.canvas_item_set_transform(_rids[idx], n.transform)
		if idx != last_idx:
			var moved_id: int = int(_ids[last_idx])
			_ids[idx] = moved_id
			_nodes[idx] = _nodes[last_idx]
			_rids[idx] = _rids[last_idx]
			_prev_pos[idx] = _prev_pos[last_idx]
			_curr_pos[idx] = _curr_pos[last_idx]
			_xforms[idx] = _xforms[last_idx]
			_synced_static[idx] = _synced_static[last_idx]
			_id_idx[moved_id] = idx
		_ids.pop_back()
		_nodes.pop_back()
		_rids.pop_back()
		_prev_pos.pop_back()
		_curr_pos.pop_back()
		_xforms.pop_back()
		_synced_static.pop_back()
	_id_idx.erase(nid)


func _flush_pending_unregisters() -> void:
	if _pending_unregisters.empty():
		return
	var keys: Array = _pending_unregisters.keys()
	_pending_unregisters.clear()
	var i: int = 0
	var count: int = keys.size()
	while i < count:
		_remove_id_now(int(keys[i]))
		i += 1


func capture_physics_snapshot() -> void:
	if not _connected:
		return
	var frame: int = Engine.get_physics_frames()
	if frame == _last_capture_frame:
		return
	_last_capture_frame = frame

	var count: int = _nodes.size()
	if count == 0:
		return
	var dist_sq: float = _teleport_dist_sq
	var i: int = 0
	_iterating = true
	while i < count:
		var n = _nodes[i]
		if is_instance_valid(n):
			var xf: Transform2D = n.transform
			var cur: Vector2 = xf.origin
			var prev: Vector2 = _curr_pos[i]
			var dx: float = cur.x - prev.x
			var dy: float = cur.y - prev.y
			if dx * dx + dy * dy > dist_sq:
				_prev_pos[i] = cur
			else:
				_prev_pos[i] = prev
			_curr_pos[i] = cur
			if dx != 0.0 or dy != 0.0 or xf != _xforms[i]:
				_xforms[i] = xf
				_synced_static[i] = false
		else:
			_pending_unregisters[_ids[i]] = true
		i += 1
	_iterating = false
	_flush_pending_unregisters()


func _on_frame_pre_draw() -> void:
	if _tree != null and _tree.paused:
		if not _was_paused:
			_was_paused = true
			_restore_all_server_transforms()
		return
	elif _was_paused:
		_was_paused = false
		_resync_all_snapshots()
		return

	var count: int = _nodes.size()
	if count == 0:
		return
	var frac: float = clamp(Engine.get_physics_interpolation_fraction(), 0.0, 1.0)
	var s = _state
	if s == null:
		s = _STATE_SCRIPT.HOLDER.get("state")
		_state = s
	var use_cull: bool = (s != null and s.cam_valid)
	var cam_rect: Rect2 = s.cam_rect_unit if use_cull else Rect2()

	var i: int = 0
	_iterating = true
	while i < count:
		var n = _nodes[i]
		if is_instance_valid(n):
			if n.visible and n.is_inside_tree():
				var p0: Vector2 = _prev_pos[i]
				var p1: Vector2 = _curr_pos[i]
				if p0.x == p1.x and p0.y == p1.y:
					if not _synced_static[i]:
						VisualServer.canvas_item_set_transform(_rids[i], n.transform)
						_synced_static[i] = true
					i += 1
					continue
				if use_cull and not cam_rect.has_point(p1) and not cam_rect.has_point(p0):
					i += 1
					continue
				var xform: Transform2D = n.transform
				xform.origin = Vector2(p0.x + (p1.x - p0.x) * frac, p0.y + (p1.y - p0.y) * frac)
				VisualServer.canvas_item_set_transform(_rids[i], xform)
		else:
			_pending_unregisters[_ids[i]] = true
		i += 1
	_iterating = false
	_flush_pending_unregisters()

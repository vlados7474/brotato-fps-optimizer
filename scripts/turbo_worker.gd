extends Reference
# =============================================================================
# Saffron-Turbo 5.6.1 - Hardened Zero-Alloc Persistent Worker Thread (Godot 3.x)
# -----------------------------------------------------------------------------
# Thread-safety invariants verified against Godot 3.6/3.7 internals:
#   - Worker NEVER holds or drops any Node/Object Variant reference (only plain
#     64-bit int instance_ids in regular Arrays, never PoolIntArray).
#   - instance_from_id() is called EXCLUSIVELY on the main thread.
#   - 5-slot pre-allocated buffer pool eliminates per-snapshot Array/Dict allocs.
#   - Strict bounding-box clamping prevents infinite loops on huge query radii.
#   - stop() unconditionally posts Semaphore, joins wait_to_finish(), and resets
#     all sequence/frame counters so start()->stop()->start() is 100% safe.
# =============================================================================

const CELL_SIZE: float = 160.0
const INV_CELL: float = 1.0 / CELL_SIZE
const MIN_CELL_COORD: int = -512
const MAX_CELL_COORD: int = 3583
const BOUNDARY_EPS: float = 0.001
const _EMPTY_ARRAY: Array = []
const CELL_BIAS: int = 512
const CELL_SHIFT: int = 12
const CELL_MASK: int = 0xFFF

var _thread: Thread = null
var _mutex: Mutex = null
var _sem: Semaphore = null

var _running: bool = false
var _stop_requested: bool = false
var _has_pending_job: bool = false
var _has_ready_result: bool = false
var _job_seq: int = 0
var _done_seq: int = 0
var _min_valid_seq: int = 0

var _write_slot: Dictionary = {}
var _pending_slot: Dictionary = {}
var _work_slot: Dictionary = {}
var _ready_slot: Dictionary = {}
var _front_slot: Dictionary = {}

var _query_out: Array = []


static func _make_slot() -> Dictionary:
	return {
		"xs": [],
		"ys": [],
		"ids": [],
		"count": 0,
		"frame": -1,
		"seq": 0,
		"cells": {},
		"active_keys": [],
		"min_cx": MAX_CELL_COORD,
		"max_cx": MIN_CELL_COORD,
		"min_cy": MAX_CELL_COORD,
		"max_cy": MIN_CELL_COORD,
		"max_density": 0,
		"hot_cells": 0
	}


static func _clear_slot_cells(slot: Dictionary) -> void:
	var cells: Dictionary = slot["cells"]
	var active: Array = slot["active_keys"]
	for key in active:
		(cells[key] as Array).clear()
	active.clear()


func start() -> bool:
	if _running:
		if _thread != null and _thread.is_alive():
			return true
		stop()
	_write_slot = _make_slot()
	_pending_slot = _make_slot()
	_work_slot = _make_slot()
	_ready_slot = _make_slot()
	_front_slot = _make_slot()
	_job_seq = 0
	_done_seq = 0
	_min_valid_seq = 0
	_has_pending_job = false
	_has_ready_result = false
	_stop_requested = false

	_mutex = Mutex.new()
	_sem = Semaphore.new()
	_thread = Thread.new()
	var err: int = _thread.start(self, "_worker_loop")
	if err != OK:
		_thread = null
		_mutex = null
		_sem = null
		_write_slot = {}
		_pending_slot = {}
		_work_slot = {}
		_ready_slot = {}
		_front_slot = {}
		return false
	_running = true
	return true


func stop() -> void:
	if not _running:
		return
	_mutex.lock()
	_stop_requested = true
	_has_pending_job = false
	_has_ready_result = false
	_mutex.unlock()
	_sem.post()
	if _thread != null and _thread.is_active():
		_thread.wait_to_finish()
	_running = false
	_thread = null
	_mutex = null
	_sem = null
	_job_seq = 0
	_done_seq = 0
	_min_valid_seq = 0
	_write_slot = {}
	_pending_slot = {}
	_work_slot = {}
	_ready_slot = {}
	_front_slot = {}
	_query_out.clear()


func invalidate() -> void:
	if not _running or _mutex == null:
		return
	_mutex.lock()
	_min_valid_seq = _job_seq
	_has_pending_job = false
	_has_ready_result = false
	if _pending_slot.has("frame"):
		_pending_slot["frame"] = -1
		_pending_slot["count"] = 0
	if _ready_slot.has("frame"):
		_ready_slot["frame"] = -1
		_ready_slot["count"] = 0
	_mutex.unlock()
	if _front_slot.has("frame"):
		_front_slot["frame"] = -1
		_front_slot["count"] = 0
	_query_out.clear()


func is_running() -> bool:
	return _running and _thread != null and _thread.is_alive()


func get_completed_seq() -> int:
	if not _running or _mutex == null:
		return 0
	_mutex.lock()
	var seq: int = _done_seq
	_mutex.unlock()
	return seq


func submit_snapshot(enemies: Array, phys_frame: int, bosses: Array = _EMPTY_ARRAY) -> bool:
	if not _running or _mutex == null or _sem == null:
		return false
	if _thread == null or not _thread.is_alive():
		return false

	var e_cnt: int = enemies.size()
	var b_cnt: int = bosses.size()
	var total: int = e_cnt + b_cnt
	if total == 0:
		invalidate()
		return false

	var slot: Dictionary = _write_slot
	var xs: Array = slot["xs"]
	var ys: Array = slot["ys"]
	var ids: Array = slot["ids"]
	if xs.size() < total:
		xs.resize(total)
		ys.resize(total)
		ids.resize(total)

	var n: int = 0
	var i: int = 0
	while i < e_cnt:
		var e = enemies[i]
		if is_instance_valid(e) and not e.dead and not e.is_queued_for_deletion():
			var p: Vector2 = e.global_position
			xs[n] = p.x
			ys[n] = p.y
			ids[n] = e.get_instance_id()
			n += 1
		i += 1
	i = 0
	while i < b_cnt:
		var b = bosses[i]
		if is_instance_valid(b) and not b.dead and not b.is_queued_for_deletion():
			var bp: Vector2 = b.global_position
			xs[n] = bp.x
			ys[n] = bp.y
			ids[n] = b.get_instance_id()
			n += 1
		i += 1
	if n == 0:
		invalidate()
		return false

	slot["count"] = n
	slot["frame"] = phys_frame

	_mutex.lock()
	_job_seq += 1
	slot["seq"] = _job_seq
	var tmp: Dictionary = _pending_slot
	_pending_slot = slot
	_write_slot = tmp
	var should_post: bool = not _has_pending_job
	_has_pending_job = true
	_mutex.unlock()

	if should_post:
		_sem.post()
	return true


func _worker_loop(_userdata = null) -> void:
	while true:
		_sem.wait()

		_mutex.lock()
		if _stop_requested:
			_mutex.unlock()
			return
		if not _has_pending_job:
			_mutex.unlock()
			continue
		var slot: Dictionary = _pending_slot
		_pending_slot = _work_slot
		_work_slot = slot
		_has_pending_job = false
		_mutex.unlock()

		_clear_slot_cells(slot)
		var xs: Array = slot["xs"]
		var ys: Array = slot["ys"]
		var n: int = int(slot["count"])
		var cells: Dictionary = slot["cells"]
		var active: Array = slot["active_keys"]

		var min_cx: int = MAX_CELL_COORD
		var max_cx: int = MIN_CELL_COORD
		var min_cy: int = MAX_CELL_COORD
		var max_cy: int = MIN_CELL_COORD
		var max_density: int = 0
		var hot_cells: int = 0

		var i: int = 0
		while i < n:
			var cx: int = _clamp_cell_coord(floor(float(xs[i]) * INV_CELL))
			var cy: int = _clamp_cell_coord(floor(float(ys[i]) * INV_CELL))

			if cx < min_cx:
				min_cx = cx
			if cx > max_cx:
				max_cx = cx
			if cy < min_cy:
				min_cy = cy
			if cy > max_cy:
				max_cy = cy

			var key: int = ((cx + CELL_BIAS) << CELL_SHIFT) | ((cy + CELL_BIAS) & CELL_MASK)
			var bucket = cells.get(key)
			if bucket == null:
				bucket = [i]
				cells[key] = bucket
				active.append(key)
			else:
				if bucket.empty():
					active.append(key)
				bucket.append(i)
			var bsz: int = bucket.size()
			if bsz > max_density:
				max_density = bsz
			if bsz == 8:
				hot_cells += 1
			i += 1

		slot["min_cx"] = min_cx
		slot["max_cx"] = max_cx
		slot["min_cy"] = min_cy
		slot["max_cy"] = max_cy
		slot["max_density"] = max_density
		slot["hot_cells"] = hot_cells

		_mutex.lock()
		if _stop_requested:
			_mutex.unlock()
			return
		var seq: int = int(slot["seq"])
		if seq > _min_valid_seq:
			var old_ready: Dictionary = _ready_slot
			_ready_slot = slot
			_work_slot = old_ready
			_has_ready_result = true
			_done_seq = seq
		_mutex.unlock()


func _pull_front_slot() -> Dictionary:
	_mutex.lock()
	if _has_ready_result:
		var tmp: Dictionary = _front_slot
		_front_slot = _ready_slot
		_ready_slot = tmp
		_has_ready_result = false
	_mutex.unlock()
	return _front_slot


static func _clamp_cell_coord(val: float) -> int:
	if val <= float(MIN_CELL_COORD):
		return MIN_CELL_COORD
	if val >= float(MAX_CELL_COORD):
		return MAX_CELL_COORD
	return int(val)


func try_query_radius(origin: Vector2, radius: float, cur_phys_frame: int, max_age_frames: int = 3):
	if not _running or _mutex == null or radius < 0.0 or is_nan(radius):
		return null

	var slot: Dictionary = _pull_front_slot()
	var count: int = int(slot.get("count", 0))
	var frame_id: int = int(slot.get("frame", -1))
	if count <= 0 or frame_id < 0 or cur_phys_frame < frame_id or (cur_phys_frame - frame_id) > max_age_frames:
		return null

	_query_out.clear()
	var ox: float = origin.x
	var oy: float = origin.y
	var r_sq: float = radius * radius

	var q_min_cx: int = _clamp_cell_coord(floor((ox - radius - BOUNDARY_EPS) * INV_CELL))
	var q_max_cx: int = _clamp_cell_coord(floor((ox + radius + BOUNDARY_EPS) * INV_CELL))
	var q_min_cy: int = _clamp_cell_coord(floor((oy - radius - BOUNDARY_EPS) * INV_CELL))
	var q_max_cy: int = _clamp_cell_coord(floor((oy + radius + BOUNDARY_EPS) * INV_CELL))

	var s_min_cx: int = int(slot["min_cx"])
	var s_max_cx: int = int(slot["max_cx"])
	var s_min_cy: int = int(slot["min_cy"])
	var s_max_cy: int = int(slot["max_cy"])

	var min_cx: int = q_min_cx if q_min_cx > s_min_cx else s_min_cx
	var max_cx: int = q_max_cx if q_max_cx < s_max_cx else s_max_cx
	var min_cy: int = q_min_cy if q_min_cy > s_min_cy else s_min_cy
	var max_cy: int = q_max_cy if q_max_cy < s_max_cy else s_max_cy
	if min_cx > max_cx or min_cy > max_cy:
		return _query_out

	var cells: Dictionary = slot["cells"]
	var ids: Array = slot["ids"]
	var xs: Array = slot["xs"]
	var ys: Array = slot["ys"]

	var cx: int = min_cx
	while cx <= max_cx:
		var cy: int = min_cy
		while cy <= max_cy:
			var key: int = ((cx + CELL_BIAS) << CELL_SHIFT) | ((cy + CELL_BIAS) & CELL_MASK)
			var bucket = cells.get(key)
			if bucket != null and not bucket.empty():
				for idx in bucket:
					var dx: float = float(xs[idx]) - ox
					var dy: float = float(ys[idx]) - oy
					if dx * dx + dy * dy <= r_sq:
						var e = instance_from_id(int(ids[idx]))
						if e != null and is_instance_valid(e) and not e.dead and not e.is_queued_for_deletion():
							_query_out.append(e)
			cy += 1
		cx += 1

	return _query_out

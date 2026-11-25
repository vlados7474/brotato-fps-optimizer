extends Reference
# =============================================================================
# Saffron-Turbo 5.6.1 - Lazy Zero-Alloc Spatial Hash Grid (160px cells)
# -----------------------------------------------------------------------------
# Uses the background TurboWorker snapshot when enable_worker_thread is active
# and a fresh off-thread grid is ready; otherwise rebuilds lazily at most once
# per physics frame ONLY when query_radius() is called (0.000 ms on light runs).
# =============================================================================

const CELL_SIZE: float = 160.0
const INV_CELL_SIZE: float = 1.0 / CELL_SIZE
const MIN_CELL_COORD: int = -512
const MAX_CELL_COORD: int = 3583
const CELL_BIAS: int = 512
const CELL_SHIFT: int = 12
const CELL_MASK: int = 0xFFF
const BOUNDARY_EPS: float = 0.001


static func _clamp_cell_coord(val: float) -> int:
	if val <= float(MIN_CELL_COORD):
		return MIN_CELL_COORD
	if val >= float(MAX_CELL_COORD):
		return MAX_CELL_COORD
	return int(val)

var worker = null
var _cells: Dictionary = {}
var _active_keys: Array = []
var _query_results: Array = []
var _built_physics_frame: int = -1


func clear() -> void:
	for key in _active_keys:
		var bucket: Array = _cells[key]
		bucket.clear()
	_active_keys.clear()
	_query_results.clear()
	_built_physics_frame = -1
	if worker != null and worker.has_method("invalidate"):
		worker.invalidate()


func _clear_active_cells() -> void:
	for key in _active_keys:
		var bucket: Array = _cells[key]
		bucket.clear()
	_active_keys.clear()


func _rebuild(enemies: Array, phys_frame: int) -> void:
	_clear_active_cells()
	_built_physics_frame = phys_frame

	for enemy in enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var pos: Vector2 = enemy.global_position
		var cx: int = int(floor(pos.x * INV_CELL_SIZE))
		var cy: int = int(floor(pos.y * INV_CELL_SIZE))
		if cx < MIN_CELL_COORD:
			cx = MIN_CELL_COORD
		elif cx > MAX_CELL_COORD:
			cx = MAX_CELL_COORD
		if cy < MIN_CELL_COORD:
			cy = MIN_CELL_COORD
		elif cy > MAX_CELL_COORD:
			cy = MAX_CELL_COORD

		var key: int = ((cx + CELL_BIAS) << CELL_SHIFT) | ((cy + CELL_BIAS) & CELL_MASK)
		var bucket = _cells.get(key)
		if bucket == null:
			bucket = []
			_cells[key] = bucket
			_active_keys.append(key)
		elif bucket.empty():
			_active_keys.append(key)
		bucket.append(enemy)


func query_radius(center: Vector2, radius: float, enemies: Array) -> Array:
	_query_results.clear()
	if radius < 0.0 or is_nan(radius):
		return _query_results

	var phys_frame: int = Engine.get_physics_frames()
	if worker != null and worker.is_running():
		var w_res = worker.try_query_radius(center, radius, phys_frame, 3)
		if w_res != null:
			return w_res

	if enemies.empty():
		return _query_results

	if _built_physics_frame != phys_frame:
		_rebuild(enemies, phys_frame)

	if _active_keys.empty():
		return _query_results

	var ox: float = center.x
	var oy: float = center.y
	var r_sq: float = radius * radius

	var min_cx: int = _clamp_cell_coord(floor((ox - radius - BOUNDARY_EPS) * INV_CELL_SIZE))
	var max_cx: int = _clamp_cell_coord(floor((ox + radius + BOUNDARY_EPS) * INV_CELL_SIZE))
	var min_cy: int = _clamp_cell_coord(floor((oy - radius - BOUNDARY_EPS) * INV_CELL_SIZE))
	var max_cy: int = _clamp_cell_coord(floor((oy + radius + BOUNDARY_EPS) * INV_CELL_SIZE))

	var cx: int = min_cx
	while cx <= max_cx:
		var cy: int = min_cy
		while cy <= max_cy:
			var key: int = ((cx + CELL_BIAS) << CELL_SHIFT) | ((cy + CELL_BIAS) & CELL_MASK)
			var bucket = _cells.get(key)
			if bucket != null and not bucket.empty():
				for enemy in bucket:
					if not is_instance_valid(enemy) or enemy.dead:
						continue
					var epos: Vector2 = enemy.global_position
					var dx: float = epos.x - ox
					var dy: float = epos.y - oy
					if dx <= radius and dx >= -radius and dy <= radius and dy >= -radius:
						if dx * dx + dy * dy <= r_sq:
							_query_results.append(enemy)
			cy += 1
		cx += 1

	return _query_results

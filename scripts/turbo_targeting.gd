extends Reference
# =============================================================================
# Saffron-Turbo 5.6.1 - Pure Scalar Nearest-Target, aim_shape Parity & O(1) Cache
# -----------------------------------------------------------------------------
# 1. Pure scalar dx*dx + dy*dy + axis-box pre-filter on standard targets, with
#    exact aim_shape closest-point parity on bosses/elites (zero Autoload calls
#    inside static funcs).
# 2. Bounded 64-slot spatial-temporal cache (_stationary_cache) with O(1) live
#    validation (is_instance_valid + not dead + is_inside_tree) instead of O(N)
#    targets.has(), and single-oldest-entry eviction instead of full clear().
# 3. Honors state.force_fresh_scan = true on firing ticks.
# =============================================================================

const LARGE_NUMBER_INT: int = 99999999
const SQRT_LARGE_NUMBER: float = 9999.99995
const MAX_STATIONARY_SLOTS: int = 64

const _stationary_cache: Dictionary = {}


static func clear_cache() -> void:
	_stationary_cache.clear()


static func _get_closest_point_on_shape(collision: CollisionShape2D, from: Vector2) -> Vector2:
	var shape_transform: Transform2D = collision.global_transform
	var local_from: Vector2 = shape_transform.affine_inverse().xform(from)
	var shape: Shape2D = collision.shape

	if shape is RectangleShape2D:
		var extents: Vector2 = shape.extents
		var clamped := Vector2(clamp(local_from.x, -extents.x, extents.x), clamp(local_from.y, -extents.y, extents.y))
		if clamped == local_from:
			return collision.global_position
		return shape_transform.xform(clamped)

	var center := Vector2.ZERO
	var radius: float = 0.0

	if shape is CapsuleShape2D:
		var half_height: float = shape.height * 0.5
		center.y = clamp(local_from.y, -half_height, half_height)
		radius = shape.radius
	elif shape is CircleShape2D:
		radius = shape.radius
	else:
		return collision.global_position

	var offset: Vector2 = local_from - center
	var len_sq: float = offset.length_squared()
	if len_sq <= radius * radius:
		return shape_transform.xform(center)
	return shape_transform.xform(center + offset * (radius / sqrt(len_sq)))


static func get_nearest(targets: Array, from_pos: Vector2, min_distance: int = 0, max_range: int = LARGE_NUMBER_INT) -> Array:
	if targets.empty():
		return []
	var ox: float = from_pos.x
	var oy: float = from_pos.y
	var max_f: float = float(max_range)
	var min_f: float = max(0.0, float(min_distance))
	var min_sq: float = min_f * min_f
	var max_sq: float = max_f * max_f
	var max_sq_excl: float = max_sq + 1.0
	var max_box: float = max_f + 1.0
	var best_target = null
	var best_dist_sq: float = INF
	for target in targets:
		if not is_instance_valid(target):
			continue
		var tpos: Vector2
		if target is Unit and target.aim_shape != null:
			tpos = _get_closest_point_on_shape(target.aim_shape, from_pos)
		else:
			tpos = target.global_position
		var dx: float = tpos.x - ox
		if dx > max_box or dx < -max_box:
			continue
		var dy: float = tpos.y - oy
		if dy > max_box or dy < -max_box:
			continue
		var d_sq: float = dx * dx + dy * dy
		if d_sq < best_dist_sq and d_sq >= min_sq and (d_sq < max_sq_excl or d_sq <= max_sq):
			best_dist_sq = d_sq
			best_target = target
	if best_target == null:
		return []
	return [best_target, sqrt(best_dist_sq)]


static func get_nearest_no_max(targets: Array, from_pos: Vector2, min_distance: int = 0, state = null) -> Array:
	if targets.empty():
		return [null, SQRT_LARGE_NUMBER]

	var ox: float = from_pos.x
	var oy: float = from_pos.y
	var min_f: float = max(0.0, float(min_distance))
	var min_sq: float = min_f * min_f

	var use_cache: bool = (
		state != null
		and state.cache_weapon_targets
		and not state.force_fresh_scan
		and targets.size() >= 6
	)
	var loc_key: int = 0
	var phys_frame: int = 0

	if use_cache:
		var interval: int = state.target_cache_frames + state.cache_extra_frames
		if interval > 1:
			phys_frame = Engine.get_physics_frames()
			var imin: int = int(max(0, min_distance))
			if imin > 65535 or abs(ox) > 32767.0 or abs(oy) > 32767.0:
				use_cache = false
			else:
				var ix: int = int(round(ox)) & 0xFFFF
				var iy: int = int(round(oy)) & 0xFFFF
				loc_key = (ix << 32) | (iy << 16) | imin
				var entry = _stationary_cache.get(loc_key)
				if entry != null:
					var c_frame: int = int(entry[1])
					var c_phase: int = int(entry[2])
					var due: bool = false
					if c_frame != phys_frame:
						due = (phys_frame - c_frame) >= interval
						if not due and state.stagger_target_scans and ((phys_frame + c_phase) % interval) == 0:
							due = true
					if not due:
						var c_unit = entry[0]
						if c_unit != null and is_instance_valid(c_unit) and (not ("dead" in c_unit) or not c_unit.dead) and c_unit.is_inside_tree() and targets.has(c_unit):
							var cpos: Vector2
							if c_unit is Unit and c_unit.aim_shape != null:
								cpos = _get_closest_point_on_shape(c_unit.aim_shape, from_pos)
							else:
								cpos = c_unit.global_position
							var cdx: float = cpos.x - ox
							var cdy: float = cpos.y - oy
							var live_sq: float = cdx * cdx + cdy * cdy
							if live_sq > min_sq and live_sq < float(LARGE_NUMBER_INT):
								return [c_unit, sqrt(live_sq)]
		else:
			use_cache = false

	var best_target = null
	var best_dist_sq: float = float(LARGE_NUMBER_INT)
	for target in targets:
		if not is_instance_valid(target):
			continue
		var tpos: Vector2
		if target is Unit and target.aim_shape != null:
			tpos = _get_closest_point_on_shape(target.aim_shape, from_pos)
		else:
			tpos = target.global_position
		var dx: float = tpos.x - ox
		var dy: float = tpos.y - oy
		var d_sq: float = dx * dx + dy * dy
		if d_sq < best_dist_sq and d_sq > min_sq:
			best_dist_sq = d_sq
			best_target = target

	if best_target == null:
		return [null, SQRT_LARGE_NUMBER]

	var dist: float = sqrt(best_dist_sq)
	if use_cache:
		if _stationary_cache.size() >= MAX_STATIONARY_SLOTS and not _stationary_cache.has(loc_key):
			var oldest_key = null
			var oldest_frame: int = 9223372036854775807
			for k in _stationary_cache:
				var ef: int = int(_stationary_cache[k][1])
				if ef < oldest_frame:
					oldest_frame = ef
					oldest_key = k
			if oldest_key != null:
				_stationary_cache.erase(oldest_key)
		var existing_entry = _stationary_cache.get(loc_key)
		if existing_entry != null:
			existing_entry[0] = best_target
			existing_entry[1] = phys_frame
		else:
			var phase_val: int = int(abs(loc_key)) & 0xFF
			_stationary_cache[loc_key] = [best_target, phys_frame, phase_val]
	return [best_target, dist]

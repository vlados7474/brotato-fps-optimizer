extends "res://global/gpe_spawner.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Zero-Throwaway GPE Hole Radius Cache (_turbo_gpe_)
# =============================================================================

const _turbo_gpe_MAX_ATTEMPTS: int = 64

var _turbo_gpe_hole_radius: float = -1.0
var _turbo_gpe_hole_scene_id: int = -1


func _turbo_gpe_extract_radius(hole_node: Node) -> float:
	if hole_node != null:
		var col = hole_node.get_node_or_null("CollisionShape2D")
		if col != null and col.shape != null and ("radius" in col.shape):
			return float(col.shape.radius) * 1.3
	return 64.0


func spawn_holes() -> Array:
	var result: Array = []
	if hole == null or _gpe_container == null:
		return result

	var scene_id: int = hole.get_instance_id()
	if scene_id != _turbo_gpe_hole_scene_id:
		_turbo_gpe_hole_scene_id = scene_id
		_turbo_gpe_hole_radius = -1.0

	var radius: float = _turbo_gpe_hole_radius
	var min_dist_sq: float = (2.0 * radius) * (2.0 * radius) if radius >= 0.0 else 0.0

	for _i in 10:
		var pos: Vector2 = Vector2.ZERO
		if result.empty():
			pos = ZoneService.get_rand_pos()
		else:
			var valid_pos: bool = false
			var attempts: int = 0
			while not valid_pos and attempts < _turbo_gpe_MAX_ATTEMPTS:
				attempts += 1
				pos = ZoneService.get_rand_pos()
				valid_pos = true
				for existing in result:
					var cpos: Vector2 = existing.center
					var dx: float = pos.x - cpos.x
					var dy: float = pos.y - cpos.y
					if dx * dx + dy * dy < min_dist_sq:
						valid_pos = false
						break

		var hole_instance = hole.instance()
		if radius < 0.0:
			radius = _turbo_gpe_extract_radius(hole_instance)
			_turbo_gpe_hole_radius = radius
			min_dist_sq = (2.0 * radius) * (2.0 * radius)

		hole_instance.global_position = pos
		result.append({
			"center": pos,
			"radius": radius
		})
		_gpe_container.add_child(hole_instance)

	return result

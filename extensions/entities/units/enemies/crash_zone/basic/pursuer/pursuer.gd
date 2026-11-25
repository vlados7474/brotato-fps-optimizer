extends "res://entities/units/enemies/crash_zone/basic/pursuer/pursuer.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Pursuer / Viperfish Pooled Scale Reset (_turbo_purs_)
# Path fixed for the real 1.2.0.3 pck layout (crash_zone/basic/pursuer);
# the 5.0.0 path entities/units/enemies/pursuer/ never existed in any build.
# =============================================================================

var _turbo_purs_ready_done: bool = false
var _turbo_purs_root_scale: Vector2 = Vector2.ONE
var _turbo_purs_phys_scales: Array = []
var _turbo_purs_vis_scales: Array = []


func _ready(): # ADDITION
	_turbo_purs_capture_baseline()
	if not is_connected("died", self, "_turbo_purs_on_died"):
		var _err = connect("died", self, "_turbo_purs_on_died")
	_turbo_purs_ready_done = true


func respawn() -> void:
	.respawn()
	if _turbo_purs_ready_done:
		_turbo_purs_reset_scales()


func _turbo_purs_on_died(_entity = null, _args = null) -> void:
	# Visual scale is preserved during death animation and cleanly reset in respawn().
	pass


func _turbo_purs_capture_baseline() -> void:
	_turbo_purs_root_scale = scale
	_turbo_purs_phys_scales.clear()
	_turbo_purs_vis_scales.clear()
	var seen: Dictionary = {}

	var phys_paths: Array = [
		"Collision",
		"CollisionShape2D",
		"Hitbox",
		"Hitbox/Collision",
		"Hitbox/CollisionShape2D",
		"Hurtbox",
		"Hurtbox/Collision",
		"Hurtbox/CollisionShape2D"
	]
	for rel in phys_paths:
		var p_node: Node = get_node_or_null(rel)
		if p_node is Node2D and not seen.has(p_node):
			seen[p_node] = true
			_turbo_purs_phys_scales.push_back([p_node, p_node.scale])

	var vis_paths: Array = ["Animation", "Sprite", "Animation/Sprite"]
	for v_rel in vis_paths:
		var v_node: Node = get_node_or_null(v_rel)
		if v_node is Node2D and not seen.has(v_node):
			seen[v_node] = true
			var is_spr: bool = (v_node is Sprite) or (v_node is AnimatedSprite) or ("Sprite" in v_node.name)
			_turbo_purs_vis_scales.push_back([v_node, v_node.scale, is_spr])


func _turbo_purs_reset_scales() -> void:
	if scale != _turbo_purs_root_scale:
		set_deferred("scale", _turbo_purs_root_scale)

	for entry in _turbo_purs_phys_scales:
		var p_node: Node2D = entry[0]
		var base_s: Vector2 = entry[1]
		if is_instance_valid(p_node) and p_node.scale != base_s:
			p_node.scale = base_s

	for v_entry in _turbo_purs_vis_scales:
		var v_node: Node2D = v_entry[0]
		var v_base: Vector2 = v_entry[1]
		var keep_sign: bool = v_entry[2]
		if is_instance_valid(v_node):
			var target_s: Vector2 = v_base
			if keep_sign:
				target_s = Vector2(-abs(v_base.x) if v_node.scale.x < 0.0 else abs(v_base.x), v_base.y)
			if v_node.scale != target_s:
				v_node.scale = target_s

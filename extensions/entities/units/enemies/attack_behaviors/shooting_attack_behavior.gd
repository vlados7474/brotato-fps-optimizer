extends "res://entities/units/enemies/attack_behaviors/shooting_attack_behavior.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - ShootingAttackBehavior Hot-Path Optimization (_turbo_sab_)
# =============================================================================

const _turbo_sab_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_sab_MAT_POOL = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_material_pool.gd")
const _turbo_sab_BAKER = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_projectile_baker.gd")

var _turbo_sab_state = null
var _turbo_sab_main = null


func physics_process(delta: float) -> void:
	var s = _turbo_sab_state
	if s == null:
		s = _turbo_sab_STATE_SCRIPT.HOLDER.get("state")
		_turbo_sab_state = s
	if s != null and not s.optimize_attack_behaviors:
		.physics_process(delta)
		return

	var step: float = 60.0 * delta
	if _current_initial_cooldown > 0:
		_current_initial_cooldown = max(_current_initial_cooldown - step, 0.0)
		return

	if _current_cd > 0.0:
		_current_cd = max(_current_cd - step, 0.0)

	if _recovery_cooldown > 0.0:
		_recovery_cooldown = max(_recovery_cooldown - step, 0.0)
		if _recovery_cooldown <= 0.0 and move_locked:
			_parent._move_locked = false
			_parent._can_move = true
			_parent._current_movement_behavior.get_movement()

	if not move_locked and (_current_cd > 0.0 or _recovery_cooldown > 0.0 or max_range < 0):
		return

	var playing_shoot: bool = _parent.is_playing_shoot_animation()
	if playing_shoot:
		if move_locked:
			_parent._move_locked = true
			_parent._can_move = false
		return

	if _current_cd <= 0.0 and _recovery_cooldown <= 0.0 and max_range >= 0:
		var tgt = _parent.current_target
		if not is_instance_valid(tgt):
			return
		var ppos: Vector2 = _parent.global_position
		var tpos: Vector2 = tgt.global_position
		var tx: float = tpos.x
		var ty: float = tpos.y
		var dx: float = tx - ppos.x
		var dy: float = ty - ppos.y
		var d_sq: float = dx * dx + dy * dy
		var min_f: float = float(min_range) if min_range > 0 else 0.0
		var max_next: float = float(max_range + 1)
		if d_sq >= min_f * min_f and d_sq < max_next * max_next:
			_parent._animation_player.playback_speed = attack_anim_speed
			_parent._animation_player.play(_parent.shoot_animation_name)
			emit_signal("shot")


func spawn_projectile(rot: float, pos: Vector2, spd: int) -> Node:
	var s = _turbo_sab_state
	if s == null:
		s = _turbo_sab_STATE_SCRIPT.HOLDER.get("state")
		_turbo_sab_state = s
	if s != null and not s.optimize_attack_behaviors:
		return .spawn_projectile(rot, pos, spd)

	var main = _turbo_sab_main
	if not is_instance_valid(main) or not main.is_inside_tree():
		main = Utils.get_scene_node()
		_turbo_sab_main = main

	var projectile = main.get_node_from_pool(projectile_pool_id, main._enemy_projectiles)

	if not is_instance_valid(projectile):
		projectile = projectile_scene.instance()
		main.add_enemy_projectile(projectile)
		projectile.set_meta("pool_id", projectile_pool_id)

	projectile.global_position = pos
	projectile.set_from(_parent)

	projectile.velocity = Vector2.RIGHT.rotated(rot) * spd * RunData.current_run_accessibility_settings.speed

	if rotate_projectile:
		projectile.rotation = rot

	if delete_projectile_on_death and not _parent.is_connected("died", projectile, "on_entity_died"):
		var _error_died = _parent.connect("died", projectile, "on_entity_died")

	projectile.set_damage(projectile_damage)

	if custom_collision_layer != 0:
		projectile.set_collision_layer(custom_collision_layer)

	var use_baker: bool = (s == null or s.optimize_projectiles)
	var use_pool: bool = (s == null or s.pool_outline_materials)
	if custom_sprite_material:
		projectile.set_sprite_material(custom_sprite_material)

	projectile.shoot()
	_turbo_sab_BAKER.normalize_projectile(projectile, _turbo_sab_MAT_POOL, use_baker, use_pool)

	return projectile

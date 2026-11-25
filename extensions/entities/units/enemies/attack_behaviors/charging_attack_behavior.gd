extends "res://entities/units/enemies/attack_behaviors/charging_attack_behavior.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - ChargingAttackBehavior Hot-Path Optimization (_turbo_cab_)
# =============================================================================

const _turbo_cab_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")

var _turbo_cab_state = null
var _turbo_cab_cached_min_r: int = -999999
var _turbo_cab_cached_max_r: int = -999999
var _turbo_cab_min_sq: float = 0.0
var _turbo_cab_max_sq: float = 0.0


func physics_process(delta: float) -> void:
	var s = _turbo_cab_state
	if s == null:
		s = _turbo_cab_STATE_SCRIPT.HOLDER.get("state")
		_turbo_cab_state = s
	if s != null and not s.optimize_attack_behaviors:
		.physics_process(delta)
		return

	if _current_cd > 0.0:
		_current_cd = max(_current_cd - 60.0 * delta, 0.0)
	_frame_counter += 1

	if _parent._move_locked and _frame_counter % 30 == 0:
		_parent.spawn_evolution_puddle_at(_parent.global_position, false)

	if _current_cd > 0:
		return

	var tgt = _parent.current_target
	if not is_instance_valid(tgt):
		return

	var ppos: Vector2 = _parent.global_position
	var tpos: Vector2 = tgt.global_position
	var tx: float = tpos.x
	var ty: float = tpos.y

	if range_X != -1:
		if abs(tx - ppos.x) < range_X:
			_parent._animation_player.playback_speed = attack_anim_speed
			_parent._animation_player.play(_parent.shoot_animation_name)
		return

	if range_Y != -1:
		if abs(ty - ppos.y) < range_Y:
			_parent._animation_player.playback_speed = attack_anim_speed
			_parent._animation_player.play(_parent.shoot_animation_name)
		return

	if max_range >= 0:
		var dx: float = tx - ppos.x
		var dy: float = ty - ppos.y
		var d_sq: float = dx * dx + dy * dy
		if min_range != _turbo_cab_cached_min_r or max_range != _turbo_cab_cached_max_r:
			_turbo_cab_cached_min_r = min_range
			_turbo_cab_cached_max_r = max_range
			var min_f: float = float(min_range) if min_range > 0 else 0.0
			var max_next: float = float(max_range + 1)
			_turbo_cab_min_sq = min_f * min_f
			_turbo_cab_max_sq = max_next * max_next
		if d_sq >= _turbo_cab_min_sq and d_sq < _turbo_cab_max_sq:
			_parent._animation_player.playback_speed = attack_anim_speed
			_parent._animation_player.play(_parent.shoot_animation_name)

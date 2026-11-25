extends "res://entities/units/enemies/attack_behaviors/charging_attack_with_warning_line.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - WarningChargingAttackBehavior Optimization (_turbo_wcab_)
# =============================================================================

const _turbo_wcab_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")

var _turbo_wcab_state = null
var _turbo_wcab_cached_min_r: int = -999999
var _turbo_wcab_cached_max_r: int = -999999
var _turbo_wcab_min_sq: float = 0.0
var _turbo_wcab_max_sq: float = 0.0


func physics_process(delta: float) -> void:
	var s = _turbo_wcab_state
	if s == null:
		s = _turbo_wcab_STATE_SCRIPT.HOLDER.get("state")
		_turbo_wcab_state = s
	if s != null and not s.optimize_attack_behaviors:
		.physics_process(delta)
		return

	if _warning_active:
		if target_calculation_timing == Timing.SHOOT:
			set_target()
			show_warning()
		return

	if _parent.dead:
		hide_warning()

	if _current_cd > 0.0:
		_current_cd = max(_current_cd - 60.0 * delta, 0.0)
	_frame_counter += 1

	if _parent._move_locked and _frame_counter % 30 == 0:
		_parent.spawn_evolution_puddle_at(_parent.global_position, false)

	if _unlock_move_timer.time_left > 0:
		return

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
			start_warning()
		return

	if range_Y != -1:
		if abs(ty - ppos.y) < range_Y:
			start_warning()
		return

	if max_range >= 0:
		var dx: float = tx - ppos.x
		var dy: float = ty - ppos.y
		var d_sq: float = dx * dx + dy * dy
		if min_range != _turbo_wcab_cached_min_r or max_range != _turbo_wcab_cached_max_r:
			_turbo_wcab_cached_min_r = min_range
			_turbo_wcab_cached_max_r = max_range
			var min_f: float = float(min_range) if min_range > 0 else 0.0
			var max_next: float = float(max_range + 1)
			_turbo_wcab_min_sq = min_f * min_f
			_turbo_wcab_max_sq = max_next * max_next
		if d_sq >= _turbo_wcab_min_sq and d_sq < _turbo_wcab_max_sq:
			start_warning()


func show_warning() -> void:
	var s = _turbo_wcab_state
	if s == null:
		s = _turbo_wcab_STATE_SCRIPT.HOLDER.get("state")
		_turbo_wcab_state = s
	if s != null and not s.optimize_attack_behaviors:
		.show_warning()
		return

	if not is_instance_valid(_warning_line):
		return

	var direction: Vector2 = _charge_direction.normalized()
	if direction == Vector2.ZERO:
		return

	direction = _parent.global_transform.basis_xform_inv(direction).normalized()
	if not _warning_line.visible:
		_warning_line.visible = true

	var p0: Vector2 = direction * 50.0
	var p1: Vector2 = direction * (warning_line_length + warning_line_forward_offset)

	if _warning_line.get_point_count() != 2:
		_warning_line.clear_points()
		_warning_line.add_point(p0)
		_warning_line.add_point(p1)
	else:
		_warning_line.set_point_position(0, p0)
		_warning_line.set_point_position(1, p1)

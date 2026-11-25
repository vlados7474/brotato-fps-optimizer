extends "res://weapons/weapon.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Weapon Target Stagger, aim_shape Parity & Broadphase Cut
# -----------------------------------------------------------------------------
# 1. Preserves 5.3.1 target stagger, cached manual-aim, and guarded property writes.
# 2. Exact aim_shape parity on cached target angle calculation (bosses/elites).
# 3. Hysteresis-guarded _range.monitoring mute during sustained manual aim
#    (avoids 1-2 tick shot drops on quick clicks) + disabled tracking mute.
# 4. Disables _hitbox.monitorable on ranged weapons (RangedWeaponStats).
# NOTE: Never defines _process() or _physics_process() here (Defect #12)!
# =============================================================================

const _turbo_wpn_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_wpn_MANUAL_MUTE_MS: int = 1000

var _turbo_wpn_state = null
var _turbo_wpn_phase: int = 0
var _turbo_wpn_cached_angle: float = 0.0
var _turbo_wpn_cached_unit = null
var _turbo_wpn_cache_frame: int = -100000
var _turbo_wpn_angle_frame: int = -100000
var _turbo_wpn_prefire_hz: int = -1
var _turbo_wpn_prefire_cd: float = 1.5
var _turbo_wpn_cache_valid: bool = false

var _turbo_wpn_last_flip_v: bool = false
var _turbo_wpn_last_rot_for_flip: float = -99999.0
var _turbo_wpn_last_idle_angle: float = 0.0
var _turbo_wpn_idle_initialised: bool = false

var _turbo_wpn_aim_frame: int = -100000
var _turbo_wpn_aim_cached: bool = false
var _turbo_wpn_aim_value: bool = false

var _turbo_wpn_tracking_disabled: bool = false
var _turbo_wpn_range_muted: bool = false
var _turbo_wpn_manual_since_ms: int = -1


func _ready() -> void: # ADDITION
	_turbo_wpn_state = _turbo_wpn_STATE_SCRIPT.HOLDER.get("state")
	if _turbo_wpn_state != null:
		_turbo_wpn_phase = _turbo_wpn_state.claim_phase()
	else:
		_turbo_wpn_phase = int(abs(get_instance_id()))
	_turbo_wpn_last_idle_angle = _current_idle_angle
	if sprite != null:
		_turbo_wpn_last_flip_v = sprite.flip_v
	_turbo_wpn_idle_initialised = true
	if stats is RangedWeaponStats and _hitbox != null:
		_hitbox.set_deferred("monitorable", false)
	_turbo_wpn_sync_range_monitoring(_manual_aim)


func init_stats(at_wave_begin: bool = true) -> void:
	.init_stats(at_wave_begin)
	if stats is RangedWeaponStats and _hitbox != null:
		_hitbox.set_deferred("monitorable", false)


func disable_target_tracking() -> void:
	_turbo_wpn_tracking_disabled = true
	.disable_target_tracking()
	_turbo_wpn_sync_range_monitoring(_manual_aim)


func _turbo_wpn_sync_range_monitoring(manual_now: bool) -> void:
	if _range == null:
		return
	var want_muted: bool = _turbo_wpn_tracking_disabled
	if not want_muted:
		if manual_now:
			var now_ms: int = OS.get_ticks_msec()
			if _turbo_wpn_manual_since_ms < 0:
				_turbo_wpn_manual_since_ms = now_ms
			elif (now_ms - _turbo_wpn_manual_since_ms) >= _turbo_wpn_MANUAL_MUTE_MS:
				want_muted = true
		else:
			_turbo_wpn_manual_since_ms = -1
	if want_muted == _turbo_wpn_range_muted:
		return
	_turbo_wpn_range_muted = want_muted
	_range.set_deferred("monitoring", not want_muted)


func _turbo_wpn_cached_target_angle(unit) -> float:
	var wpos: Vector2 = global_position
	var target_pos: Vector2
	if unit is Unit and unit.aim_shape != null:
		target_pos = Utils.get_target_position(unit, wpos)
	else:
		target_pos = unit.global_position
	return (target_pos - wpos).angle()


func _turbo_wpn_refresh_live(frame: int, force_fresh: bool = false) -> float:
	if force_fresh and _turbo_wpn_state != null:
		_turbo_wpn_state.force_fresh_scan = true
	var angle: float = .get_direction_and_calculate_target()
	if force_fresh and _turbo_wpn_state != null:
		_turbo_wpn_state.force_fresh_scan = false
	if not _targets_in_range.empty() and not _current_target.empty() and is_instance_valid(_current_target[0]) and not _current_target[0].dead:
		_turbo_wpn_cached_unit = _current_target[0]
		_turbo_wpn_cached_angle = angle
		_turbo_wpn_cache_frame = frame
		_turbo_wpn_angle_frame = frame
		_turbo_wpn_cache_valid = true
	else:
		_turbo_wpn_cached_unit = null
		_turbo_wpn_cache_valid = false
	return angle


func get_direction_and_calculate_target() -> float:
	if _manual_aim or _turbo_wpn_state == null or not _turbo_wpn_state.cache_weapon_targets:
		return .get_direction_and_calculate_target()

	if _targets_in_range.empty():
		_turbo_wpn_cache_valid = false
		_turbo_wpn_cached_unit = null
		if not _current_target.empty():
			_current_target.clear()
		return rotation if _is_shooting else _current_idle_angle

	var frame: int = Engine.get_physics_frames()
	if _turbo_wpn_cache_valid and _turbo_wpn_angle_frame == frame and not _current_target.empty() and is_instance_valid(_turbo_wpn_cached_unit) and not _turbo_wpn_cached_unit.dead:
		return _turbo_wpn_cached_angle

	var hz: int = _turbo_wpn_state.phys_hz
	if hz != _turbo_wpn_prefire_hz:
		_turbo_wpn_prefire_hz = hz
		_turbo_wpn_prefire_cd = max(1.5, (60.0 / float(max(hz, 1))) * 1.5)
	if _current_cooldown <= _turbo_wpn_prefire_cd:
		return _turbo_wpn_refresh_live(frame, true)

	if _turbo_wpn_cache_valid:
		if _current_target.empty() or not is_instance_valid(_turbo_wpn_cached_unit) or _turbo_wpn_cached_unit.dead:
			_turbo_wpn_cache_valid = false

	var interval: int = _turbo_wpn_state.target_cache_frames + _turbo_wpn_state.cache_extra_frames
	if _current_cooldown > 12.0 and _turbo_wpn_state.tier >= 1:
		interval += int(min(_turbo_wpn_state.tier + 1, 4))

	if interval <= 1 or not _turbo_wpn_cache_valid:
		return _turbo_wpn_refresh_live(frame)

	if _turbo_wpn_state.stagger_target_scans:
		if ((frame + _turbo_wpn_phase) % interval) == 0 or (frame - _turbo_wpn_cache_frame) >= interval:
			return _turbo_wpn_refresh_live(frame)
	elif (frame - _turbo_wpn_cache_frame) >= interval:
		return _turbo_wpn_refresh_live(frame)

	_turbo_wpn_cached_angle = _turbo_wpn_cached_target_angle(_turbo_wpn_cached_unit)
	_turbo_wpn_angle_frame = frame
	return _turbo_wpn_cached_angle


func should_shoot() -> bool:
	if not _manual_aim and not _is_shooting and _turbo_wpn_state != null and _turbo_wpn_state.cache_weapon_targets:
		if _current_cooldown <= 0.0 and not _targets_in_range.empty():
			var frame: int = Engine.get_physics_frames()
			var target_invalid: bool = _current_target.empty() or not is_instance_valid(_current_target[0]) or _current_target[0].dead
			if _turbo_wpn_cache_frame != frame or target_invalid:
				rotation = _turbo_wpn_refresh_live(frame, true)
	return .should_shoot()


func is_manual_aim() -> bool:
	if _turbo_wpn_state == null or not _turbo_wpn_state.cache_manual_aim:
		var raw_aim: bool = .is_manual_aim()
		_turbo_wpn_sync_range_monitoring(raw_aim)
		return raw_aim
	var idle_frame: int = Engine.get_idle_frames()
	if not _turbo_wpn_aim_cached or ((idle_frame + _turbo_wpn_phase) % 10) == 0 or (idle_frame - _turbo_wpn_aim_frame) >= 10:
		_turbo_wpn_aim_value = .is_manual_aim()
		_turbo_wpn_aim_frame = idle_frame
		_turbo_wpn_aim_cached = true
		_turbo_wpn_sync_range_monitoring(_turbo_wpn_aim_value)
	return _turbo_wpn_aim_value


func update_sprite_flipv() -> void:
	if _turbo_wpn_state == null or not _turbo_wpn_state.guard_weapon_property_writes or sprite == null:
		.update_sprite_flipv()
		return
	var cur_rot: float = rotation
	if _turbo_wpn_idle_initialised and cur_rot == _turbo_wpn_last_rot_for_flip and sprite.flip_v == _turbo_wpn_last_flip_v:
		return
	_turbo_wpn_last_rot_for_flip = cur_rot
	var cur_deg: float = rad2deg(cur_rot)
	var should_flip: bool = cur_deg <= -90.0 or cur_deg >= 90.0
	if _turbo_wpn_idle_initialised and should_flip == _turbo_wpn_last_flip_v and sprite.flip_v == should_flip:
		return
	_turbo_wpn_last_flip_v = should_flip
	sprite.flip_v = should_flip


func update_idle_angle() -> void:
	if _turbo_wpn_state == null or not _turbo_wpn_state.guard_weapon_property_writes:
		.update_idle_angle()
		return
	var target_angle: float = _idle_angle if _parent.get_direction() == 1 else PI - _idle_angle
	if _turbo_wpn_idle_initialised and is_equal_approx(target_angle, _turbo_wpn_last_idle_angle):
		return
	_turbo_wpn_last_idle_angle = target_angle
	_current_idle_angle = target_angle

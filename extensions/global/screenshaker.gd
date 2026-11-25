extends "res://global/screenshaker.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Stream-Friendly Integer Camera Shake (_turbo_shk_)
# =============================================================================

const _turbo_shk_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_shk_QUANTIZER_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_shake_quantizer.gd")
const _turbo_shk_DEADZONE_PX: float = 0.65
const _turbo_shk_STEP_MS: int = 33
const _turbo_shk_MAX_DUR_SEC: float = 0.10
const _turbo_shk_TAIL_MS: int = 120

var _turbo_shk_state = null
var _turbo_shk_quantizer: Node = null
var _turbo_shk_camera: Camera2D = null
var _turbo_shk_last_shake_ms: int = -10000
var _turbo_shk_last_step_ms: int = -10000
var _turbo_shk_active_until_ms: int = 0
var _turbo_shk_held_offset: Vector2 = Vector2.ZERO


func _ready() -> void: # ADDITION
	_turbo_shk_state = _turbo_shk_STATE_SCRIPT.HOLDER.get("state")
	_turbo_shk_ensure_quantizer()


func _exit_tree() -> void: # ADDITION
	_turbo_shk_zero_offset()


func shake(intensity: float, duration: float) -> void:
	var s = _turbo_shk_state
	if s != null and (s.disable_shake or s.stream_potato):
		_turbo_shk_zero_offset()
		if is_instance_valid(_turbo_shk_quantizer):
			_turbo_shk_quantizer.set_process(false)
		return

	if s != null and not s.limit_screenshake:
		.shake(intensity, duration)
		return

	var max_amp: float = s.screenshake_max_intensity if s != null else 1.5
	if s != null and s.tier >= 3:
		max_amp = min(max_amp, 1.0)

	var clamped_amp: float = min(intensity, max_amp)
	if clamped_amp < _turbo_shk_DEADZONE_PX or duration <= 0.0:
		return

	var min_interval: int = s.screenshake_min_interval_ms if s != null else 150
	var now_ms: int = OS.get_ticks_msec()
	if now_ms - _turbo_shk_last_shake_ms < min_interval:
		return
	_turbo_shk_last_shake_ms = now_ms

	var clamped_dur: float = min(duration, _turbo_shk_MAX_DUR_SEC)
	var quantized_amp: float = max(1.0, round(clamped_amp))
	.shake(quantized_amp, clamped_dur)

	var until_ms: int = now_ms + int(clamped_dur * 1000.0) + _turbo_shk_TAIL_MS
	if until_ms > _turbo_shk_active_until_ms:
		_turbo_shk_active_until_ms = until_ms
	_turbo_shk_ensure_quantizer()
	if is_instance_valid(_turbo_shk_quantizer):
		_turbo_shk_quantizer.set_process(true)
	_turbo_shk_quantize_camera_offset()


func _turbo_shk_quantize_camera_offset() -> void:
	var now_ms: int = OS.get_ticks_msec()
	var cam: Camera2D = _turbo_shk_get_camera()
	if cam == null:
		if now_ms >= _turbo_shk_active_until_ms and is_instance_valid(_turbo_shk_quantizer):
			_turbo_shk_held_offset = Vector2.ZERO
			_turbo_shk_quantizer.set_process(false)
		return

	var s = _turbo_shk_state
	if s != null and (s.disable_shake or s.stream_potato or not s.limit_screenshake):
		if (s.disable_shake or s.stream_potato) and cam.offset != Vector2.ZERO:
			cam.offset = Vector2.ZERO
		_turbo_shk_held_offset = Vector2.ZERO
		if is_instance_valid(_turbo_shk_quantizer):
			_turbo_shk_quantizer.set_process(false)
		return

	if now_ms >= _turbo_shk_active_until_ms:
		_turbo_shk_held_offset = Vector2.ZERO
		if cam.offset != Vector2.ZERO:
			cam.offset = Vector2.ZERO
		if is_instance_valid(_turbo_shk_quantizer):
			_turbo_shk_quantizer.set_process(false)
		return

	var raw: Vector2 = cam.offset
	var qx: float = 0.0 if abs(raw.x) < _turbo_shk_DEADZONE_PX else round(raw.x)
	var qy: float = 0.0 if abs(raw.y) < _turbo_shk_DEADZONE_PX else round(raw.y)
	var snapped: Vector2 = Vector2(qx, qy)

	if snapped == Vector2.ZERO:
		_turbo_shk_held_offset = Vector2.ZERO
		if cam.offset != Vector2.ZERO:
			cam.offset = Vector2.ZERO
		return

	if _turbo_shk_held_offset == Vector2.ZERO or now_ms - _turbo_shk_last_step_ms >= _turbo_shk_STEP_MS:
		_turbo_shk_held_offset = snapped
		_turbo_shk_last_step_ms = now_ms

	if cam.offset != _turbo_shk_held_offset:
		cam.offset = _turbo_shk_held_offset


func _turbo_shk_ensure_quantizer() -> void:
	if is_instance_valid(_turbo_shk_quantizer):
		return
	var q: Node = _turbo_shk_QUANTIZER_SCRIPT.new()
	q.name = "SaffronTurboShakeQuantizer"
	q.host = self
	add_child(q)
	_turbo_shk_quantizer = q


func _turbo_shk_get_camera() -> Camera2D:
	if is_instance_valid(_turbo_shk_camera):
		return _turbo_shk_camera
	var own_cam = get("_camera")
	if own_cam is Camera2D and is_instance_valid(own_cam):
		_turbo_shk_camera = own_cam
		return _turbo_shk_camera
	var pub_cam = get("camera")
	if pub_cam is Camera2D and is_instance_valid(pub_cam):
		_turbo_shk_camera = pub_cam
		return _turbo_shk_camera
	var tree: SceneTree = get_tree()
	if tree != null and tree.current_scene != null:
		_turbo_shk_camera = tree.current_scene.get_node_or_null("Camera") as Camera2D
	return _turbo_shk_camera


func _turbo_shk_zero_offset() -> void:
	_turbo_shk_held_offset = Vector2.ZERO
	var cam: Camera2D = _turbo_shk_get_camera()
	if cam != null and cam.offset != Vector2.ZERO:
		cam.offset = Vector2.ZERO

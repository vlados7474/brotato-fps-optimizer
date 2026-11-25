extends "res://projectiles/player_explosion.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Zero-Realloc Explosion Smoke & Offscreen Cull (_turbo_pe_)
# -----------------------------------------------------------------------------
# Fixes GPU VisualServer::multimesh_allocate hitches by bucketing and locking
# _explosion_smoke.amount once on cold creation, visually scaling via
# scale_amount / lifetime, culling offscreen smoke via scaled cam_rect,
# applying fixed_fps / fract_delta, and stopping emission in end_explosion().
# Does NOT re-invoke parent _ready or override _physics_process (Defect #12 safe).
# =============================================================================

const _turbo_pe_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")

var _turbo_pe_state = null
var _turbo_pe_amount_locked: bool = false
var _turbo_pe_locked_amount: int = 8
var _turbo_pe_base_scale_amount: float = 1.0
var _turbo_pe_base_lifetime: float = 1.0
var _turbo_pe_base_fixed_fps: int = 0
var _turbo_pe_base_fract_delta: bool = true
const _turbo_pe_FRAME_BUDGET: Dictionary = {"f": -1, "c": 0}

var _turbo_pe_last_fps: int = -1
var _turbo_pe_last_safe_val: int = -1
var _turbo_pe_last_life_scale: float = -1.0


func _ready() -> void: # ADDITION
	_turbo_pe_state = _turbo_pe_STATE_SCRIPT.HOLDER.get("state")
	if _explosion_smoke != null:
		_turbo_pe_base_scale_amount = _explosion_smoke.scale_amount
		_turbo_pe_base_lifetime = _explosion_smoke.lifetime
		_turbo_pe_base_fixed_fps = _explosion_smoke.fixed_fps
		_turbo_pe_base_fract_delta = _explosion_smoke.fract_delta
		_turbo_pe_last_fps = _explosion_smoke.fixed_fps


func set_smoke_amount(value: int) -> void:
	if not is_inside_tree() or _explosion_smoke == null:
		return

	var s = _turbo_pe_state
	if s == null:
		_turbo_pe_state = _turbo_pe_STATE_SCRIPT.HOLDER.get("state")
		s = _turbo_pe_state

	if s != null and not s.scale_explosion_smoke:
		_explosion_smoke.scale_amount = _turbo_pe_base_scale_amount
		_explosion_smoke.lifetime = _turbo_pe_base_lifetime
		_turbo_pe_amount_locked = false
		_turbo_pe_last_safe_val = -1
		.set_smoke_amount(value)
		return

	var safe_val: int = int(max(1, value))

	if not _turbo_pe_amount_locked:
		var bucket: int = 8
		if safe_val <= 4:
			bucket = 4
		elif safe_val <= 8:
			bucket = 8
		elif safe_val <= 16:
			bucket = 16
		elif safe_val <= 24:
			bucket = 24
		else:
			bucket = 32
		if _explosion_smoke.amount != bucket:
			_explosion_smoke.amount = bucket
		_turbo_pe_locked_amount = bucket
		_turbo_pe_amount_locked = true

	var life_scale: float = s.fx_lifetime_scale if s != null else 1.0
	if safe_val == _turbo_pe_last_safe_val and abs(life_scale - _turbo_pe_last_life_scale) < 0.001:
		return
	_turbo_pe_last_safe_val = safe_val
	_turbo_pe_last_life_scale = life_scale
	var ratio: float = clamp(float(safe_val) / float(_turbo_pe_locked_amount), 0.5, 1.5)
	_explosion_smoke.scale_amount = _turbo_pe_base_scale_amount * sqrt(ratio)
	_explosion_smoke.lifetime = max(0.08, _turbo_pe_base_lifetime * life_scale * clamp(ratio, 0.75, 1.25))


func emit_smoke() -> void:
	if not ProgressData.settings.visual_effects or _explosion_smoke == null:
		return

	var s = _turbo_pe_state
	if s == null:
		_turbo_pe_state = _turbo_pe_STATE_SCRIPT.HOLDER.get("state")
		s = _turbo_pe_state

	if s != null and s.cull_offscreen and s.cam_valid:
		var pad: float = max(scale.x, scale.y) * 64.0
		var gp: Vector2 = global_position
		var cr: Rect2 = s.cam_rect
		if gp.x < cr.position.x - pad or gp.x > cr.position.x + cr.size.x + pad or gp.y < cr.position.y - pad or gp.y > cr.position.y + cr.size.y + pad:
			return
	if s != null and (s.tier >= 2 or s.stream_potato):
		var cap_pf: int = 2 if (s.tier >= 4 or s.stream_potato) else (4 if s.tier == 3 else 8)
		var pf: int = Engine.get_physics_frames()
		if _turbo_pe_FRAME_BUDGET["f"] != pf:
			_turbo_pe_FRAME_BUDGET["f"] = pf
			_turbo_pe_FRAME_BUDGET["c"] = 0
		if int(_turbo_pe_FRAME_BUDGET["c"]) >= cap_pf:
			return
		_turbo_pe_FRAME_BUDGET["c"] = int(_turbo_pe_FRAME_BUDGET["c"]) + 1

	if s != null and s.throttle_particle_sim_fps:
		var target_fps: int = s.fx_sim_fps
		if _turbo_pe_last_fps != target_fps:
			_explosion_smoke.fixed_fps = target_fps
			_explosion_smoke.fract_delta = (target_fps <= 0)
			_turbo_pe_last_fps = target_fps
	elif _turbo_pe_last_fps != _turbo_pe_base_fixed_fps:
		_explosion_smoke.fixed_fps = _turbo_pe_base_fixed_fps
		_explosion_smoke.fract_delta = _turbo_pe_base_fract_delta
		_turbo_pe_last_fps = _turbo_pe_base_fixed_fps

	_explosion_smoke.emit()


func end_explosion() -> void:
	if _explosion_smoke != null and _explosion_smoke.emitting:
		_explosion_smoke.emitting = false
	.end_explosion()

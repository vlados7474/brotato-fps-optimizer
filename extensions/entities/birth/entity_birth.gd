extends "res://entities/birth/entity_birth.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - EntityBirth Offscreen & Color Cache (_turbo_birth_)
# -----------------------------------------------------------------------------
# Never defines _physics_process() (Defect #12 fix). Uses 12.0-tick (~0.2s)
# resync interval when offscreen so approaching players always see the cross.
# =============================================================================

const _turbo_birth_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _TURBO_BIRTH_COLOR_CACHE: Dictionary = {}

var _turbo_birth_state = null


func _ready() -> void: # ADDITION
	_turbo_birth_state = _turbo_birth_STATE_SCRIPT.HOLDER.get("state")
	monitorable = false


func _exit_tree() -> void: # ADDITION
	if _sprite != null and not _sprite.visible:
		_sprite.visible = true


func start(p_request: SpawnRequest) -> void:
	.start(p_request)
	if type != EntityType.ENEMY:
		set_deferred("monitoring", false)
		if _collision_shape != null:
			_collision_shape.call_deferred("set_disabled", true)
	else:
		set_deferred("monitoring", true)
		if _collision_shape != null:
			_collision_shape.call_deferred("set_disabled", false)
	_turbo_birth_sync_visibility(global_position)


func set_color() -> void:
	if request.charmed_by != -1:
		_color = Utils.CHARM_COLOR
		_sprite.texture = entity_sprite
	elif type == EntityType.NEUTRAL:
		_color = _turbo_birth_get_lightened_color(ProgressData.settings.color_positive)
		_sprite.texture = entity_sprite
	elif type == EntityType.STRUCTURE or type == EntityType.PET:
		_color = Color.cornflower
		_sprite.texture = structure_sprite
	elif type == EntityType.ENEMY:
		_color = _turbo_birth_get_lightened_color(ProgressData.settings.color_negative)
		_sprite.texture = entity_sprite


func birth() -> void:
	if _sprite != null and not _sprite.visible:
		_sprite.visible = true
	.birth()


func get_flicker_cd() -> float:
	_turbo_birth_sync_visibility(global_position)
	var s = _turbo_birth_state
	if s != null:
		if s.cull_offscreen and not _colliding_with_player and s.cam_valid and not s.cam_rect.has_point(global_position):
			return 12.0
		if s.stream_potato or (s.adaptive_quality and s.tier >= 3):
			return 9999.0
	return .get_flicker_cd()


func _turbo_birth_get_lightened_color(color_str: String) -> Color:
	var cached = _TURBO_BIRTH_COLOR_CACHE.get(color_str)
	if cached != null:
		return cached
	var base: Color = Color(color_str)
	var lightened: Color = base.lightened(0.22)
	if _TURBO_BIRTH_COLOR_CACHE.size() >= 64:
		_TURBO_BIRTH_COLOR_CACHE.clear()
	_TURBO_BIRTH_COLOR_CACHE[color_str] = lightened
	return lightened


func _turbo_birth_sync_visibility(pos: Vector2) -> void:
	if _sprite == null:
		return
	var s = _turbo_birth_state
	if s == null:
		s = _turbo_birth_STATE_SCRIPT.HOLDER.get("state")
		_turbo_birth_state = s
	var want_vis: bool = true
	if s != null and s.cull_offscreen and not _colliding_with_player and s.cam_valid:
		want_vis = s.cam_rect.has_point(pos)
	if _sprite.visible != want_vis:
		_sprite.visible = want_vis
		if want_vis:
			if _sprite.self_modulate.a < 1.0:
				_sprite.self_modulate.a = 1.0
			if _flicker_cd > 100.0 and not (s != null and (s.stream_potato or (s.adaptive_quality and s.tier >= 3))):
				_flicker_cd = .get_flicker_cd()

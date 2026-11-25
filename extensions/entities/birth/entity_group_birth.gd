extends "res://entities/birth/entity_group_birth.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - EntityGroupBirth Offscreen Visibility Sync (_turbo_gbirth_)
# =============================================================================

const _turbo_gbirth_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")

var _turbo_gbirth_state = null


func start(p_request: SpawnRequest) -> void:
	.start(p_request)
	_turbo_gbirth_sync_visibility(global_position)


func birth() -> void:
	if _sprite != null and not _sprite.visible:
		_sprite.visible = true
	.birth()


func _turbo_gbirth_sync_visibility(pos: Vector2) -> void:
	if _sprite == null:
		return
	var s = _turbo_gbirth_state
	if s == null:
		s = _turbo_gbirth_STATE_SCRIPT.HOLDER.get("state")
		_turbo_gbirth_state = s
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

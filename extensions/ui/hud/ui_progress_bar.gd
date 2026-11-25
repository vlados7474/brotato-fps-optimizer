extends "res://ui/hud/ui_progress_bar.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - UIProgressBar Dirty-Check on tint_progress (_turbo_pb_)
# =============================================================================

const _turbo_pb_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")


func update_color_from_effects(effects: Dictionary) -> void:
	var s = _turbo_pb_STATE_SCRIPT.HOLDER.get("state")
	if s != null and not s.optimize_hud_inventory:
		.update_color_from_effects(effects)
		return
	var new_color: Color = progress_color
	for effect_key in effect_colors:
		if effects.get(effect_key, 0) > 0:
			new_color = effect_colors[effect_key]
			break
	_non_flash_color = new_color
	if _flash_timer.time_left == 0 and tint_progress != new_color:
		tint_progress = new_color


func _on_Timer_timeout() -> void:
	if tint_progress != _non_flash_color:
		tint_progress = _non_flash_color

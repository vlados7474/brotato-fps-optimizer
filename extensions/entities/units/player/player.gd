extends "res://entities/units/player/player.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Player Zero-Alloc LifeBar & Deferred Interp Registration
# -----------------------------------------------------------------------------
# Hurtbox layer isolation is handled universally in unit.gd (covers Player,
# Scapegoat, and DinoEgg). Never defines _physics_process() here (Defect #12)!
# =============================================================================

const _turbo_player_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")

var _turbo_player_state = null
var _turbo_life_bar_effects: Dictionary = {"hit_protection": 0}


func _ready() -> void: # ADDITION
	_turbo_player_state = _turbo_player_STATE_SCRIPT.HOLDER.get("state")
	call_deferred("_turbo_player_register_interp")


func _exit_tree() -> void: # ADDITION
	if _turbo_player_state != null and _turbo_player_state.interpolator != null:
		_turbo_player_state.interpolator.unregister_node(self)


func _turbo_player_register_interp() -> void:
	if not is_inside_tree() or dead:
		return
	if _turbo_player_state != null and _turbo_player_state.interpolator != null:
		_turbo_player_state.interpolator.register_node(self)
		if _turbo_player_state.interpolator.has_method("reset_node_snapshot"):
			_turbo_player_state.interpolator.reset_node_snapshot(self)


func die(args: Entity.DieArgs = Utils.default_die_args) -> void:
	if _turbo_player_state != null and _turbo_player_state.interpolator != null:
		_turbo_player_state.interpolator.unregister_node(self)
	.die(args)


func life_bar_effects() -> Dictionary:
	_turbo_life_bar_effects["hit_protection"] = _hit_protection
	return _turbo_life_bar_effects

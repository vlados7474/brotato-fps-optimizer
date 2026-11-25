extends "res://projectiles/player_projectile.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Safe Crit-Effect Counters for PlayerProjectile (_turbo_pp_)
# -----------------------------------------------------------------------------
# Fixes shared NullEffect mutation bug by storing per-projectile counters
# (_turbo_crit_pierce / _turbo_crit_bounce) instead of decrementing or erasing
# from _hitbox.effects, with safe mod-effect guards ("key_hash" in effect).
# Does NOT override _physics_process (Defect #12 safe).
# =============================================================================

const _turbo_pp_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
var _turbo_pp_empty_poh: Array = []

var _turbo_crit_pierce: int = 0
var _turbo_crit_bounce: int = 0
var _turbo_pp_stepped: bool = false


func set_effects(effects: Array) -> void:
	_hitbox.effects = effects
	_turbo_crit_pierce = 0
	_turbo_crit_bounce = 0

	if not _hitbox.projectiles_on_hit.empty():
		if not _turbo_pp_empty_poh.empty():
			_turbo_pp_empty_poh = []
		_hitbox.projectiles_on_hit = _turbo_pp_empty_poh

	if effects.empty():
		return

	var found_poh: bool = false
	for effect in effects:
		if effect == null:
			continue
		if effect is NullEffect or "key_hash" in effect:
			var kh: int = effect.key_hash
			if kh == Keys.pierce_on_crit_hash:
				_turbo_crit_pierce += int(effect.value)
				continue
			elif kh == Keys.bounce_on_crit_hash:
				_turbo_crit_bounce += int(effect.value)
				continue
		if not found_poh and effect is ProjectilesOnHitEffect:
			if _hitbox.from is BuilderTurret:
				_hitbox.projectiles_on_hit = _hitbox.from.projectiles_on_hit
			elif is_instance_valid(_hitbox.from) and "_hitbox" in _hitbox.from and _hitbox.from._hitbox != null:
				_hitbox.projectiles_on_hit = _hitbox.from._hitbox.projectiles_on_hit
			found_poh = true


func _on_Hitbox_critically_hit_something(_thing_hit: Node, _damage_dealt: int) -> void:
	if _turbo_crit_bounce > 0:
		_bounce += 1
		_turbo_crit_bounce -= 1
	if _turbo_crit_pierce > 0:
		_piercing += 1
		_turbo_crit_pierce -= 1
	emit_signal("critically_hit_something", _thing_hit, _damage_dealt)


func _exit_tree() -> void: # ADDITION
	if _turbo_pp_stepped:
		_turbo_pp_unregister_stepper()


func _turbo_pp_register_stepper() -> void:
	var s = _turbo_pp_STATE_SCRIPT.HOLDER.get("state")
	if s == null or not s.optimize_projectiles or s.stepper == null:
		_turbo_pp_unregister_stepper()
		set_physics_process(true)
		return
	if get_script() != s.stepper.pp_leaf_script or _enable_stop_delay or sinusoidal_motion != Vector2.ZERO:
		_turbo_pp_unregister_stepper()
		set_physics_process(true)
		return
	if not _turbo_pp_stepped:
		_turbo_pp_stepped = true
		set_physics_process(false)
		s.stepper.register_player(self)


func _turbo_pp_unregister_stepper() -> void:
	if not _turbo_pp_stepped:
		return
	_turbo_pp_stepped = false
	set_physics_process(true)
	var s = _turbo_pp_STATE_SCRIPT.HOLDER.get("state")
	if s != null and s.stepper != null:
		s.stepper.unregister_player(self)


func shoot() -> void:
	.shoot()
	_turbo_pp_register_stepper()


func stop(from_screen_border: bool = false) -> void:
	if _turbo_pp_stepped:
		_turbo_pp_unregister_stepper()
	.stop(from_screen_border)


func _return_to_pool() -> void:
	_turbo_pp_unregister_stepper()
	_turbo_crit_pierce = 0
	_turbo_crit_bounce = 0
	._return_to_pool()

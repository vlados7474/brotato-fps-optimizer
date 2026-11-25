extends "res://singletons/weapon_service.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - WeaponService Projectile & Explosion Guard (_turbo_ws_)
# -----------------------------------------------------------------------------
# 1. set_projectile_effects(): returns cached read-only crit-effect templates
#    paired with local counters in player_projectile.gd, with integrity guard
#    against external mutation.
# 2. spawn_projectile(): computes velocity once (eliminates duplicate
#    Vector2.RIGHT.rotated(direction) * speed) and avoids empty-effect churn.
# 3. explode(): scales ExplodingEffect.base_smoke_amount around .explode()
#    with 100% hitbox/damage parity.
# =============================================================================

const _turbo_ws_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_ws_MAX_TEMPLATES: int = 64

var _turbo_ws_state = null
var _turbo_ws_main = null
var _turbo_ws_empty: Array = []
var _turbo_ws_templates: Dictionary = {}
var _turbo_ws_active_explosions: Dictionary = {}
var _turbo_ws_explode_depth: int = 0
var _turbo_ws_active_eff_id: int = 0


func _ready() -> void: # ADDITION
	_turbo_ws_state = _turbo_ws_STATE_SCRIPT.HOLDER.get("state")


func spawn_projectile(
	pos: Vector2,
	weapon_stats: RangedWeaponStats,
	direction: float,
	from: Node,
	args: WeaponServiceSpawnProjectileArgs
) -> Node:
	var s = _turbo_ws_state
	if s == null:
		_turbo_ws_state = _turbo_ws_STATE_SCRIPT.HOLDER.get("state")
		s = _turbo_ws_state
	if s != null and not s.optimize_projectiles:
		return .spawn_projectile(pos, weapon_stats, direction, from, args)


	var duplicated_effects: Array
	if args.effects.empty():
		duplicated_effects = set_projectile_effects(args.effects, args.from_player_index)
	else:
		duplicated_effects = []
		for effect in args.effects:
			duplicated_effects.push_back(effect.duplicate())
		duplicated_effects = set_projectile_effects(duplicated_effects, args.from_player_index)

	var main = _turbo_ws_main
	if not is_instance_valid(main):
		main = Utils.get_scene_node()
		_turbo_ws_main = main

	var projectile_pool_id: int = default_projectile_pool_id
	if weapon_stats.projectile_scene != null:
		projectile_pool_id = weapon_stats.projectile_scene.get_instance_id()

	var projectile = main.get_node_from_pool(projectile_pool_id, main._player_projectiles)
	if not is_instance_valid(projectile):
		var projectile_scene = weapon_stats.projectile_scene if weapon_stats.projectile_scene != null else DEFAULT_PROJECTILE_SCENE
		projectile = projectile_scene.instance()
		if args.deferred:
			main.call_deferred("add_player_projectile", projectile)
		else:
			main.add_player_projectile(projectile)
		projectile.set_meta("pool_id", projectile_pool_id)

	var spd: float = weapon_stats.projectile_speed
	var vel: Vector2 = Vector2(cos(direction), sin(direction)) * spd
	var rot: float = direction if spd > 0.0 else vel.angle()

	if args.deferred:
		var def_hb_args := Hitbox.HitboxArgs.new()
		def_hb_args.set_from_weapon_stats(weapon_stats)
		projectile.call_deferred(
			"shoot_ex",
			from,
			pos,
			vel,
			rot,
			weapon_stats,
			args.damage_tracking_key_hash,
			duplicated_effects,
			def_hb_args,
			args.knockback_direction
		)
	else:
		_hitbox_args.set_from_weapon_stats(weapon_stats)
		projectile.shoot_ex(
			from,
			pos,
			vel,
			rot,
			weapon_stats,
			args.damage_tracking_key_hash,
			duplicated_effects,
			_hitbox_args,
			args.knockback_direction
		)

	return projectile


func set_projectile_effects(base_effects: Array, player_index: int = -1) -> Array:
	if _turbo_ws_state == null:
		_turbo_ws_state = _turbo_ws_STATE_SCRIPT.HOLDER.get("state")
	if _turbo_ws_state != null and not _turbo_ws_state.pool_projectile_effects:
		return .set_projectile_effects(base_effects, player_index)

	if player_index < 0:
		if base_effects.empty():
			if not _turbo_ws_empty.empty():
				_turbo_ws_empty = []
			return _turbo_ws_empty
		return base_effects.duplicate()

	var p_eff: int = int(max(0, int(RunData.get_player_effect(Keys.pierce_on_crit_hash, player_index))))
	var b_eff: int = int(max(0, int(RunData.get_player_effect(Keys.bounce_on_crit_hash, player_index))))

	if base_effects.empty():
		if p_eff <= 0 and b_eff <= 0:
			if not _turbo_ws_empty.empty():
				_turbo_ws_empty = []
			return _turbo_ws_empty

		var tpl_key: int = ((p_eff & 0xFFFF) << 16) | (b_eff & 0xFFFF)
		var expected_len: int = (1 if p_eff > 0 else 0) + (1 if b_eff > 0 else 0)
		if _turbo_ws_templates.has(tpl_key):
			var cached_tpl: Array = _turbo_ws_templates[tpl_key]
			if cached_tpl.size() == expected_len:
				var intact: bool = true
				var idx: int = 0
				if p_eff > 0:
					if cached_tpl[idx].key_hash != Keys.pierce_on_crit_hash or int(cached_tpl[idx].value) != p_eff:
						intact = false
					idx += 1
				if intact and b_eff > 0:
					if cached_tpl[idx].key_hash != Keys.bounce_on_crit_hash or int(cached_tpl[idx].value) != b_eff:
						intact = false
				if intact:
					return cached_tpl

		var built: Array = []
		if p_eff > 0:
			var ne_p := NullEffect.new()
			ne_p.key = "pierce_on_crit"
			ne_p.key_hash = Keys.pierce_on_crit_hash
			ne_p.value = p_eff
			built.append(ne_p)
		if b_eff > 0:
			var ne_b := NullEffect.new()
			ne_b.key = "bounce_on_crit"
			ne_b.key_hash = Keys.bounce_on_crit_hash
			ne_b.value = b_eff
			built.append(ne_b)

		if _turbo_ws_templates.size() >= _turbo_ws_MAX_TEMPLATES:
			_turbo_ws_templates.clear()
		_turbo_ws_templates[tpl_key] = built
		return built

	if p_eff <= 0 and b_eff <= 0:
		return base_effects.duplicate()

	var out_arr: Array = base_effects.duplicate()
	var tpl_key_ne: int = ((p_eff & 0xFFFF) << 16) | (b_eff & 0xFFFF)
	var cached_ne = _turbo_ws_templates.get(tpl_key_ne)
	if cached_ne == null:
		cached_ne = []
		if p_eff > 0:
			var ne_p2 := NullEffect.new()
			ne_p2.key = "pierce_on_crit"
			ne_p2.key_hash = Keys.pierce_on_crit_hash
			ne_p2.value = p_eff
			cached_ne.append(ne_p2)
		if b_eff > 0:
			var ne_b2 := NullEffect.new()
			ne_b2.key = "bounce_on_crit"
			ne_b2.key_hash = Keys.bounce_on_crit_hash
			ne_b2.value = b_eff
			cached_ne.append(ne_b2)
		if _turbo_ws_templates.size() >= _turbo_ws_MAX_TEMPLATES:
			_turbo_ws_templates.clear()
		_turbo_ws_templates[tpl_key_ne] = cached_ne
	for ce in cached_ne:
		out_arr.push_back(ce)
	return out_arr


func explode(effect: ExplodingEffect, args: WeaponServiceExplodeArgs) -> Node:
	var s = _turbo_ws_state
	if s == null:
		_turbo_ws_state = _turbo_ws_STATE_SCRIPT.HOLDER.get("state")
		s = _turbo_ws_state
	if effect == null or s == null or not s.scale_explosion_smoke:
		return .explode(effect, args)
	var smoke_mult: float = s.explode_smoke_scale
	if smoke_mult >= 0.999:
		return .explode(effect, args)
	var eff_id: int = effect.get_instance_id()
	if _turbo_ws_explode_depth > 0:
		if eff_id == _turbo_ws_active_eff_id or _turbo_ws_active_explosions.has(eff_id):
			return .explode(effect, args)
	var orig_smoke: int = int(effect.base_smoke_amount)
	if orig_smoke <= 1:
		return .explode(effect, args)
	if _turbo_ws_explode_depth == 0:
		_turbo_ws_active_eff_id = eff_id
	else:
		_turbo_ws_active_explosions[eff_id] = true
	_turbo_ws_explode_depth += 1
	effect.base_smoke_amount = int(max(1, int(round(float(orig_smoke) * smoke_mult))))
	var inst: Node = .explode(effect, args)
	effect.base_smoke_amount = orig_smoke
	_turbo_ws_explode_depth -= 1
	if _turbo_ws_explode_depth == 0:
		_turbo_ws_active_eff_id = 0
	else:
		_turbo_ws_active_explosions.erase(eff_id)
	return inst

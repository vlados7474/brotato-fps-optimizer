extends "res://entities/units/unit/unit.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Unit Transform Guard, Flash, EB Cache, Velocity Fast-Path
# & Universal Hurtbox Layer Isolation (Player + Scapegoat + DinoEgg)
# -----------------------------------------------------------------------------
# NOTE: Never defines _physics_process() here (Defect #12)!
# =============================================================================

const _turbo_unit_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_unit_MAT_POOL = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_material_pool.gd")
const _turbo_unit_FLASH_BOOST: float = 1.32
const _turbo_unit_COLOR_EPS: float = 0.01
const _turbo_unit_ISOLATED_HITBOX_LAYER: int = 16384

var _turbo_unit_state = null
var _turbo_unit_next_flash_ms: int = 0
var _turbo_unit_mod_flashing: bool = false
var _turbo_unit_base_modulate: Color = Color(1.0, 1.0, 1.0, 1.0)
var _turbo_unit_applied_modulate: Color = Color(1.0, 1.0, 1.0, 1.0)

var _turbo_eb_cache: Array = []
var _turbo_unit_eb_dirty: bool = true
var _turbo_unit_eb_connected: bool = false
var _turbo_unit_last_mb = null
var _turbo_unit_has_rand_mb: bool = false


func _ready() -> void: # ADDITION
	_turbo_unit_state = _turbo_unit_STATE_SCRIPT.HOLDER.get("state")
	_turbo_eb_cache.clear()
	_turbo_unit_eb_dirty = true
	_turbo_unit_last_mb = null
	_turbo_unit_connect_eb_signals()
	_turbo_unit_sync_hurtbox_mask()
	if sprite != null:
		_turbo_unit_base_modulate = sprite.self_modulate


func _exit_tree() -> void: # ADDITION
	_turbo_unit_reset_flash()
	_turbo_eb_cache.clear()
	_turbo_unit_eb_dirty = true


func respawn() -> void:
	_turbo_unit_reset_flash()
	_turbo_eb_cache.clear()
	_turbo_unit_eb_dirty = true
	_turbo_unit_last_mb = null
	.respawn()
	if _turbo_unit_state == null:
		_turbo_unit_state = _turbo_unit_STATE_SCRIPT.HOLDER.get("state")
	_turbo_unit_connect_eb_signals()
	_turbo_unit_sync_hurtbox_mask()
	if sprite != null:
		_turbo_unit_base_modulate = sprite.self_modulate


func _turbo_unit_sync_hurtbox_mask() -> void:
	if _hurtbox == null:
		return
	var s = _turbo_unit_state
	if s != null and s.isolate_enemy_hitbox_layer:
		if (_hurtbox.collision_mask & Utils.ENEMIES_BIT) != 0:
			_hurtbox.collision_mask = (_hurtbox.collision_mask & (~Utils.ENEMIES_BIT)) | _turbo_unit_ISOLATED_HITBOX_LAYER
	else:
		if (_hurtbox.collision_mask & _turbo_unit_ISOLATED_HITBOX_LAYER) != 0:
			_hurtbox.collision_mask = (_hurtbox.collision_mask & (~_turbo_unit_ISOLATED_HITBOX_LAYER)) | Utils.ENEMIES_BIT


func _turbo_unit_connect_eb_signals() -> void:
	if _turbo_unit_eb_connected or effect_behaviors == null:
		return
	if not effect_behaviors.is_connected("child_entered_tree", self, "_turbo_unit_on_eb_changed"):
		var _e1 = effect_behaviors.connect("child_entered_tree", self, "_turbo_unit_on_eb_changed")
	if not effect_behaviors.is_connected("child_exiting_tree", self, "_turbo_unit_on_eb_changed"):
		var _e2 = effect_behaviors.connect("child_exiting_tree", self, "_turbo_unit_on_eb_changed")
	_turbo_unit_eb_connected = true


func _turbo_unit_on_eb_changed(_node: Node) -> void:
	_turbo_unit_eb_dirty = true


func _turbo_unit_get_eb_children() -> Array:
	if effect_behaviors == null:
		if not _turbo_eb_cache.empty():
			_turbo_eb_cache.clear()
		_turbo_unit_eb_dirty = false
		return _turbo_eb_cache
	if _turbo_unit_eb_dirty:
		_turbo_unit_eb_dirty = false
		if effect_behaviors.get_child_count() == 0:
			_turbo_eb_cache.clear()
		else:
			_turbo_eb_cache = effect_behaviors.get_children()
	return _turbo_eb_cache


func _turbo_unit_reset_flash() -> void:
	_turbo_unit_next_flash_ms = 0
	if _flash_timer != null and not _flash_timer.is_stopped():
		_flash_timer.stop()
	if _turbo_unit_mod_flashing:
		_turbo_unit_mod_flashing = false
		if sprite != null:
			var cur: Color = sprite.self_modulate
			var app: Color = _turbo_unit_applied_modulate
			if abs(cur.r - app.r) < _turbo_unit_COLOR_EPS and abs(cur.g - app.g) < _turbo_unit_COLOR_EPS and abs(cur.b - app.b) < _turbo_unit_COLOR_EPS:
				sprite.self_modulate = Color(_turbo_unit_base_modulate.r, _turbo_unit_base_modulate.g, _turbo_unit_base_modulate.b, cur.a)
	if sprite != null:
		if flash_mat != null and sprite.material == flash_mat:
			sprite.material = _non_flash_material
		elif flash_shield_mat != null and sprite.material == flash_shield_mat:
			sprite.material = _non_flash_shield_material


func _turbo_unit_apply_material(mat: ShaderMaterial) -> void:
	if sprite == null:
		return
	var handled: bool = false
	if flash_mat != null and sprite.material == flash_mat:
		_non_flash_material = mat
		handled = true
	if flash_shield_mat != null and sprite.material == flash_shield_mat:
		_non_flash_shield_material = mat
		handled = true
	if handled:
		return
	if sprite.material != mat:
		sprite.material = mat


func _set_outlines(alpha: float = 1.0, desaturation: float = 0.0) -> void:
	var s = _turbo_unit_state
	if s == null:
		s = _turbo_unit_STATE_SCRIPT.HOLDER.get("state")
		_turbo_unit_state = s
	if s != null and not s.pool_outline_materials:
		._set_outlines(alpha, desaturation)
		return
	if not _outline_colors:
		_turbo_unit_apply_material(null)
		return
	if sprite == null or sprite.texture == null or outline_material == null or outline_material.shader == null:
		return
	var eff_alpha: float = alpha if alpha < 1.0 else _current_material_alpha
	if alpha < 1.0:
		_current_material_alpha = alpha
	var eff_desat: float = desaturation if desaturation > 0.0 else _current_material_desaturation
	if desaturation > 0.0:
		_current_material_desaturation = desaturation
	var pooled: ShaderMaterial = _turbo_unit_MAT_POOL.get_outline_material(
		outline_material.shader,
		sprite.texture.get_size(),
		eff_alpha,
		eff_desat,
		_outline_colors
	)
	if pooled != null:
		_turbo_unit_apply_material(pooled)
	else:
		._set_outlines(alpha, desaturation)


func _integrate_forces(state: Physics2DDirectBodyState) -> void:
	if sleeping:
		return
	if mode == MODE_KINEMATIC:
		state.transform.origin = global_position
		return

	var origin: Vector2 = state.transform.origin
	var ox: float = origin.x
	var oy: float = origin.y
	var step: float = state.step
	var vx: float = _integrate_forces_velocity.x
	var vy: float = _integrate_forces_velocity.y
	var sx: float = vx * step
	var sy: float = vy * step

	if should_collide_with_borders:
		var s = _turbo_unit_state
		var min_x: float
		var min_y: float
		var max_x: float
		var max_y: float
		if s != null and s.tick_zone_valid:
			min_x = s.tick_zone_min_x
			min_y = s.tick_zone_min_y
			max_x = s.tick_zone_max_x
			max_y = s.tick_zone_max_y
		else:
			var zr: Rect2 = ZoneService.get_current_zone_rect()
			min_x = zr.position.x
			min_y = zr.position.y
			max_x = zr.position.x + zr.size.x
			max_y = zr.position.y + zr.size.y
		var nx: float = ox + sx
		var ny: float = oy + sy
		if nx < min_x or nx > max_x or ny < min_y or ny > max_y:
			nx = clamp(nx, min_x, max_x)
			ny = clamp(ny, min_y, max_y)
			sx = nx - ox
			sy = ny - oy
			if step > 0.0:
				var inv_step: float = 1.0 / step
				vx = sx * inv_step
				vy = sy * inv_step
				_integrate_forces_velocity = Vector2(vx, vy)

	if (vx == 0.0 and vy == 0.0) or not _can_move or _move_locked:
		state.linear_velocity = _integrate_forces_velocity
		return

	var target_position = _current_movement_behavior.get_target_position()
	if target_position == null:
		state.linear_velocity = _integrate_forces_velocity
		return

	var tx: float = target_position.x - ox
	var ty: float = target_position.y - oy
	var step_sq: float = sx * sx + sy * sy
	if tx * tx + ty * ty > step_sq:
		state.linear_velocity = _integrate_forces_velocity
		return

	var proj_t: float = (tx * sx + ty * sy) / step_sq if step_sq > 0.0 else 0.0
	var px: float = sx * proj_t
	var py: float = sy * proj_t
	if (sx - px) * (-px) + (sy - py) * (-py) <= 0.0:
		state.linear_velocity = Vector2.ZERO
		state.transform.origin = target_position
		return
	state.linear_velocity = _integrate_forces_velocity


func has_random_target_movement() -> bool:
	var mb = _current_movement_behavior
	if mb == null:
		return false
	if mb != _turbo_unit_last_mb:
		_turbo_unit_last_mb = mb
		_turbo_unit_has_rand_mb = mb.picks_random_targets()
	return _turbo_unit_has_rand_mb


func get_next_velocity() -> Vector2:
	if _current_movement.x == 0.0 and _current_movement.y == 0.0:
		_last_move_input = Vector2.ZERO
	else:
		_last_move_input = get_move_input()
	var kx: float = knockback_vector.x
	var ky: float = knockback_vector.y
	if kx == 0.0 and ky == 0.0:
		_last_knockback_value = Vector2.ZERO
		return _last_move_input
	if kx * kx + ky * ky < 1e-6:
		knockback_vector = Vector2.ZERO
		_last_knockback_value = Vector2.ZERO
		return _last_move_input
	_last_knockback_value = get_next_knockback_value()
	return _last_move_input + _last_knockback_value


func update_animation(movement: Vector2) -> void:
	if _turbo_unit_state != null and not _turbo_unit_state.guard_unit_transforms:
		.update_animation(movement)
		return
	if not mirror_sprite_with_movement or movement.x == 0.0 or sprite == null:
		return
	var sx: float = sprite.scale.x
	if movement.x > 0.0:
		if sx < 0.0:
			sprite.scale.x = -sx
	else:
		if sx > 0.0:
			sprite.scale.x = -sx


func take_damage(value: int, args: TakeDamageArgs) -> Array:
	if _pending_die:
		return [0, 0, false]

	var hitbox = args.hitbox
	var from_player_index = args.from_player_index

	var crit_damage = 0.0
	var crit_chance = 0.0
	var knockback_direction = Vector2.ZERO
	var knockback_amount = 0.0
	var knockback_piercing = 0.0
	var dmg_taken = [0, 0, false]

	if hitbox != null:
		crit_damage = hitbox.crit_damage
		crit_chance = hitbox.crit_chance
		knockback_direction = hitbox.knockback_direction
		if from_player_index >= 0 and from_player_index < players_ref.size() and is_instance_valid(players_ref[from_player_index]):
			knockback_direction = 0.2 * knockback_direction + 0.8 * players_ref[from_player_index].global_position.direction_to(global_position)
		knockback_amount = hitbox.knockback_amount
		knockback_piercing = hitbox.knockback_piercing

	var is_crit = true if Utils.get_chance_success(crit_chance) else false
	var is_one_shot = false
	if hitbox:
		for effect in hitbox.effects:
			if _is_burning and effect.key_hash == Keys.crit_on_hitting_burning_target_hash:
				is_crit = true
			elif effect.key_hash == Keys.crit_on_whip_tip_hash and is_instance_valid(hitbox.from) and hitbox.from.has_method("is_target_at_tip"):
				if hitbox.from.is_target_at_tip(self, effect.value):
					is_crit = true
			elif effect is OneShotOnHitEffect:
				if Utils.get_chance_success(effect.value / 100.0):
					is_one_shot = true
					_on_one_shotted(effect)
				else:
					is_one_shot = false

	var dmg_value = value
	var sound = Utils.get_rand_element(hurt_sounds)
	if is_crit:
		dmg_value = round(value * crit_damage) as int
		sound = Utils.get_rand_element(crit_sounds)

	var dmg_value_result = get_damage_value(dmg_value, from_player_index, args.armor_applied, args.dodgeable, is_crit, hitbox, args.is_burning)
	var full_dmg_value: int = dmg_value_result.value
	var armor_did_something: bool = dmg_value_result.armor_did_something

	if is_one_shot:
		full_dmg_value = int(max(current_stats.health, full_dmg_value))
		if hitbox:
			hitbox.one_shot_something(self)
	dmg_taken = clamp(full_dmg_value, 0, current_stats.health)
	current_stats.health = max(0.0, current_stats.health - full_dmg_value) as int

	if (is_crit or is_one_shot) and hitbox:
		hitbox.critically_hit_something(self, dmg_taken)
		if hitbox.from != null:
			emit_signal("crit_effect", hitbox.from)

	if full_dmg_value > 0 and not args.hide_feedback:
		flash()

	if args.custom_sound:
		sound = args.custom_sound

	if not args.hide_feedback:
		SoundManager2D.play(sound, global_position, 0, 0.2)

	var final_knockback_amount = knockback_amount

	if final_knockback_amount < 0 and hitbox != null and from_player_index >= 0 and from_player_index < players_ref.size():
		final_knockback_amount = get_knockback_amount_based_on_distance_to_attacker(final_knockback_amount, hitbox, players_ref[from_player_index])
	elif knockback_piercing > 0:
		final_knockback_amount = get_increased_piercing_knockback_amount(knockback_amount, knockback_piercing, stats.knockback_resistance)

	knockback_vector = knockback_direction * final_knockback_amount
	emit_signal("health_updated", self, current_stats.health, max_stats.health)

	var hit_type = HitType.NORMAL

	var eb_list: Array = _turbo_unit_get_eb_children()
	if not eb_list.empty():
		for effect_behavior in eb_list:
			if is_instance_valid(effect_behavior) and not effect_behavior.is_queued_for_deletion():
				var behavior_hit_type_result = effect_behavior.on_taken_damage(args)
				if behavior_hit_type_result != HitType.NORMAL:
					hit_type = behavior_hit_type_result

	if current_stats.health <= 0:
		if hitbox:
			hitbox.killed_something(self)

		_die_args_unit.knockback_vector = knockback_direction * max(knockback_amount, MIN_DEATH_KNOCKBACK_AMOUNT)
		_die_args_unit.killed_by_player_index = from_player_index
		_die_args_unit.killing_blow_dmg_value = full_dmg_value
		_die_args_unit.is_burning = args.is_burning
		call_deferred("die", _die_args_unit)
		_pending_die = true

		if from_player_index >= 0 and Utils.get_chance_success(RunData.get_player_effect(Keys.heal_on_kill_hash, from_player_index) / 100.0):
			RunData.emit_signal("healing_effect", 1, from_player_index, Keys.item_goblet_hash)
		if is_crit:
			assert(from_player_index >= 0)

			var gold_added = 0
			var gold_on_crit_kill_effects = RunData.get_player_effect(Keys.gold_on_crit_kill_hash, from_player_index)
			for effect in gold_on_crit_kill_effects:
				if Utils.get_chance_success(effect[1] / 100.0):
					gold_added += 1
					RunData.add_tracked_value(from_player_index, Keys.item_hunting_trophy_hash, 1)

			if Utils.get_chance_success(RunData.get_player_effect(Keys.heal_on_crit_kill_hash, from_player_index) / 100.0):
				RunData.emit_signal("healing_effect", 1, from_player_index, Keys.item_tentacle_hash)

			if hitbox != null:
				for effect in hitbox.effects:
					if effect.key_hash == Keys.gold_on_crit_kill_hash and randf() <= effect.value / 100.0:
						gold_added += 1
						hitbox.added_gold_on_crit(gold_added)

			if gold_added > 0:
				RunData.add_gold(gold_added, from_player_index)
				hit_type = HitType.GOLD_ON_CRIT_KILL

	emit_signal(
		"took_damage",
		self,
		full_dmg_value,
		knockback_direction,
		is_crit,
		false,
		false,
		armor_did_something,
		args,
		hit_type,
		is_one_shot
	)

	return [full_dmg_value, dmg_taken, false]


func get_damage_value(dmg_value: int, from_player_index: int, armor_applied: = true, _dodgeable: = true, _is_crit: = false, hitbox: Hitbox = null, _p_is_burning: = false) -> GetDamageValueResult:
	var result = _damage_value_result
	result.value = 0
	result.dodged = false
	result.protected = false
	result.armor_did_something = false
	var total_bonus_damage = 0

	if hitbox:
		for effect in hitbox.effects:
			if effect.key_hash == Keys.bonus_damage_against_targets_above_hp_hash and current_stats.health >= (effect.value2 / 100.0) * max_stats.health:
				total_bonus_damage += effect.value
			elif effect.key_hash == Keys.bonus_damage_against_targets_below_hp_hash and current_stats.health <= (effect.value2 / 100.0) * max_stats.health:
				total_bonus_damage += effect.value

		if from_player_index >= 0:
			var bonus_non_elemental_damage_against_burning_targets = RunData.get_player_effect(Keys.bonus_non_elemental_damage_against_burning_targets_hash, from_player_index)
			if bonus_non_elemental_damage_against_burning_targets > 0 and _is_burning:
				var is_elemental = false
				for scaling_stat in hitbox.scaling_stats:
					assert(scaling_stat[0] is int)
					if scaling_stat[0] == Keys.stat_elemental_damage_hash:
						is_elemental = true
						break

				if not is_elemental:
					total_bonus_damage += bonus_non_elemental_damage_against_burning_targets

	var eb_list: Array = _turbo_unit_get_eb_children()
	if not eb_list.empty():
		for effect_behavior in eb_list:
			if is_instance_valid(effect_behavior) and not effect_behavior.is_queued_for_deletion():
				total_bonus_damage += effect_behavior.get_bonus_damage(hitbox, from_player_index)

	if from_player_index >= 0:
		var bonus_damage_against_targets_above_hp_from_items = RunData.get_player_effect(Keys.bonus_damage_against_targets_above_hp_hash, from_player_index)
		if bonus_damage_against_targets_above_hp_from_items.size() > 0:
			assert(from_player_index >= 0)
			for bonus in bonus_damage_against_targets_above_hp_from_items:
				if current_stats.health >= (bonus[1] / 100.0) * max_stats.health:
					total_bonus_damage += bonus[0]

		var bonus_damage_against_targets_below_hp_from_items = RunData.get_player_effect(Keys.bonus_damage_against_targets_below_hp_hash, from_player_index)
		if bonus_damage_against_targets_below_hp_from_items.size() > 0:
			assert(from_player_index >= 0)
			for bonus in bonus_damage_against_targets_below_hp_from_items:
				if current_stats.health <= (bonus[1] / 100.0) * max_stats.health:
					total_bonus_damage += bonus[0]

	dmg_value = round(dmg_value * (1.0 + (total_bonus_damage / 100.0))) as int

	result.value = max(1, dmg_value - current_stats.armor) as int if armor_applied else dmg_value

	if armor_applied and dmg_value != result.value:
		result.armor_did_something = true

	return result


func flash() -> void:
	if sprite == null or _flash_timer == null:
		return
	var s = _turbo_unit_state
	if s != null:
		if s.disable_flash or s.stream_potato:
			return
		if s.cull_offscreen and s.cam_valid and not s.cam_rect_unit.has_point(global_position):
			return
		if s.throttle_flashes and s.flash_interval_ms > 0:
			var now_ms: int = OS.get_ticks_msec()
			if now_ms < _turbo_unit_next_flash_ms:
				return
			_turbo_unit_next_flash_ms = now_ms + s.flash_interval_ms

		if s.batch_friendly_flash:
			if flash_mat != null and sprite.material == flash_mat:
				sprite.material = _non_flash_material
			elif flash_shield_mat != null and sprite.material == flash_shield_mat:
				sprite.material = _non_flash_shield_material
			var cur_col: Color = sprite.self_modulate
			if not _turbo_unit_mod_flashing:
				_turbo_unit_base_modulate = cur_col
			else:
				var p: Color = _turbo_unit_applied_modulate
				if abs(cur_col.r - p.r) >= _turbo_unit_COLOR_EPS or abs(cur_col.g - p.g) >= _turbo_unit_COLOR_EPS or abs(cur_col.b - p.b) >= _turbo_unit_COLOR_EPS:
					_turbo_unit_base_modulate = cur_col
			var b: Color = _turbo_unit_base_modulate
			var boosted := Color(b.r * _turbo_unit_FLASH_BOOST, b.g * _turbo_unit_FLASH_BOOST, b.b * _turbo_unit_FLASH_BOOST, cur_col.a)
			_turbo_unit_applied_modulate = boosted
			_turbo_unit_mod_flashing = true
			sprite.self_modulate = boosted
			_flash_timer.start()
			return

	if _turbo_unit_mod_flashing:
		_turbo_unit_mod_flashing = false
		var cur_c: Color = sprite.self_modulate
		var app_c: Color = _turbo_unit_applied_modulate
		if abs(cur_c.r - app_c.r) < _turbo_unit_COLOR_EPS and abs(cur_c.g - app_c.g) < _turbo_unit_COLOR_EPS and abs(cur_c.b - app_c.b) < _turbo_unit_COLOR_EPS:
			sprite.self_modulate = Color(_turbo_unit_base_modulate.r, _turbo_unit_base_modulate.g, _turbo_unit_base_modulate.b, cur_c.a)
	.flash()

func flash_shield() -> void:
	var s = _turbo_unit_state
	if s != null and s.batch_friendly_flash:
		flash()
		return
	.flash_shield()


func _on_FlashTimer_timeout() -> void:
	if _turbo_unit_mod_flashing:
		_turbo_unit_mod_flashing = false
		if sprite != null:
			var cur: Color = sprite.self_modulate
			var app: Color = _turbo_unit_applied_modulate
			if abs(cur.r - app.r) < _turbo_unit_COLOR_EPS and abs(cur.g - app.g) < _turbo_unit_COLOR_EPS and abs(cur.b - app.b) < _turbo_unit_COLOR_EPS:
				sprite.self_modulate = Color(_turbo_unit_base_modulate.r, _turbo_unit_base_modulate.g, _turbo_unit_base_modulate.b, cur.a)
			if flash_mat != null and sprite.material == flash_mat:
				sprite.material = _non_flash_material
			elif flash_shield_mat != null and sprite.material == flash_shield_mat:
				sprite.material = _non_flash_shield_material
		return
	if sprite == null or (sprite.material != flash_mat and sprite.material != flash_shield_mat):
		return
	._on_FlashTimer_timeout()

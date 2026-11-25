extends "res://entities/units/enemies/enemy.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Enemy Scan, Grid, Anim Guard, Physics2D Isolation & Interp
# -----------------------------------------------------------------------------
# 1. Preserves 5.3.1: jitter, scalar update_target(), worker-first TurboGrid
#    _slow_enemies_around(), track-inspected anim pause, crowd collision relax.
# 2. Optional enemy hitbox layer isolation (4 -> 16384; charm preserves 16384
#    so uncharm() restores 16384 instead of 4!).
# 3. Deferred _hurtbox.monitoring / _hitbox.monitorable disable in die() and
#    _on_despawn(), restored in respawn().
# 4. Deferred s.interpolator registration after spawn_entity sets global_position.
# 5. Fast-paths in get_charmed_by_player_index() and spawn_evolution_puddle_at().
# NOTE: Never defines _physics_process() here (Defect #12)!
# =============================================================================

const _turbo_enemy_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_enemy_GRID_MIN_COUNT: int = 24
const _turbo_enemy_JITTER_MAX: float = 0.08
const _turbo_enemy_RELAX_HYSTERESIS: int = 15
const _turbo_enemy_ISOLATED_HITBOX_LAYER: int = 16384
const _turbo_enemy_SAFE_LOCO_ANIMS: Dictionary = {
	"move": true,
	"walk": true,
	"idle": true,
	"default": true,
	"reset": true,
	"death": true,
	"die": true
}

var _turbo_enemy_state = null
var _turbo_enemy_next_slow_ms: int = 0
var _turbo_enemy_eb_cache: Array = []
var _turbo_enemy_eb_count: int = -1
var _turbo_enemy_died_target_id: int = 0

var _turbo_enemy_anim_player: AnimationPlayer = null
var _turbo_enemy_anim_paused: bool = false
var _turbo_enemy_can_pause_anim: bool = false
var _turbo_enemy_is_special: bool = false
var _turbo_enemy_mask_relaxed: bool = false
var _turbo_enemy_scene_can_be_boosted: bool = false
var _turbo_enemy_is_exact_base: bool = false


func _ready() -> void: # ADDITION
	_turbo_enemy_state = _turbo_enemy_STATE_SCRIPT.HOLDER.get("state")
	_turbo_enemy_scene_can_be_boosted = can_be_boosted
	var my_scr = get_script()
	_turbo_enemy_is_exact_base = (my_scr != null and my_scr.resource_path == "res://entities/units/enemies/enemy.gd")
	_turbo_enemy_resolve_anim_safety()
	_turbo_enemy_reset_caches()
	_turbo_enemy_apply_jitter()
	_turbo_enemy_apply_hitbox_layer()
	call_deferred("_turbo_enemy_register_interp")
	if not is_connected("died", self, "_turbo_enemy_on_self_died"):
		var _e1 = connect("died", self, "_turbo_enemy_on_self_died")


func _exit_tree() -> void: # ADDITION
	_turbo_enemy_unregister_interp()
	_turbo_enemy_restore_anim()
	_turbo_enemy_restore_mask()


func _turbo_enemy_register_interp() -> void:
	if not is_inside_tree() or dead:
		return
	var s = _turbo_enemy_state
	if s != null and s.interpolator != null:
		s.interpolator.register_node(self)
		if s.interpolator.has_method("reset_node_snapshot"):
			s.interpolator.reset_node_snapshot(self)


func _turbo_enemy_unregister_interp() -> void:
	var s = _turbo_enemy_state
	if s != null and s.interpolator != null:
		s.interpolator.unregister_node(self)


func _turbo_enemy_apply_hitbox_layer() -> void:
	if _hitbox == null:
		return
	var s = _turbo_enemy_state
	if s == null or not s.isolate_enemy_hitbox_layer:
		if not _is_charmed and (_hitbox.collision_layer & _turbo_enemy_ISOLATED_HITBOX_LAYER) != 0:
			_hitbox.collision_layer = (_hitbox.collision_layer & (~_turbo_enemy_ISOLATED_HITBOX_LAYER)) | Utils.ENEMIES_BIT
		return
	if _is_charmed:
		if (_hitbox.collision_layer & _turbo_enemy_ISOLATED_HITBOX_LAYER) != 0:
			_hitbox.collision_layer = (_hitbox.collision_layer & (~_turbo_enemy_ISOLATED_HITBOX_LAYER)) | Utils.PET_PROJECTILES_BIT
		return
	if (_hitbox.collision_layer & Utils.ENEMIES_BIT) != 0:
		_hitbox.collision_layer = (_hitbox.collision_layer & (~Utils.ENEMIES_BIT)) | _turbo_enemy_ISOLATED_HITBOX_LAYER


func _turbo_enemy_sync_crowd() -> bool:
	if dead:
		return false
	_turbo_enemy_sync_crowd_anim(global_position)
	_turbo_enemy_sync_collision_relax()
	return _turbo_enemy_anim_paused or _turbo_enemy_mask_relaxed


func respawn() -> void:
	if _turbo_enemy_state == null:
		_turbo_enemy_state = _turbo_enemy_STATE_SCRIPT.HOLDER.get("state")
	_turbo_enemy_restore_anim()
	_turbo_enemy_restore_mask()
	_turbo_enemy_reset_caches()
	can_be_boosted = _turbo_enemy_scene_can_be_boosted
	.respawn()
	if _hurtbox != null:
		_hurtbox.set_deferred("monitoring", true)
	if _hitbox != null:
		_hitbox.set_deferred("monitorable", true)
	_turbo_enemy_apply_hitbox_layer()
	_turbo_enemy_apply_jitter()
	call_deferred("_turbo_enemy_register_interp")


func die(args: Entity.DieArgs = Utils.default_die_args) -> void:
	_turbo_enemy_unregister_interp()
	.die(args)
	if _hurtbox != null:
		_hurtbox.set_deferred("monitoring", false)
	if _hitbox != null:
		_hitbox.set_deferred("monitorable", false)


func _on_despawn(args: Entity.DieArgs) -> void:
	_turbo_enemy_unregister_interp()
	_turbo_enemy_restore_anim()
	_turbo_enemy_restore_mask()
	._on_despawn(args)
	if _hurtbox != null:
		_hurtbox.set_deferred("monitoring", false)
	if _hitbox != null:
		_hitbox.set_deferred("monitorable", false)


func set_charmed(from_player_index: int) -> void:
	_turbo_enemy_restore_mask()
	.set_charmed(from_player_index)
	if _is_charmed:
		if _hitbox != null and (_hitbox.collision_layer & _turbo_enemy_ISOLATED_HITBOX_LAYER) != 0:
			_hitbox.collision_layer = Utils.PET_PROJECTILES_BIT
		_turbo_unit_sync_hurtbox_mask()
	else:
		_turbo_enemy_apply_hitbox_layer()


func get_time_factor() -> float:
	if _is_charmed:
		return 1.0
	var s = _turbo_enemy_state
	if s != null and s.in_run:
		return s.tick_enemy_tf
	return EntityService.enemy_time_factor


func _apply_time_factor_to_animation(time_factor: float) -> void:
	if time_factor == 1.0 and _animation_time_factor == 1.0 and _animation_player != null and _animation_player.playback_speed == _animation_time_scaled_speed:
		return
	._apply_time_factor_to_animation(time_factor)


func is_playing_shoot_animation() -> bool:
	if _animation_player == null:
		return false
	var a: String = _animation_player.current_animation
	return a == "shoot" or a == "shoot_charmed"


func get_next_velocity() -> Vector2:
	if _turbo_enemy_is_special or not _turbo_enemy_is_exact_base:
		return .get_next_velocity()
	var mx: float = _current_movement.x
	var my: float = _current_movement.y
	if mx == 0.0 and my == 0.0:
		_last_move_input = Vector2.ZERO
	else:
		var raw_spd: float = current_stats.speed + bonus_speed + decaying_bonus_speed
		if raw_spd <= 0.0:
			_last_move_input = Vector2.ZERO
		else:
			var tf: float = 1.0 if _is_charmed else (_turbo_enemy_state.tick_enemy_tf if (_turbo_enemy_state != null and _turbo_enemy_state.in_run) else EntityService.enemy_time_factor)
			var spd: float = raw_spd * tf
			var lsq: float = mx * mx + my * my
			if abs(lsq - 1.0) > 0.0002:
				var inv_len: float = spd / sqrt(lsq)
				_last_move_input = Vector2(mx * inv_len, my * inv_len)
			else:
				_last_move_input = Vector2(mx * spd, my * spd)
	var kx: float = knockback_vector.x
	var ky: float = knockback_vector.y
	if kx == 0.0 and ky == 0.0:
		_last_knockback_value = Vector2.ZERO
		return _last_move_input
	kx *= 0.9
	ky *= 0.9
	if kx * kx + ky * ky < 1e-6:
		knockback_vector = Vector2.ZERO
		_last_knockback_value = Vector2.ZERO
		return _last_move_input
	knockback_vector = Vector2(kx, ky)
	var kb_mult: float = 100.0 - stats.knockback_resistance * 100.0
	_last_knockback_value = Vector2(kx * kb_mult, ky * kb_mult)
	return _last_move_input + _last_knockback_value


func get_charmed_by_player_index() -> int:
	if not _is_charmed:
		return -1
	return .get_charmed_by_player_index()


func spawn_evolution_puddle_at(pos: Vector2, is_small: bool = true) -> void:
	if _is_charmed or (not _is_mutant and not _is_meca):
		return
	.spawn_evolution_puddle_at(pos, is_small)


func _turbo_enemy_resolve_anim_safety() -> void:
	_turbo_enemy_can_pause_anim = false
	if "_animation_player" in self and get("_animation_player") is AnimationPlayer:
		_turbo_enemy_anim_player = get("_animation_player")
	else:
		_turbo_enemy_anim_player = get_node_or_null("AnimationPlayer") as AnimationPlayer

	var scr = get_script()
	var path_lc: String = scr.resource_path.to_lower() if scr != null else ""
	var scene_lc: String = filename.to_lower()
	_turbo_enemy_is_special = (
		("is_loot" in self and bool(get("is_loot")))
		or ("is_boss" in self and bool(get("is_boss")))
		or ("is_elite" in self and bool(get("is_elite")))
		or ("boss" in path_lc)
		or ("boss" in scene_lc)
		or ("elite" in path_lc)
		or ("elite" in scene_lc)
	)
	if _turbo_enemy_is_special or _turbo_enemy_anim_player == null:
		return

	var anim_names: PoolStringArray = _turbo_enemy_anim_player.get_animation_list()
	if anim_names.empty():
		return

	for raw_name in anim_names:
		var aname: String = raw_name.to_lower()
		if not _turbo_enemy_SAFE_LOCO_ANIMS.has(aname):
			return
		if aname == "death" or aname == "die":
			continue
		var anim_res: Animation = _turbo_enemy_anim_player.get_animation(raw_name)
		if anim_res == null:
			continue
		var t_cnt: int = anim_res.get_track_count()
		for t in range(t_cnt):
			var t_type: int = anim_res.track_get_type(t)
			if t_type == Animation.TYPE_METHOD or t_type == Animation.TYPE_AUDIO:
				return

	_turbo_enemy_can_pause_anim = true


func _turbo_enemy_on_self_died(_a = null, _b = null) -> void:
	_turbo_enemy_restore_anim()
	_turbo_enemy_restore_mask()


func _turbo_enemy_restore_anim() -> void:
	if _turbo_enemy_anim_paused:
		_turbo_enemy_anim_paused = false
		if is_instance_valid(_turbo_enemy_anim_player):
			_turbo_enemy_anim_player.playback_active = true


func _turbo_enemy_restore_mask() -> void:
	if _turbo_enemy_mask_relaxed:
		_turbo_enemy_mask_relaxed = false
		collision_mask = collision_mask | Utils.ENEMIES_BIT


func _turbo_enemy_sync_collision_relax() -> void:
	var charmed: bool = ("_is_charmed" in self and bool(get("_is_charmed"))) or collision_layer == Utils.PETS_BIT
	var loot_flag: bool = ("is_loot" in self and bool(get("is_loot")))
	if _turbo_enemy_is_special or dead or loot_flag or charmed:
		if _turbo_enemy_mask_relaxed:
			_turbo_enemy_restore_mask()
		return
	var s = _turbo_enemy_state
	if s == null or not s.relax_enemy_collisions:
		if _turbo_enemy_mask_relaxed:
			_turbo_enemy_restore_mask()
		return
	var thr: int = s.relax_collision_threshold
	if not _turbo_enemy_mask_relaxed:
		if s.census_enemies >= thr and (collision_mask & Utils.ENEMIES_BIT) != 0:
			collision_mask = collision_mask & (~Utils.ENEMIES_BIT)
			_turbo_enemy_mask_relaxed = true
	else:
		var off_thr: int = int(max(0, thr - _turbo_enemy_RELAX_HYSTERESIS))
		if s.census_enemies < off_thr:
			_turbo_enemy_restore_mask()


func _turbo_enemy_sync_crowd_anim(my_pos: Vector2) -> void:
	if not _turbo_enemy_can_pause_anim or not is_instance_valid(_turbo_enemy_anim_player):
		return
	var s = _turbo_enemy_state
	if s == null or not s.pause_crowd_idle_anim or dead or s.census_enemies < s.crowd_anim_threshold:
		if _turbo_enemy_anim_paused:
			_turbo_enemy_restore_anim()
		return

	var offscreen: bool = s.cull_offscreen and s.cam_valid and not s.cam_rect_unit.has_point(my_pos)
	var want_pause: bool = offscreen or s.tier >= 4
	if not want_pause:
		if _turbo_enemy_anim_paused:
			_turbo_enemy_restore_anim()
		return

	var cur_anim: String = _turbo_enemy_anim_player.current_animation
	if cur_anim == "move" or cur_anim == "walk" or cur_anim == "idle":
		if not _turbo_enemy_anim_paused:
			_turbo_enemy_anim_player.playback_active = false
			_turbo_enemy_anim_paused = true
	elif _turbo_enemy_anim_paused:
		_turbo_enemy_restore_anim()


func _turbo_enemy_reset_caches() -> void:
	_turbo_enemy_next_slow_ms = 0
	_turbo_enemy_eb_cache.clear()
	_turbo_enemy_eb_count = -1
	_turbo_enemy_died_target_id = 0


func _turbo_enemy_apply_jitter() -> void:
	var raw_id: int = get_instance_id()
	var mixed: int = (raw_id ^ (raw_id >> 16) ^ (raw_id >> 32)) & 0x3FFFFFFF
	mixed = (mixed * 73244475) ^ (mixed >> 11)
	update_target_timer = float(mixed & 0xFF) * (_turbo_enemy_JITTER_MAX / 255.0)


func _slow_enemies_around(slow_percent: float, duration: float, radius: float) -> void:
	var s = _turbo_enemy_state
	if s != null and not s.throttle_slow_scans:
		._slow_enemies_around(slow_percent, duration, radius)
		return

	var interval_ms: int = s.slow_scan_interval_ms if s != null else 250
	if interval_ms > 0:
		var now_ms: int = OS.get_ticks_msec()
		if now_ms < _turbo_enemy_next_slow_ms:
			return
		_turbo_enemy_next_slow_ms = now_ms + interval_ms

	if _entity_spawner_ref == null or radius < 0.0:
		return

	var origin: Vector2 = global_position
	if s != null and s.grid != null and s.grid.worker != null and s.grid.worker.is_running():
		var w_nearby = s.grid.worker.try_query_radius(origin, radius, Engine.get_physics_frames(), 3)
		if w_nearby != null:
			for enemy in w_nearby:
				if is_instance_valid(enemy) and not enemy.dead:
					enemy.add_decaying_speed(-(enemy.current_stats.speed * slow_percent / 100.0) as int, true, duration)
			return

	var all_enemies: Array = _entity_spawner_ref.get_all_enemies(false)
	var count: int = all_enemies.size()
	if count == 0:
		return

	if count >= _turbo_enemy_GRID_MIN_COUNT and s != null and s.grid != null:
		var nearby: Array = s.grid.query_radius(origin, radius, all_enemies)
		for enemy in nearby:
			if is_instance_valid(enemy) and not enemy.dead:
				enemy.add_decaying_speed(-(enemy.current_stats.speed * slow_percent / 100.0) as int, true, duration)
		return

	var ox: float = origin.x
	var oy: float = origin.y
	var r_sq: float = radius * radius
	for enemy in all_enemies:
		if not is_instance_valid(enemy) or enemy.dead:
			continue
		var epos: Vector2 = enemy.global_position
		var dx: float = epos.x - ox
		var dy: float = epos.y - oy
		if dx <= radius and dx >= -radius and dy <= radius and dy >= -radius:
			if dx * dx + dy * dy <= r_sq:
				enemy.add_decaying_speed(-(enemy.current_stats.speed * slow_percent / 100.0) as int, true, duration)


func update_target() -> void:
	var min_dist_squared: float = float(Utils.LARGE_NUMBER)
	var my_pos: Vector2 = global_position
	var mx: float = my_pos.x
	var my: float = my_pos.y

	if _entity_spawner_ref != null:
		var pets: Array = _entity_spawner_ref.targetable_pets
		if not pets.empty():
			for pet in pets:
				if not is_instance_valid(pet) or pet.dead:
					continue
				var ppos: Vector2 = pet.global_position
				var pdx: float = ppos.x - mx
				var pdy: float = ppos.y - my
				var p_sq: float = pdx * pdx + pdy * pdy
				if p_sq < min_dist_squared:
					min_dist_squared = p_sq
					current_target = pet

	if players_ref != null:
		for player in players_ref:
			if not is_instance_valid(player) or player.dead:
				continue
			var plpos: Vector2 = player.global_position
			var dx: float = plpos.x - mx
			var dy: float = plpos.y - my
			var dist_squared: float = dx * dx + dy * dy
			if dist_squared < min_dist_squared:
				min_dist_squared = dist_squared
				current_target = player

	var eb_list: Array = _turbo_unit_get_eb_children()
	if not eb_list.empty():
		for effect_behavior in eb_list:
			if is_instance_valid(effect_behavior) and not effect_behavior.is_queued_for_deletion():
				effect_behavior.update_target()

	if current_target != null and is_instance_valid(current_target):
		var target_id: int = current_target.get_instance_id()
		if target_id != _turbo_enemy_died_target_id:
			if not current_target.is_connected("died", self, "_on_target_died"):
				var _err = current_target.connect("died", self, "_on_target_died")
			_turbo_enemy_died_target_id = target_id

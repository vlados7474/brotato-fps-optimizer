extends "res://main.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - O(1) Endless Gold, Pool Prewarm, Gold Z-Bucketing
# & Safe Opt-In Fruit Compressor (_turbo_main_)
# -----------------------------------------------------------------------------
# 1. Hybrid O(1) on_gold_picked_up() when player_index >= 0 and gold.value > 16
#    (fixed L34 bug: removed RunData.bonus_gold > 0 fallback so O(1) stays
#    active even when bonus_gold is carried over from the previous wave).
# 2. Optional wave-start pool prewarm (s.prewarm_pools): pre-instantiates and
#    wires Gold (x50), Consumable (x24), and EntityBirth (x32) in _ready().
# 3. Optional Gold Z-bucketing (s.z_bucket_shadows_gold): sets
#    z_as_relative = false and z_index = -5 on prewarmed and spawned gold.
# 4. Safe opt-in Fruit Compressor (compress_excess_fruits / max_ground_fruits).
# 5. Never touches _physics_process() so Godot 3 multilevel cascade is intact.
# =============================================================================

const _turbo_main_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_main_MAT_POOL = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_material_pool.gd")
const _turbo_main_BAKER = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_projectile_baker.gd")
const _turbo_main_MAX_FRUIT_STACK: int = 12
const _turbo_main_GOLD_FAST_THRESHOLD: float = 16.0
const _turbo_main_PREWARM_GOLD: int = 50
const _turbo_main_PREWARM_CONSUMABLE: int = 64
const _turbo_main_PREWARM_BIRTH: int = 40
const _turbo_main_GOLD_Z_INDEX: int = -5
const _turbo_main_MAX_POOL_PER_ID: int = 96

var _turbo_main_state = null
var _turbo_main_fruit_stacks: Dictionary = {}
var _turbo_main_compress_queued: bool = false
var _turbo_main_compress_start_idx: int = 0
var _turbo_main_compress_cap: int = 40
var _turbo_main_z_bucket_queued: bool = false


func _ready() -> void: # ADDITION
	_turbo_main_state = _turbo_main_STATE_SCRIPT.HOLDER.get("state")
	if _turbo_main_state == null:
		_turbo_main_state = _turbo_main_STATE_SCRIPT.instance()
	_turbo_main_fruit_stacks.clear()
	_turbo_main_z_bucket_queued = false
	if _turbo_main_state != null and _turbo_main_state.prewarm_pools:
		_turbo_main_prewarm_pools()


func _exit_tree() -> void: # ADDITION
	_turbo_main_fruit_stacks.clear()


func _turbo_main_prewarm_pools() -> void:
	var s = _turbo_main_state
	var z_bucket: bool = (s != null and s.z_bucket_shadows_gold)

	if gold_scene != null and _gold_pool_id != Keys.empty_hash and is_instance_valid(_materials_container):
		if not _pool.has(_gold_pool_id):
			_pool[_gold_pool_id] = []
		var gold_pool: Array = _pool[_gold_pool_id]
		while gold_pool.size() < _turbo_main_PREWARM_GOLD:
			var gold = gold_scene.instance()
			var _e1 = gold.connect("picked_up", self, "on_gold_picked_up")
			var _e2 = gold.connect("picked_up", _effects_manager, "on_gold_picked_up")
			var _e3 = gold.connect("picked_up", _floating_text_manager, "on_gold_picked_up")
			if z_bucket:
				gold.z_as_relative = false
				gold.z_index = _turbo_main_GOLD_Z_INDEX
			_materials_container.add_child(gold)
			_materials_container.remove_child(gold)
			gold_pool.push_back(gold)

	if consumable_scene != null and _consumable_pool_id != Keys.empty_hash and is_instance_valid(_consumables_container):
		if not _pool.has(_consumable_pool_id):
			_pool[_consumable_pool_id] = []
		var cons_pool: Array = _pool[_consumable_pool_id]
		while cons_pool.size() < _turbo_main_PREWARM_CONSUMABLE:
			var cons = consumable_scene.instance()
			var _ec = cons.connect("picked_up", self, "on_consumable_picked_up")
			_consumables_container.add_child(cons)
			_consumables_container.remove_child(cons)
			cons_pool.push_back(cons)

	if is_instance_valid(_entity_spawner) and _entity_spawner.entity_birth_scene != null and is_instance_valid(_births_container):
		var birth_pool_id: int = _entity_spawner._entity_birth_pool_id
		if birth_pool_id != Keys.empty_hash:
			if not _pool.has(birth_pool_id):
				_pool[birth_pool_id] = []
			var birth_pool: Array = _pool[birth_pool_id]
			var birth_scene: PackedScene = _entity_spawner.entity_birth_scene
			while birth_pool.size() < _turbo_main_PREWARM_BIRTH:
				var birth = birth_scene.instance()
				var _eb = birth.connect("birth_timeout", _entity_spawner, "on_entity_birth_timeout")
				_births_container.add_child(birth)
				birth.hide()
				birth.set_physics_process(false)
				if "_collision_shape" in birth and birth._collision_shape != null:
					birth._collision_shape.set_disabled(true)
				_births_container.remove_child(birth)
				birth_pool.push_back(birth)


func spawn_gold(value: float, pos: Vector2, spread: int) -> void:
	var prev_count: int = _active_golds.size()
	.spawn_gold(value, pos, spread)
	var s = _turbo_main_state
	if s != null and s.z_bucket_shadows_gold:
		var cur_count: int = _active_golds.size()
		if cur_count > prev_count:
			var i: int = prev_count
			while i < cur_count:
				var g = _active_golds[i]
				if is_instance_valid(g) and (g.z_as_relative or g.z_index != _turbo_main_GOLD_Z_INDEX):
					g.z_as_relative = false
					g.z_index = _turbo_main_GOLD_Z_INDEX
				i += 1
		elif cur_count < MAX_GOLDS and not _turbo_main_z_bucket_queued:
			_turbo_main_z_bucket_queued = true
			call_deferred("_turbo_main_z_bucket_active_golds")


func _turbo_main_z_bucket_active_golds() -> void:
	_turbo_main_z_bucket_queued = false
	if not is_inside_tree() or _cleaning_up:
		return
	var s = _turbo_main_state
	if s == null or not s.z_bucket_shadows_gold:
		return
	for g in _active_golds:
		if is_instance_valid(g) and (g.z_as_relative or g.z_index != _turbo_main_GOLD_Z_INDEX):
			g.z_as_relative = false
			g.z_index = _turbo_main_GOLD_Z_INDEX


func on_gold_picked_up(gold: Node, player_index: int) -> void:
	if not is_instance_valid(gold) or player_index < 0 or float(gold.value) <= _turbo_main_GOLD_FAST_THRESHOLD:
		.on_gold_picked_up(gold, player_index)
		return
	if gold.already_picked_up:
		return

	gold.already_picked_up = true
	_active_golds.erase(gold)
	add_node_to_pool(gold, _gold_pool_id)

	if ProgressData.settings.alt_gold_sounds:
		SoundManager.play(Utils.get_rand_element(gold_alt_pickup_sounds), -5, 0.2)
	else:
		SoundManager.play(Utils.get_rand_element(gold_pickup_sounds), 0, 0.2)

	var increase_effect: int = RunData.get_player_effect(Keys.increase_material_value_hash, player_index)
	var value: float = float(gold.value)
	value += value * (float(increase_effect) / 100.0)

	var boost: int = RunData.apply_common_gold_pickup_effects(int(gold.value), player_index)
	value *= float(boost)
	gold.boosted *= boost

	if Utils.get_chance_success(float(RunData.get_player_effect(Keys.heal_when_pickup_gold_hash, player_index)) / 100.0):
		RunData.emit_signal("healing_effect", 1, player_index, Keys.item_cute_monkey_hash)

	var dmg_when_pickup_gold_effect = RunData.get_player_effect(Keys.dmg_when_pickup_gold_hash, player_index)
	if dmg_when_pickup_gold_effect.size() > 0:
		handle_stat_damages(dmg_when_pickup_gold_effect, player_index)

	var highest_cd_weapon = null
	if player_index < _players.size() and is_instance_valid(_players[player_index]):
		for weapon in _players[player_index].current_weapons:
			for effect in weapon.effects:
				if effect.key_hash == Keys.reload_when_pickup_gold_hash:
					if not weapon._is_shooting and (highest_cd_weapon == null or weapon._current_cooldown > highest_cd_weapon._current_cooldown):
						highest_cd_weapon = weapon
		if highest_cd_weapon:
			highest_cd_weapon._current_cooldown = 0

	if _entity_spawner != null and not _entity_spawner.structures.empty():
		for structure in _entity_spawner.structures:
			if structure is BuilderTurret:
				for effect in structure.effects:
					if effect.key_hash == Keys.reload_when_pickup_gold_hash:
						structure._cooldown = 0

	if RunData.get_player_effect_bool(Keys.reload_when_pickup_gold_hash, player_index):
		if player_index < _players.size() and is_instance_valid(_players[player_index]):
			for weapon in _players[player_index].current_weapons:
				weapon._current_cooldown = 0

	var total: int = int(ceil(value)) if value > 0.0 else 0
	var player_count: int = RunData.get_player_count()
	if total > 0 and player_count > 0:
		if player_count == 1:
			RunData.add_gold(total, player_index)
			RunData.add_xp(total, player_index)
		else:
			var next_p: int = _next_gold_player % player_count
			var base_share: int = total / player_count
			var rem: int = total % player_count
			for i in range(player_count):
				var dist: int = (i - next_p + player_count) % player_count
				var share: int = base_share + (1 if dist < rem else 0)
				if share > 0:
					RunData.add_gold(share, i)
					RunData.add_xp(share, i)
			_next_gold_player = (next_p + rem) % player_count

	ProgressData.increment_stat("materials_collected")


func _handle_manual_aim_visuals() -> void:
	if RunData.is_coop_run:
		return
	var want_crosshair: bool = false
	var crosshair_cursor: bool = false
	var want_mode: int = -1
	if not _cleaning_up:
		if Utils.is_manual_aim(0):
			if Utils.is_player_using_gamepad(0):
				want_crosshair = true
				want_mode = Input.MOUSE_MODE_HIDDEN
				var player_pos: Vector2 = _players[0].global_position
				player_pos.y -= 32.0
				_crosshair.global_position = player_pos + CROSSHAIR_DIST_FROM_PLAYER_MANUAL_AIM * _players[0].gamepad_attack_vector
			else:
				crosshair_cursor = true
				want_mode = Input.MOUSE_MODE_VISIBLE
		elif ProgressData.settings.manual_aim_on_mouse_press and ProgressData.settings.manual_aim:
			want_mode = Input.MOUSE_MODE_VISIBLE
		else:
			want_mode = Input.MOUSE_MODE_HIDDEN
		if ProgressData.settings.mouse_only:
			want_mode = Input.MOUSE_MODE_VISIBLE

	if _crosshair.visible != want_crosshair:
		_crosshair.visible = want_crosshair
	if want_mode != -1 and Input.get_mouse_mode() != want_mode:
		Input.set_mouse_mode(want_mode)
	if crosshair_cursor != _crosshair_cursor_active:
		_set_crosshair_cursor(crosshair_cursor)


func _add_node_to_pool(node: Node, id: int) -> void:
	if not is_instance_valid(node) or node.get_parent() == null:
		return
	if _pool.has(id) and (_pool[id] as Array).size() >= _turbo_main_MAX_POOL_PER_ID:
		node.get_parent().remove_child(node)
		node.queue_free()
		return
	._add_node_to_pool(node, id)


func add_enemy_projectile(instance) -> void:
	.add_enemy_projectile(instance)
	var s = _turbo_main_state
	var use_baker: bool = (s == null or s.optimize_projectiles)
	var use_pool: bool = (s == null or s.pool_outline_materials)
	_turbo_main_BAKER.normalize_projectile(instance, _turbo_main_MAT_POOL, use_baker, use_pool)


func spawn_consumables(unit) -> void:
	var prev_count: int = _consumables.size()
	.spawn_consumables(unit)
	var s = _turbo_main_state
	if s != null and s.compress_excess_fruits and not _cleaning_up:
		_turbo_main_compress_from(prev_count, s.max_ground_fruits)


func on_structure_wanted_to_spawn_fruit(pos: Vector2) -> void:
	var prev_count: int = _consumables.size()
	.on_structure_wanted_to_spawn_fruit(pos)
	var s = _turbo_main_state
	if s != null and s.compress_excess_fruits and not _cleaning_up:
		_turbo_main_compress_from(prev_count, s.max_ground_fruits)


func _turbo_main_compress_from(start_idx: int, max_fruits: int) -> void:
	var cur_size: int = _consumables.size()
	var cap: int = int(max(1, max_fruits))
	if cur_size <= start_idx:
		if not _pool.has(_consumable_pool_id) or _pool[_consumable_pool_id].empty():
			if not _turbo_main_compress_queued:
				_turbo_main_compress_queued = true
				_turbo_main_compress_start_idx = start_idx
				_turbo_main_compress_cap = cap
				call_deferred("_turbo_main_compress_tail")
			else:
				_turbo_main_compress_start_idx = int(min(_turbo_main_compress_start_idx, start_idx))
				_turbo_main_compress_cap = cap
		return
	var i: int = cur_size - 1
	while i >= start_idx:
		if i < _consumables.size():
			_turbo_main_try_compress(_consumables[i], cap)
		i -= 1


func _turbo_main_compress_tail() -> void:
	_turbo_main_compress_queued = false
	if not is_inside_tree() or _cleaning_up:
		return
	var cur_size: int = _consumables.size()
	if cur_size <= _turbo_main_compress_start_idx:
		return
	var i: int = cur_size - 1
	while i >= _turbo_main_compress_start_idx:
		if i < _consumables.size():
			_turbo_main_try_compress(_consumables[i], _turbo_main_compress_cap)
		i -= 1


func despawn_consumable(consumable) -> void:
	if is_instance_valid(consumable):
		var cid: int = consumable.get_instance_id()
		if _turbo_main_fruit_stacks.has(cid):
			_turbo_main_fruit_stacks.erase(cid)
			consumable.scale = Vector2.ONE
	.despawn_consumable(consumable)


func on_consumable_picked_up(consumable: Node, player_index: int) -> void:
	if not is_instance_valid(consumable) or consumable.already_picked_up:
		return

	var cid: int = consumable.get_instance_id()
	var stack_count: int = 1
	if _turbo_main_fruit_stacks.has(cid):
		stack_count = int(_turbo_main_fruit_stacks[cid])
		_turbo_main_fruit_stacks.erase(cid)
		consumable.scale = Vector2.ONE

	var pickup_pos: Vector2 = consumable.global_position
	var c_data: ConsumableData = consumable.consumable_data

	.on_consumable_picked_up(consumable, player_index)

	if stack_count <= 1 or c_data == null or player_index < 0 or player_index >= _players.size():
		return

	var player = _players[player_index]
	for _i in range(stack_count - 1):
		if not is_instance_valid(player) or player.dead:
			break
		player.on_consumable_picked_up(c_data)
		if not _cleaning_up:
			RunData.handle_explode_effect(Keys.explode_on_consumable_hash, pickup_pos, player_index)
			RunData.handle_explode_effect(Keys.explode_on_consumable_burning_hash, pickup_pos, player_index)
		RunData.apply_item_effects(c_data, player_index)


func _turbo_main_is_compressible_data(data: ConsumableData) -> bool:
	if data == null or data.to_be_processed_at_end_of_wave:
		return false
	if data.my_id_hash != Keys.consumable_fruit_hash:
		return false
	if "poison" in data.resource_path.to_lower():
		return false
	return true


func _turbo_main_try_compress(newest, max_fruits: int) -> void:
	if not is_instance_valid(newest) or newest.already_picked_up or newest.attracted_by != null:
		return
	if not _turbo_main_is_compressible_data(newest.consumable_data):
		return
	var add_cnt: int = int(_turbo_main_fruit_stacks.get(newest.get_instance_id(), 1))
	if _turbo_main_try_merge(newest.consumable_data, newest.global_position, add_cnt, max_fruits, newest):
		despawn_consumable(newest)


func _turbo_main_try_merge(data: ConsumableData, pos: Vector2, amount: int, max_fruits: int, exclude: Node) -> bool:
	var fruit_count: int = 0
	var best_target = null
	var best_dist_sq: float = INF
	var px: float = pos.x
	var py: float = pos.y

	for c in _consumables:
		if c == exclude or not is_instance_valid(c) or c.already_picked_up or c.attracted_by != null:
			continue
		if c.consumable_data == null or (c.consumable_data != data and not _turbo_main_is_compressible_data(c.consumable_data)):
			continue
		fruit_count += 1
		var stack: int = int(_turbo_main_fruit_stacks.get(c.get_instance_id(), 1))
		if stack + amount <= _turbo_main_MAX_FRUIT_STACK:
			var cp: Vector2 = c.global_position
			var dx: float = cp.x - px
			var dy: float = cp.y - py
			var d_sq: float = dx * dx + dy * dy
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best_target = c

	if fruit_count < max_fruits or best_target == null:
		return false

	var tid: int = best_target.get_instance_id()
	var new_stack: int = int(_turbo_main_fruit_stacks.get(tid, 1)) + amount
	_turbo_main_fruit_stacks[tid] = new_stack
	var sc: float = min(1.0 + float(new_stack - 1) * 0.05, 1.55)
	best_target.scale = Vector2(sc, sc)
	return true

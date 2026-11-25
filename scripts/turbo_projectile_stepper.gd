extends Node
# =============================================================================
# Saffron-Turbo 5.6.1 - Centralized Flat-Array Projectile Stepper
# -----------------------------------------------------------------------------
# Eliminates 500-868 per-node C++->GDScript _physics_process virtual dispatches
# on exact-leaf EnemyProjectile and PlayerProjectile instances while preserving
# 100% vanilla physics/gameplay parity (exact delta, sinusoidal handoff,
# stop_delay handoff, offscreen stop(true) puddle suppression, rotation parity).
# Never extends res://projectiles/projectile.gd (zero F-A reload risk).
# =============================================================================

const _STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const EP_VANILLA_PATH: String = "res://projectiles/bullet_enemy/enemy_projectile.gd"
const PP_VANILLA_PATH: String = "res://projectiles/player_projectile.gd"

var _state = null
var _tree: SceneTree = null
var ep_leaf_script: Script = null
var pp_leaf_script: Script = null

var _ep_nodes: Array = []
var _ep_ids: Array = []
var _ep_idx: Dictionary = {}

var _pp_nodes: Array = []
var _pp_ids: Array = []
var _pp_idx: Dictionary = {}

var _iterating: bool = false
var _pending_ep_unreg: Dictionary = {}
var _pending_pp_unreg: Dictionary = {}
var _had_slow_tf: bool = false


func _init() -> void:
	process_priority = 0


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_STOP
	process_priority = 0
	_tree = get_tree()
	_state = _STATE_SCRIPT.HOLDER.get("state")
	var ep_modded: bool = false
	var pp_modded: bool = false
	var ml_store = get_node_or_null("/root/ModLoaderStore")
	if ml_store != null and "script_extensions" in ml_store and ml_store.script_extensions is Array:
		for ext_entry in ml_store.script_extensions:
			var es: String = str(ext_entry)
			if "Saffron-Turbo" in es:
				continue
			if "/projectile.gd" in es:
				ep_modded = true
				pp_modded = true
			elif "enemy_projectile.gd" in es:
				ep_modded = true
			elif "player_projectile.gd" in es:
				pp_modded = true
	if not ep_modded and ResourceLoader.exists(EP_VANILLA_PATH):
		var ep_s: Script = load(EP_VANILLA_PATH) as Script
		if _script_chain_depth(ep_s) <= 3:
			ep_leaf_script = ep_s
	if not pp_modded and ResourceLoader.exists(PP_VANILLA_PATH):
		var pp_s: Script = load(PP_VANILLA_PATH) as Script
		if _script_chain_depth(pp_s) <= 3:
			pp_leaf_script = pp_s


func _script_chain_depth(scr: Script) -> int:
	var depth: int = 0
	var cur: Script = scr
	while cur != null:
		depth += 1
		cur = cur.get_base_script()
	return depth


func _exit_tree() -> void:
	_restore_all_physics_process()
	_ep_nodes.clear()
	_ep_ids.clear()
	_ep_idx.clear()
	_pp_nodes.clear()
	_pp_ids.clear()
	_pp_idx.clear()
	_pending_ep_unreg.clear()
	_pending_pp_unreg.clear()


func _restore_all_physics_process() -> void:
	for p in _ep_nodes:
		if is_instance_valid(p):
			p._turbo_ep_stepped = false
			p.set_physics_process(true)
	for pp in _pp_nodes:
		if is_instance_valid(pp):
			pp._turbo_pp_stepped = false
			pp.set_physics_process(true)


func register_enemy(p: Node2D) -> void:
	if p == null or not is_instance_valid(p):
		return
	var pid: int = p.get_instance_id()
	if _pending_ep_unreg.has(pid):
		_pending_ep_unreg.erase(pid)
	if _ep_idx.has(pid):
		return
	if "_animation_time_factor" in p and p._animation_time_factor != 1.0:
		_had_slow_tf = true
	_ep_idx[pid] = _ep_nodes.size()
	_ep_ids.push_back(pid)
	_ep_nodes.push_back(p)


func unregister_enemy(p: Node2D) -> void:
	if p == null or not is_instance_valid(p):
		return
	var pid: int = p.get_instance_id()
	if not _ep_idx.has(pid):
		return
	if _iterating:
		_pending_ep_unreg[pid] = true
		return
	_remove_ep_id(pid)


func register_player(pp: Node2D) -> void:
	if pp == null or not is_instance_valid(pp):
		return
	var pid: int = pp.get_instance_id()
	if _pending_pp_unreg.has(pid):
		_pending_pp_unreg.erase(pid)
	if _pp_idx.has(pid):
		return
	_pp_idx[pid] = _pp_nodes.size()
	_pp_ids.push_back(pid)
	_pp_nodes.push_back(pp)


func unregister_player(pp: Node2D) -> void:
	if pp == null or not is_instance_valid(pp):
		return
	var pid: int = pp.get_instance_id()
	if not _pp_idx.has(pid):
		return
	if _iterating:
		_pending_pp_unreg[pid] = true
		return
	_remove_pp_id(pid)


func _remove_ep_id(pid: int) -> void:
	if not _ep_idx.has(pid):
		return
	var idx: int = int(_ep_idx[pid])
	var last_idx: int = _ep_nodes.size() - 1
	if idx >= 0 and idx <= last_idx:
		if idx != last_idx:
			var moved_id: int = int(_ep_ids[last_idx])
			_ep_ids[idx] = moved_id
			_ep_nodes[idx] = _ep_nodes[last_idx]
			_ep_idx[moved_id] = idx
		_ep_ids.pop_back()
		_ep_nodes.pop_back()
	_ep_idx.erase(pid)


func _remove_pp_id(pid: int) -> void:
	if not _pp_idx.has(pid):
		return
	var idx: int = int(_pp_idx[pid])
	var last_idx: int = _pp_nodes.size() - 1
	if idx >= 0 and idx <= last_idx:
		if idx != last_idx:
			var moved_id: int = int(_pp_ids[last_idx])
			_pp_ids[idx] = moved_id
			_pp_nodes[idx] = _pp_nodes[last_idx]
			_pp_idx[moved_id] = idx
		_pp_ids.pop_back()
		_pp_nodes.pop_back()
	_pp_idx.erase(pid)


func _flush_pending() -> void:
	if not _pending_ep_unreg.empty():
		var ep_keys: Array = _pending_ep_unreg.keys()
		_pending_ep_unreg.clear()
		var i: int = 0
		var cnt: int = ep_keys.size()
		while i < cnt:
			_remove_ep_id(int(ep_keys[i]))
			i += 1
	if not _pending_pp_unreg.empty():
		var pp_keys: Array = _pending_pp_unreg.keys()
		_pending_pp_unreg.clear()
		var j: int = 0
		var pcnt: int = pp_keys.size()
		while j < pcnt:
			_remove_pp_id(int(pp_keys[j]))
			j += 1


func _physics_process(delta: float) -> void:
	if _tree == null or _tree.paused:
		return
	var ep_cnt: int = _ep_nodes.size()
	var pp_cnt: int = _pp_nodes.size()
	if ep_cnt == 0 and pp_cnt == 0:
		return

	var cam_rect: Rect2 = ZoneService.current_zone_max_camera_rect
	var min_x: float = cam_rect.position.x
	var min_y: float = cam_rect.position.y
	var max_x: float = min_x + cam_rect.size.x
	var max_y: float = min_y + cam_rect.size.y

	_iterating = true

	# --- Lane A: Exact-leaf EnemyProjectile ---
	if ep_cnt > 0:
		var enemy_tf: float = EntityService.enemy_time_factor
		var fast_tf: bool = (enemy_tf == 1.0 and not _had_slow_tf)
		if enemy_tf != 1.0:
			_had_slow_tf = true
		var any_anim_dirty: bool = false

		var i: int = 0
		while i < ep_cnt:
			var p = _ep_nodes[i]
			var pid: int = int(_ep_ids[i])
			i += 1
			if not is_instance_valid(p) or not p.is_inside_tree():
				if is_instance_valid(p):
					p._turbo_ep_stepped = false
					p.set_physics_process(true)
				_pending_ep_unreg[pid] = true
				continue
			if not p._turbo_ep_stepped:
				_pending_ep_unreg[pid] = true
				continue

			var sin_m: Vector2 = p.sinusoidal_motion
			if sin_m.x != 0.0 or sin_m.y != 0.0:
				p._turbo_ep_stepped = false
				_pending_ep_unreg[pid] = true
				p.set_physics_process(true)
				p._physics_process(delta)
				continue

			var eff_delta: float = delta
			if not fast_tf:
				var tf: float = enemy_tf
				if tf != 1.0:
					var hb = p._hitbox
					var frm = hb.from if hb != null else null
					if is_instance_valid(frm) and "_is_charmed" in frm and frm._is_charmed:
						tf = 1.0
				if tf != p._animation_time_factor:
					if p._animation_player != null:
						if p._animation_time_factor != 0.0:
							p._animation_player.playback_speed *= tf / p._animation_time_factor
						else:
							p._animation_player.playback_speed = tf
					p._animation_time_factor = tf
				if p._animation_time_factor != 1.0:
					any_anim_dirty = true
				eff_delta = delta * tf

			var pos: Vector2 = p.position + p.velocity * eff_delta
			p.position = pos

			if p.destroy_on_leaving_screen:
				if pos.x < min_x or pos.x > max_x or pos.y < min_y or pos.y > max_y:
					p.stop(true)

		if enemy_tf == 1.0 and not any_anim_dirty:
			_had_slow_tf = false

	# --- Lane B: Exact-leaf PlayerProjectile ---
	if pp_cnt > 0:
		var j: int = 0
		while j < pp_cnt:
			var pp = _pp_nodes[j]
			var ppid: int = int(_pp_ids[j])
			j += 1
			if not is_instance_valid(pp) or not pp.is_inside_tree():
				if is_instance_valid(pp):
					pp._turbo_pp_stepped = false
					pp.set_physics_process(true)
				_pending_pp_unreg[ppid] = true
				continue
			if not pp._turbo_pp_stepped:
				_pending_pp_unreg[ppid] = true
				continue

			var p_sin: Vector2 = pp.sinusoidal_motion
			if p_sin.x != 0.0 or p_sin.y != 0.0:
				pp._turbo_pp_stepped = false
				_pending_pp_unreg[ppid] = true
				pp.set_physics_process(true)
				pp.sinusoidal_time += Vector2(delta * pp.sinusoidal_motion_speed.x, delta * pp.sinusoidal_motion_speed.y)
				pp.sinusoidal_offset = Vector2(sin(pp.sinusoidal_time.x), sin(pp.sinusoidal_time.y)) * p_sin * 0.5
				var sppos: Vector2 = pp.position + (pp.velocity + pp.sinusoidal_offset) * delta
				pp.position = sppos
				if pp._enable_stop_delay:
					pp._elapsed_delay += 60.0 * delta
					if pp._elapsed_delay >= pp.stop_delay:
						pp._return_to_pool()
					continue
				if pp.destroy_on_leaving_screen and (sppos.x < min_x or sppos.x > max_x or sppos.y < min_y or sppos.y > max_y):
					pp.stop(true)
				else:
					pp._physics_process(delta)
				continue

			var ppos: Vector2 = pp.position + pp.velocity * delta
			pp.position = ppos

			if pp.destroy_on_leaving_screen:
				if ppos.x < min_x or ppos.x > max_x or ppos.y < min_y or ppos.y > max_y:
					pp.stop(true)
					if not pp._turbo_pp_stepped:
						continue

			if pp.rotation_speed != 0:
				pp.rotation_degrees += 25

			if pp._time_until_max_range <= 0.0:
				pp.stop()
			pp._time_until_max_range -= delta

	_iterating = false
	_flush_pending()

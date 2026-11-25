extends "res://visual_effects/floating_text/floating_text_manager.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Pre-String Cull & 65ms Damage Aggregator (_turbo_ftm_)
# =============================================================================

const _turbo_ftm_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_ftm_CANVAS_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_damage_canvas.gd")
const _turbo_ftm_WINDOW_MS: int = 65
const _turbo_ftm_STALE_DROP_MS: int = 130
const _turbo_ftm_RING_CAP: int = 256
const _turbo_ftm_RING_MASK: int = 255
const _turbo_ftm_LUT_SIZE: int = 2048
const _turbo_ftm_TELEPORT_SQ: float = 62500.0
const _turbo_ftm_ICON_SCALE: Vector2 = Vector2(0.5, 0.5)
const _turbo_ftm_WHITE: Color = Color(1.0, 1.0, 1.0, 1.0)

const _turbo_ftm_B_UID: int = 0
const _turbo_ftm_B_DMG: int = 1
const _turbo_ftm_B_POS: int = 2
const _turbo_ftm_B_CRIT: int = 3
const _turbo_ftm_B_HIT_TYPE: int = 4
const _turbo_ftm_B_PLAYER_IDX: int = 5
const _turbo_ftm_B_EXPIRE_MS: int = 6
const _turbo_ftm_B_DEAD: int = 7

var _turbo_ftm_state = null
var _turbo_ftm_canvas = null
var _turbo_ftm_font_probed: bool = false
var _turbo_ftm_settings: Dictionary = {}
var _turbo_ftm_has_special_icon: bool = false
var _turbo_ftm_crit_color: Color = Color(1.0, 1.0, 0.0, 1.0)

var _turbo_ftm_sync_idle_frame: int = -1
var _turbo_ftm_flushes_left: int = 8
var _turbo_ftm_bypass_cap: bool = false
var _turbo_ftm_processing: bool = false

var _turbo_ftm_ring: Array = []
var _turbo_ftm_head: int = 0
var _turbo_ftm_tail: int = 0
var _turbo_ftm_count: int = 0
var _turbo_ftm_by_uid: Dictionary = {}
var _turbo_ftm_num_lut: Array = []


func _ready() -> void: # ADDITION
	_turbo_ftm_state = _turbo_ftm_STATE_SCRIPT.HOLDER.get("state")
	if typeof(ProgressData.settings) == TYPE_DICTIONARY:
		_turbo_ftm_settings = ProgressData.settings
	_turbo_ftm_has_special_icon = has_method("get_special_hit_icon")
	if "crit_color" in self:
		_turbo_ftm_crit_color = self.get("crit_color")
	elif _turbo_ftm_settings.has("color_crit"):
		_turbo_ftm_crit_color = Color(_turbo_ftm_settings["color_crit"])

	if _turbo_ftm_ring.empty():
		_turbo_ftm_ring.resize(_turbo_ftm_RING_CAP)
		for i in range(_turbo_ftm_RING_CAP):
			_turbo_ftm_ring[i] = [0, 0, Vector2.ZERO, false, 0, -1, 0, false]

	if _turbo_ftm_num_lut.empty():
		_turbo_ftm_num_lut.resize(_turbo_ftm_LUT_SIZE)
		for n in range(_turbo_ftm_LUT_SIZE):
			_turbo_ftm_num_lut[n] = str(n)

	_turbo_ftm_reset_flush_budget(Engine.get_idle_frames())
	set_process(false)
	_turbo_ftm_processing = false


func _exit_tree() -> void: # ADDITION
	_turbo_ftm_clear_batches()
	if _turbo_ftm_canvas != null and is_instance_valid(_turbo_ftm_canvas):
		_turbo_ftm_canvas.clear_all()
	_turbo_ftm_canvas = null
	_turbo_ftm_font_probed = false
	_turbo_ftm_bypass_cap = false
	_turbo_ftm_processing = false


func _process(_delta: float) -> void: # ADDITION
	if _turbo_ftm_count <= 0:
		set_process(false)
		_turbo_ftm_processing = false
		return

	_turbo_ftm_reset_flush_budget(Engine.get_idle_frames())
	var s = _turbo_ftm_state
	var eff_cap: int = _turbo_ftm_effective_cap(s)
	if not bool(_turbo_ftm_settings.get("damage_display", true)) or (s != null and s.throttle_damage_numbers and eff_cap <= 0):
		_turbo_ftm_clear_batches()
		if _turbo_ftm_canvas != null and is_instance_valid(_turbo_ftm_canvas):
			_turbo_ftm_canvas.clear_all()
		set_process(false)
		_turbo_ftm_processing = false
		return

	_turbo_ftm_flush_due(OS.get_ticks_msec())
	if _turbo_ftm_count <= 0:
		set_process(false)
		_turbo_ftm_processing = false


func _on_unit_took_damage(unit, value: int, knockback_direction: Vector2, is_crit: bool, is_dodge: bool, is_protected: bool, armor_did_something: bool, args: TakeDamageArgs, hit_type: int, is_one_shot: bool) -> void:
	if unit == null or not is_instance_valid(unit):
		return

	if unit is Player or is_one_shot:
		_turbo_ftm_bypass_cap = true
		._on_unit_took_damage(unit, value, knockback_direction, is_crit, is_dodge, is_protected, armor_did_something, args, hit_type, is_one_shot)
		_turbo_ftm_bypass_cap = false
		return

	if not bool(_turbo_ftm_settings.get("damage_display", true)):
		return

	var s = _turbo_ftm_state
	if s == null:
		._on_unit_took_damage(unit, value, knockback_direction, is_crit, is_dodge, is_protected, armor_did_something, args, hit_type, is_one_shot)
		return

	var eff_cap: int = _turbo_ftm_effective_cap(s)
	if s.throttle_damage_numbers and eff_cap <= 0:
		return

	var unit_pos: Vector2 = unit.global_position
	if s.cull_offscreen and s.cam_valid and not s.cam_rect_unit.has_point(unit_pos):
		return

	if value <= 0 or is_dodge or is_protected:
		if s.throttle_damage_numbers and (s.tier >= 4 or _turbo_ftm_active_texts() >= eff_cap):
			return
		._on_unit_took_damage(unit, value, knockback_direction, is_crit, is_dodge, is_protected, armor_did_something, args, hit_type, is_one_shot)
		return

	var uid: int = unit.get_instance_id()
	var has_existing: bool = (not _turbo_ftm_by_uid.empty()) and _turbo_ftm_by_uid.has(uid)
	var should_batch: bool = has_existing or (s.batch_damage_numbers and not (is_crit and s.tier == 0 and _turbo_ftm_active_texts() < (eff_cap >> 1)) and (s.tier >= 1 or _turbo_ftm_active_texts() >= (eff_cap >> 1)))

	if should_batch:
		var idle_frame: int = Engine.get_idle_frames()
		if idle_frame != _turbo_ftm_sync_idle_frame:
			_turbo_ftm_reset_flush_budget(idle_frame)
		var p_idx: int = args.from_player_index if args != null else -1
		var is_dead: bool = unit.dead or unit.current_stats.health <= 0
		_turbo_ftm_record_hit(uid, value, unit_pos, is_crit, hit_type, p_idx, is_dead, has_existing)
		return

	if s.throttle_damage_numbers and _turbo_ftm_active_texts() >= eff_cap:
		return

	._on_unit_took_damage(unit, value, knockback_direction, is_crit, is_dodge, is_protected, armor_did_something, args, hit_type, is_one_shot)



func _turbo_ftm_effective_cap(s) -> int:
	if s == null:
		return 40
	if s.fast_canvas_damage_numbers and s.text_cap <= 0 and not s.stream_potato:
		return 24
	return s.text_cap


func _turbo_ftm_active_texts() -> int:
	var n: int = current_nb_of_texts
	if _turbo_ftm_canvas != null and is_instance_valid(_turbo_ftm_canvas):
		n += _turbo_ftm_canvas.active_count()
	return n


func _turbo_ftm_ensure_canvas() -> void:
	if _turbo_ftm_canvas != null and is_instance_valid(_turbo_ftm_canvas):
		return
	_turbo_ftm_canvas = _turbo_ftm_CANVAS_SCRIPT.new()
	_turbo_ftm_canvas.name = "SaffronDamageCanvas"
	add_child(_turbo_ftm_canvas)
	_turbo_ftm_probe_font()


func _turbo_ftm_find_label(node: Node) -> Label:
	if node is Label:
		return node as Label
	var i: int = 0
	var cnt: int = node.get_child_count()
	while i < cnt:
		var found: Label = _turbo_ftm_find_label(node.get_child(i))
		if found != null:
			return found
		i += 1
	return null


func _turbo_ftm_probe_font() -> void:
	if _turbo_ftm_font_probed or _turbo_ftm_canvas == null:
		return
	_turbo_ftm_font_probed = true
	var scene = get("_floating_text")
	if not (scene is PackedScene):
		scene = get("floating_text_scene")
	if scene is PackedScene:
		var tmp = scene.instance()
		if tmp != null:
			var lbl: Label = _turbo_ftm_find_label(tmp)
			if lbl != null:
				var f: Font = lbl.get("custom_fonts/font")
				if f == null:
					f = lbl.get_font("font")
				if f != null:
					_turbo_ftm_canvas.set_font(f)
			tmp.free()
	if not _turbo_ftm_canvas.has_font() and ResourceLoader.exists("res://resources/fonts/actual/base/font_40_outline_thick.tres"):
		var fallback_font = load("res://resources/fonts/actual/base/font_40_outline_thick.tres")
		if fallback_font is Font:
			_turbo_ftm_canvas.set_font(fallback_font)


func _turbo_ftm_try_canvas(text_str: String, world_pos: Vector2, color: Color, eff_duration: float) -> bool:
	var s = _turbo_ftm_state
	if s == null or not s.fast_canvas_damage_numbers:
		return false
	_turbo_ftm_ensure_canvas()
	if _turbo_ftm_canvas != null and _turbo_ftm_canvas.has_font():
		return _turbo_ftm_canvas.spawn(text_str, world_pos, color, eff_duration)
	return false


func display(value: String, text_pos: Vector2, color: Color = _turbo_ftm_WHITE, icon: Resource = null, p_duration: float = duration, always_display: bool = false, p_direction: Vector2 = direction, need_translate: bool = true, icon_scale: Vector2 = _turbo_ftm_ICON_SCALE, player_index: int = -1, positive_color: bool = false) -> void:
	if always_display or _turbo_ftm_bypass_cap:
		var eff_tr_prio: bool = need_translate and not value.is_valid_integer()
		.display(value, text_pos, color, icon, p_duration, true, p_direction, eff_tr_prio, icon_scale, player_index, positive_color)
		return

	var s = _turbo_ftm_state
	var eff_cap: int = _turbo_ftm_effective_cap(s)
	if s != null:
		if s.throttle_damage_numbers and (eff_cap <= 0 or _turbo_ftm_active_texts() >= eff_cap):
			return
		if s.cull_offscreen and s.cam_valid and not s.cam_rect_unit.has_point(text_pos):
			return

	var eff_duration: float = p_duration
	if s != null:
		if s.tier >= 3:
			eff_duration = p_duration * 0.70
		elif s.tier == 2:
			eff_duration = p_duration * 0.85

	var eff_translate: bool = need_translate and not value.is_valid_integer()
	if icon == null and not eff_translate and (not positive_color or (RunData.get_player_count() <= 1 and _turbo_ftm_settings.has("color_positive"))):
		var eff_col: Color = Color(_turbo_ftm_settings["color_positive"]) if positive_color else color
		if _turbo_ftm_try_canvas(value, text_pos, eff_col, eff_duration):
			return
	if s != null and s.throttle_damage_numbers and (s.tier >= 4 or s.text_cap <= 0):
		return
	.display(value, text_pos, color, icon, eff_duration, false, p_direction, eff_translate, icon_scale, player_index, positive_color)


func _turbo_ftm_reset_flush_budget(idle_frame: int) -> void:
	_turbo_ftm_sync_idle_frame = idle_frame
	var tier: int = _turbo_ftm_state.tier if _turbo_ftm_state != null else 0
	if tier >= 4:
		_turbo_ftm_flushes_left = 3 if (_turbo_ftm_state != null and _turbo_ftm_state.fast_canvas_damage_numbers and not _turbo_ftm_state.stream_potato) else 0
	elif tier == 3:
		_turbo_ftm_flushes_left = 3
	elif tier == 2:
		_turbo_ftm_flushes_left = 5
	else:
		_turbo_ftm_flushes_left = 8


func _turbo_ftm_record_hit(uid: int, value: int, unit_pos: Vector2, is_crit: bool, hit_type: int, player_idx: int, is_dead: bool, has_existing: bool) -> void:
	var s = _turbo_ftm_state
	var cap: int = _turbo_ftm_effective_cap(s)
	var throttle: bool = s.throttle_damage_numbers if s != null else true

	if has_existing:
		var existing: Array = _turbo_ftm_by_uid[uid]
		var prev_pos: Vector2 = existing[_turbo_ftm_B_POS]
		var rdx: float = prev_pos.x - unit_pos.x
		var rdy: float = prev_pos.y - unit_pos.y
		if bool(existing[_turbo_ftm_B_DEAD]) or (rdx * rdx + rdy * rdy) > _turbo_ftm_TELEPORT_SQ:
			var _erased_r = _turbo_ftm_by_uid.erase(uid)
			if int(existing[_turbo_ftm_B_DMG]) > 0:
				if _turbo_ftm_flushes_left > 0 and (not throttle or _turbo_ftm_active_texts() < cap):
					if _turbo_ftm_emit_slot(existing):
						_turbo_ftm_flushes_left -= 1
				existing[_turbo_ftm_B_DMG] = 0
		else:
			existing[_turbo_ftm_B_DMG] = int(existing[_turbo_ftm_B_DMG]) + value
			existing[_turbo_ftm_B_POS] = unit_pos
			if is_crit:
				existing[_turbo_ftm_B_CRIT] = true
			if hit_type != 0:
				existing[_turbo_ftm_B_HIT_TYPE] = hit_type
			if player_idx >= 0:
				existing[_turbo_ftm_B_PLAYER_IDX] = player_idx
			if is_dead:
				existing[_turbo_ftm_B_DEAD] = true
			return

	if _turbo_ftm_count >= _turbo_ftm_RING_CAP:
		var oldest: Array = _turbo_ftm_ring[_turbo_ftm_head]
		var old_uid: int = int(oldest[_turbo_ftm_B_UID])
		if _turbo_ftm_by_uid.has(old_uid) and _turbo_ftm_by_uid[old_uid] == oldest:
			var _erased_o = _turbo_ftm_by_uid.erase(old_uid)
		if int(oldest[_turbo_ftm_B_DMG]) > 0 and _turbo_ftm_flushes_left > 0 and (not throttle or _turbo_ftm_active_texts() < cap):
			if _turbo_ftm_emit_slot(oldest):
				_turbo_ftm_flushes_left -= 1
		oldest[_turbo_ftm_B_UID] = 0
		oldest[_turbo_ftm_B_DMG] = 0
		_turbo_ftm_head = (_turbo_ftm_head + 1) & _turbo_ftm_RING_MASK
		_turbo_ftm_count -= 1

	var now_ms: int = OS.get_ticks_msec()
	var slot: Array = _turbo_ftm_ring[_turbo_ftm_tail]
	slot[_turbo_ftm_B_UID] = uid
	slot[_turbo_ftm_B_DMG] = value
	slot[_turbo_ftm_B_POS] = unit_pos
	slot[_turbo_ftm_B_CRIT] = is_crit
	slot[_turbo_ftm_B_HIT_TYPE] = hit_type
	slot[_turbo_ftm_B_PLAYER_IDX] = player_idx
	slot[_turbo_ftm_B_EXPIRE_MS] = now_ms + _turbo_ftm_WINDOW_MS
	slot[_turbo_ftm_B_DEAD] = is_dead

	_turbo_ftm_by_uid[uid] = slot
	_turbo_ftm_tail = (_turbo_ftm_tail + 1) & _turbo_ftm_RING_MASK
	_turbo_ftm_count += 1

	if not _turbo_ftm_processing:
		set_process(true)
		_turbo_ftm_processing = true


func _turbo_ftm_flush_due(now_ms: int) -> void:
	var s = _turbo_ftm_state
	var cap: int = _turbo_ftm_effective_cap(s)
	var throttle: bool = s.throttle_damage_numbers if s != null else true

	while _turbo_ftm_count > 0:
		var slot: Array = _turbo_ftm_ring[_turbo_ftm_head]
		var dmg: int = int(slot[_turbo_ftm_B_DMG])
		if dmg <= 0:
			slot[_turbo_ftm_B_UID] = 0
			_turbo_ftm_head = (_turbo_ftm_head + 1) & _turbo_ftm_RING_MASK
			_turbo_ftm_count -= 1
			continue

		var expire_ms: int = int(slot[_turbo_ftm_B_EXPIRE_MS])
		if expire_ms > now_ms:
			break

		var can_show: bool = _turbo_ftm_flushes_left > 0 and (not throttle or _turbo_ftm_active_texts() < cap)
		if can_show:
			var uid: int = int(slot[_turbo_ftm_B_UID])
			if _turbo_ftm_by_uid.has(uid) and _turbo_ftm_by_uid[uid] == slot:
				var _e1 = _turbo_ftm_by_uid.erase(uid)
			if _turbo_ftm_emit_slot(slot):
				_turbo_ftm_flushes_left -= 1
			slot[_turbo_ftm_B_UID] = 0
			slot[_turbo_ftm_B_DMG] = 0
			_turbo_ftm_head = (_turbo_ftm_head + 1) & _turbo_ftm_RING_MASK
			_turbo_ftm_count -= 1
		elif now_ms - expire_ms > _turbo_ftm_STALE_DROP_MS:
			var stale_uid: int = int(slot[_turbo_ftm_B_UID])
			if _turbo_ftm_by_uid.has(stale_uid) and _turbo_ftm_by_uid[stale_uid] == slot:
				var _e2 = _turbo_ftm_by_uid.erase(stale_uid)
			slot[_turbo_ftm_B_UID] = 0
			slot[_turbo_ftm_B_DMG] = 0
			_turbo_ftm_head = (_turbo_ftm_head + 1) & _turbo_ftm_RING_MASK
			_turbo_ftm_count -= 1
		else:
			break


func _turbo_ftm_emit_slot(slot: Array) -> bool:
	var dmg: int = int(slot[_turbo_ftm_B_DMG])
	if dmg <= 0:
		return false

	var pos: Vector2 = slot[_turbo_ftm_B_POS]
	if not bool(slot[_turbo_ftm_B_DEAD]):
		var live_obj = instance_from_id(int(slot[_turbo_ftm_B_UID]))
		if live_obj != null and is_instance_valid(live_obj):
			var live_node := live_obj as Node2D
			if live_node != null and live_node.is_inside_tree() and not bool(live_obj.get("dead")):
				var live_pos: Vector2 = live_node.global_position
				var ldx: float = pos.x - live_pos.x
				var ldy: float = pos.y - live_pos.y
				if (ldx * ldx + ldy * ldy) <= _turbo_ftm_TELEPORT_SQ:
					pos = live_pos

	var s = _turbo_ftm_state
	if s != null and s.cull_offscreen and s.cam_valid and not s.cam_rect_unit.has_point(pos):
		return false

	var text: String = _turbo_ftm_num_lut[dmg] if (dmg >= 0 and dmg < _turbo_ftm_LUT_SIZE) else str(dmg)
	var color: Color = _turbo_ftm_crit_color if bool(slot[_turbo_ftm_B_CRIT]) else _turbo_ftm_WHITE
	var hit_type: int = int(slot[_turbo_ftm_B_HIT_TYPE])
	var icon: Resource = null
	if hit_type != 0 and _turbo_ftm_has_special_icon:
		icon = get_special_hit_icon(hit_type)

	var eff_duration: float = duration
	if s != null:
		if s.tier >= 3:
			eff_duration = duration * 0.70
		elif s.tier == 2:
			eff_duration = duration * 0.85

	if icon == null and _turbo_ftm_try_canvas(text, pos, color, eff_duration):
		return true
	.display(text, pos, color, icon, eff_duration, false, direction, false, _turbo_ftm_ICON_SCALE, int(slot[_turbo_ftm_B_PLAYER_IDX]), false)
	return true


func _turbo_ftm_clear_batches() -> void:
	while _turbo_ftm_count > 0:
		var slot: Array = _turbo_ftm_ring[_turbo_ftm_head]
		slot[_turbo_ftm_B_UID] = 0
		slot[_turbo_ftm_B_DMG] = 0
		_turbo_ftm_head = (_turbo_ftm_head + 1) & _turbo_ftm_RING_MASK
		_turbo_ftm_count -= 1
	_turbo_ftm_head = 0
	_turbo_ftm_tail = 0
	_turbo_ftm_by_uid.clear()

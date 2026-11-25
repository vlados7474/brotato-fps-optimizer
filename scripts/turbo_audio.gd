extends Reference
# =============================================================================
# Saffron-Turbo 5.6.1 - Autoload-Safe Category Haas Audio Deduplicator & Drainer
# -----------------------------------------------------------------------------
# Invoked ONLY on frames where SoundManager / SoundManager2D actually have
# queued items (0.000 ms on silent frames):
# - Never drops critical 1D UI/progression sounds (level-up, wave end, shop,
#   combine, boss, win/loss) via "__bypass__" marker.
# - Collapses exact duplicates and random variation families inside 35/45ms
#   category Haas window (without falling back to directory-wide keys).
# - Early offscreen 2D culling at tier 0-1 when queue.size() >= 3.
# =============================================================================

const HAAS_1D_USEC: int = 22000
const HAAS_2D_BASE_USEC: int = 28000
const HAAS_2D_HEAVY_USEC: int = 45000
const HAAS_CAT_BASE_USEC: int = 35000
const HAAS_CAT_HEAVY_USEC: int = 45000
const MAX_DRAIN_PER_FRAME: int = 2
const MAX_DRAIN_HEAVY_PER_FRAME: int = 1
const EARLY_CULL_2D_QUEUE_THRESHOLD: int = 3
const MAX_TRACKED_SOUNDS: int = 512
const BYPASS_KEY: String = "__bypass__"

var _sm1d: Node = null
var _sm2d: Node = null
var _q1: Array = []
var _q2: Array = []
var _avail1: Array = []
var _avail2: Array = []
var _bound_root: Node = null
var _last_1d_usec: Dictionary = {}
var _last_2d_usec: Dictionary = {}
var _last_cat_1d_usec: Dictionary = {}
var _last_cat_2d_usec: Dictionary = {}
var _cat_cache: Dictionary = {}


func tick(root: Viewport, state) -> void:
	if root == null or state == null or not state.dedup_audio:
		return
	if _bound_root != root:
		_bound_root = root
		_sm1d = root.get_node_or_null("SoundManager")
		_sm2d = root.get_node_or_null("SoundManager2D")
		var q1 = _sm1d.get("sounds_to_play") if is_instance_valid(_sm1d) else null
		var q2 = _sm2d.get("sounds_to_play") if is_instance_valid(_sm2d) else null
		var a1 = _sm1d.get("players_available") if is_instance_valid(_sm1d) else null
		var a2 = _sm2d.get("players_available") if is_instance_valid(_sm2d) else null
		_q1 = q1 if typeof(q1) == TYPE_ARRAY else []
		_q2 = q2 if typeof(q2) == TYPE_ARRAY else []
		_avail1 = a1 if typeof(a1) == TYPE_ARRAY else []
		_avail2 = a2 if typeof(a2) == TYPE_ARRAY else []

	var has_q1: bool = not _q1.empty()
	var has_q2: bool = not _q2.empty()
	if not has_q1 and not has_q2:
		return

	var now_usec: int = OS.get_ticks_usec()
	var max_drain: int = MAX_DRAIN_HEAVY_PER_FRAME if state.tier >= 3 else MAX_DRAIN_PER_FRAME
	var cat_win: int = HAAS_CAT_HEAVY_USEC if state.tier >= 2 else HAAS_CAT_BASE_USEC

	if has_q1 and is_instance_valid(_sm1d):
		_process_queue(_sm1d, _q1, _avail1, false, now_usec, HAAS_1D_USEC, cat_win, max_drain, false, Rect2())
	if has_q2 and is_instance_valid(_sm2d):
		var win_2d: int = HAAS_2D_HEAVY_USEC if state.tier >= 3 else HAAS_2D_BASE_USEC
		var cull_2d: bool = state.cull_offscreen and state.cam_valid and (state.tier >= 2 or _q2.size() >= EARLY_CULL_2D_QUEUE_THRESHOLD)
		_process_queue(_sm2d, _q2, _avail2, true, now_usec, win_2d, cat_win, max_drain, cull_2d, state.cam_rect_unit)


func _get_category_key(sound: Resource, sid: int, is_2d: bool) -> String:
	var cache_id: int = (sid << 1) | (1 if is_2d else 0)
	if _cat_cache.has(cache_id):
		return _cat_cache[cache_id]
	if _cat_cache.size() > MAX_TRACKED_SOUNDS:
		_cat_cache.clear()

	var path: String = sound.resource_path
	if path.empty():
		_cat_cache[cache_id] = ""
		return ""

	var lower_path: String = path.to_lower()
	if not is_2d:
		if ("level" in lower_path or "upgrade" in lower_path or "wave" in lower_path
			or "won" in lower_path or "lost" in lower_path or "combine" in lower_path
			or "shop" in lower_path or "button" in lower_path or "click" in lower_path
			or "challenge" in lower_path or "boss" in lower_path or "chest" in lower_path or "crate" in lower_path or "/ui/" in lower_path):
			_cat_cache[cache_id] = BYPASS_KEY
			return BYPASS_KEY

	var key: String = ""
	if "explos" in lower_path or "blast" in lower_path or "boom" in lower_path:
		key = "cat:explosion"
	elif "spawn" in lower_path or "birth" in lower_path:
		key = "cat:spawn"
	else:
		var dir: String = lower_path.get_base_dir()
		var stem: String = lower_path.get_file().get_basename()
		var end_idx: int = stem.length()
		while end_idx > 0:
			var c: int = stem.ord_at(end_idx - 1)
			if (c >= 48 and c <= 57) or c == 95 or c == 45 or c == 32:
				end_idx -= 1
			else:
				break
		if end_idx > 0:
			key = dir + "/" + stem.substr(0, end_idx)
		else:
			key = ""

	_cat_cache[cache_id] = key
	return key


func _process_queue(sm: Node, queue: Array, available: Array, is_2d: bool, now_usec: int, window_usec: int, cat_window_usec: int, max_drain: int, cull_2d: bool, cam_rect: Rect2) -> void:
	var history: Dictionary = _last_2d_usec if is_2d else _last_1d_usec
	if history.size() > MAX_TRACKED_SOUNDS:
		history.clear()
	var cat_history: Dictionary = _last_cat_2d_usec if is_2d else _last_cat_1d_usec
	if cat_history.size() > MAX_TRACKED_SOUNDS:
		cat_history.clear()

	var avail_cnt: int = available.size()
	var play_budget: int = avail_cnt if avail_cnt < max_drain else max_drain
	var q_len: int = queue.size()
	if is_2d and play_budget <= 0:
		queue.clear()
		return

	var write_idx: int = 0
	var read_idx: int = 0
	while read_idx < q_len:
		if is_2d and write_idx >= play_budget:
			break
		var entry = queue[read_idx]
		read_idx += 1
		if typeof(entry) != TYPE_ARRAY or entry.empty():
			continue
		var sound = entry[0]
		if sound == null or not is_instance_valid(sound):
			continue
		if cull_2d and entry.size() >= 4 and typeof(entry[3]) == TYPE_VECTOR2:
			if not cam_rect.has_point(entry[3]):
				continue
		var sid: int = sound.get_instance_id()
		var cat_key: String = _get_category_key(sound, sid, is_2d) if sound is Resource else ""
		if cat_key != BYPASS_KEY:
			if write_idx >= play_budget:
				continue
			var prev_usec: int = int(history.get(sid, -1000000))
			if now_usec - prev_usec < window_usec:
				continue
			if cat_key != "":
				var prev_cat_usec: int = int(cat_history.get(cat_key, -1000000))
				if now_usec - prev_cat_usec < cat_window_usec:
					continue
			history[sid] = now_usec
			if cat_key != "":
				cat_history[cat_key] = now_usec

		if write_idx != read_idx - 1:
			queue[write_idx] = entry
		write_idx += 1

	if write_idx < q_len:
		queue.resize(write_idx)

	if max_drain <= 1 or write_idx <= 1 or available.size() <= 1:
		return
	var extra: int = max_drain - 1
	while extra > 0 and queue.size() > 1 and available.size() > 1:
		var before: int = queue.size()
		sm._process(0.0)
		if queue.size() >= before:
			break
		extra -= 1

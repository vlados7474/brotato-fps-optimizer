extends Node2D
# =============================================================================
# Saffron-Turbo 5.6.1 - 1-Draw-Call Canvas Damage Number Renderer
# -----------------------------------------------------------------------------
# Pre-allocated native Array buffers (avoids Godot 3 PoolRealArray lock/unlock
# overhead), per-font static 0..2047 half-width LUT, oldest-slot eviction on
# overflow, ascent-aligned Y baseline, and single update() per frame.
# =============================================================================

const MAX_SLOTS: int = 128
const DEFAULT_DURATION: float = 0.65
const RISE_PX_PER_SEC: float = 42.0
const HALF_W_LUT_SIZE: int = 2048
const _HALF_W_LUT_BY_FONT: Dictionary = {}
const _HALF_W_STR_BY_FONT: Dictionary = {}

var _font: Font = null
var _font_key: int = 0
var _font_ascent_half: float = 0.0
var _half_w_lut: Array = []
var _half_w_str: Dictionary = {}
var _count: int = 0

var _texts: Array = []
var _colors: Array = []
var _xs: Array = []
var _ys: Array = []
var _vys: Array = []
var _ages: Array = []
var _durs: Array = []


func _init() -> void:
	_ensure_buffers()


func _ready() -> void:
	z_index = 100
	z_as_relative = false
	_ensure_buffers()
	set_process(false)


func _ensure_buffers() -> void:
	if _texts.size() == MAX_SLOTS:
		return
	_texts.resize(MAX_SLOTS)
	_colors.resize(MAX_SLOTS)
	_xs.resize(MAX_SLOTS)
	_ys.resize(MAX_SLOTS)
	_vys.resize(MAX_SLOTS)
	_ages.resize(MAX_SLOTS)
	_durs.resize(MAX_SLOTS)
	for i in range(MAX_SLOTS):
		_texts[i] = ""
		_colors[i] = Color.white
		_xs[i] = 0.0
		_ys[i] = 0.0
		_vys[i] = 0.0
		_ages[i] = 0.0
		_durs[i] = DEFAULT_DURATION


func set_font(font: Font) -> void:
	if font == null:
		_font = null
		_font_key = 0
		_font_ascent_half = 0.0
		_half_w_lut = []
		_half_w_str = {}
		return
	var fid: int = (font.get_instance_id() << 12) | (int(round(font.get_height())) & 0xFFF)
	if _font == font and _font_key == fid and _half_w_lut.size() == HALF_W_LUT_SIZE:
		return
	_font = font
	_font_key = fid
	_font_ascent_half = _font.get_ascent() * 0.5
	if _HALF_W_LUT_BY_FONT.has(fid):
		_half_w_lut = _HALF_W_LUT_BY_FONT[fid]
		_half_w_str = _HALF_W_STR_BY_FONT[fid]
		return
	if _HALF_W_LUT_BY_FONT.size() > 16:
		_HALF_W_LUT_BY_FONT.clear()
		_HALF_W_STR_BY_FONT.clear()
	var lut: Array = []
	lut.resize(HALF_W_LUT_SIZE)
	for i in range(HALF_W_LUT_SIZE):
		lut[i] = 0.0
	_HALF_W_LUT_BY_FONT[fid] = lut
	_half_w_lut = lut
	var smap: Dictionary = {}
	_HALF_W_STR_BY_FONT[fid] = smap
	_half_w_str = smap


func has_font() -> bool:
	return _font != null


func active_count() -> int:
	return _count


func clear_all() -> void:
	if _count > 0:
		_count = 0
		update()
	set_process(false)


func spawn(text_str: String, world_pos: Vector2, color: Color, duration: float = DEFAULT_DURATION) -> bool:
	if _font == null or text_str.empty():
		return false
	if _texts.size() < MAX_SLOTS:
		_ensure_buffers()

	var idx: int = _count
	if idx >= MAX_SLOTS:
		var oldest_idx: int = 0
		var max_age: float = -1.0
		for k in range(MAX_SLOTS):
			var a: float = float(_ages[k])
			if a > max_age:
				max_age = a
				oldest_idx = k
		idx = oldest_idx
	else:
		_count += 1

	var local_pos: Vector2 = world_pos if global_transform == Transform2D.IDENTITY else to_local(world_pos)
	var half_w: float = 0.0
	var slen: int = text_str.length()
	if slen <= 4 and _half_w_lut.size() == HALF_W_LUT_SIZE:
		var c0: int = text_str.ord_at(0)
		if c0 >= 48 and c0 <= 57 and (c0 != 48 or slen == 1) and text_str.is_valid_integer():
			var n: int = int(text_str)
			if n >= 0 and n < HALF_W_LUT_SIZE:
				half_w = float(_half_w_lut[n])
				if half_w <= 0.0:
					half_w = _font.get_string_size(text_str).x * 0.5
					_half_w_lut[n] = half_w
	if half_w <= 0.0:
		var cached_w = _half_w_str.get(text_str)
		if cached_w != null:
			half_w = float(cached_w)
		else:
			half_w = _font.get_string_size(text_str).x * 0.5
			if _half_w_str.size() >= 512:
				_half_w_str.clear()
			_half_w_str[text_str] = half_w

	_texts[idx] = text_str
	_xs[idx] = local_pos.x - half_w
	_ys[idx] = local_pos.y + _font_ascent_half
	_vys[idx] = -RISE_PX_PER_SEC
	_colors[idx] = color
	_ages[idx] = 0.0
	_durs[idx] = duration if duration > 0.05 else DEFAULT_DURATION

	if not is_processing():
		set_process(true)
	return true


func _process(delta: float) -> void:
	if _count <= 0:
		set_process(false)
		return

	var damp: float = max(0.0, 1.0 - 2.2 * delta)
	var i: int = 0
	while i < _count:
		var age: float = float(_ages[i]) + delta
		var dur: float = float(_durs[i])
		if age >= dur:
			_count -= 1
			if i < _count:
				_texts[i] = _texts[_count]
				_xs[i] = _xs[_count]
				_ys[i] = _ys[_count]
				_vys[i] = _vys[_count]
				_colors[i] = _colors[_count]
				_ages[i] = _ages[_count]
				_durs[i] = _durs[_count]
			continue
		var vy: float = float(_vys[i])
		_ages[i] = age
		_ys[i] = float(_ys[i]) + vy * delta
		_vys[i] = vy * damp
		i += 1

	update()
	if _count <= 0:
		set_process(false)


func _draw() -> void:
	if _count <= 0 or _font == null:
		return
	var f: Font = _font
	var cnt: int = _count
	for i in range(cnt):
		var age: float = float(_ages[i])
		var dur: float = float(_durs[i])
		var t: float = age / dur
		var alpha: float = 1.0 if t < 0.55 else clamp(1.0 - (t - 0.55) / 0.45, 0.0, 1.0)
		var base_c: Color = _colors[i]
		var draw_c := Color(base_c.r, base_c.g, base_c.b, base_c.a * alpha)
		var pos := Vector2(float(_xs[i]), float(_ys[i]))
		draw_string(f, pos, String(_texts[i]), draw_c)

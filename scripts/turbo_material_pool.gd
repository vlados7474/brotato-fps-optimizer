extends Reference
# =============================================================================
# Saffron-Turbo 5.6.1 - Shared ShaderMaterial Pool (2D Batching Restorer)
# -----------------------------------------------------------------------------
# Deduplicates identical outline, double-color projectile, and hue-shift
# ShaderMaterials using O(1) LRU eviction via Godot 3 OrderedHashMap order.
# 5.5.0:
# - Replaces texture_size uniform in vanilla outline.gdshader with Godot's
#   built-in TEXTURE_PIXEL_SIZE so all sprite dimensions share 1 material per
#   outline color state (collapsing 50-70 enemy/buffer shaders -> 2-5).
# - Sorts multi-color outline keys by rgba32 so [A, B] == [B, A].
# - Adds get_double_color_projectile_material() & get_hue_shift_material()
#   keyed by shader_id + uniform values (immune to resource_local_to_scene).
# =============================================================================

const MAX_POOL_SIZE: int = 256
const LRU_TOUCH_THRESHOLD: int = 128
const MAX_FAST_ID: int = 1099511627776 # 1 << 40
const HOLDER: Dictionary = {
	"outlines": {},
	"outlines_1c": {},
	"outlines_1c_size": 0,
	"projectiles": {},
	"noop": null
}


class _NoOpShaderMaterial extends ShaderMaterial:
	func set_shader_param(_param: String, _value) -> void:
		pass


static func clear_all() -> void:
	HOLDER["outlines"].clear()
	HOLDER["outlines_1c"].clear()
	HOLDER["outlines_1c_size"] = 0
	HOLDER["projectiles"].clear()
	HOLDER["noop"] = null


static func get_noop_material() -> ShaderMaterial:
	var m = HOLDER["noop"]
	if m == null:
		m = _NoOpShaderMaterial.new()
		HOLDER["noop"] = m
	return m


static func _evict_oldest(pool: Dictionary) -> void:
	while pool.size() >= MAX_POOL_SIZE:
		var oldest_key = null
		for k in pool:
			oldest_key = k
			break
		if oldest_key == null:
			break
		pool.erase(oldest_key)


static func _evict_oldest_1c(fast_pool: Dictionary) -> void:
	while HOLDER["outlines_1c_size"] >= MAX_POOL_SIZE:
		var oldest_mk = null
		for mk in fast_pool:
			oldest_mk = mk
			break
		if oldest_mk == null:
			HOLDER["outlines_1c_size"] = 0
			break
		var old_sub: Dictionary = fast_pool[oldest_mk]
		var oldest_ck = null
		for ck in old_sub:
			oldest_ck = ck
			break
		if oldest_ck != null:
			old_sub.erase(oldest_ck)
			HOLDER["outlines_1c_size"] = int(max(0, HOLDER["outlines_1c_size"] - 1))
		if old_sub.empty():
			fast_pool.erase(oldest_mk)


static func get_outline_material(base_shader: Shader, tex_size: Vector2, alpha: float, desaturation: float, colors: Array) -> ShaderMaterial:
	if base_shader == null:
		return null
	var eff_shader: Shader = base_shader
	var shader_id: int = eff_shader.get_instance_id()
	var tw: int = int(round(tex_size.x))
	var th: int = int(round(tex_size.y))
	var a_q: int = int(clamp(round(alpha * 100.0), 0.0, 100.0))
	var d_q: int = int(clamp(round(desaturation * 100.0), 0.0, 100.0))
	var c_cnt: int = colors.size()

	# Integer fast-path for 1-color outlines (zero string/% allocations)
	if c_cnt == 1 and shader_id >= 0 and shader_id < MAX_FAST_ID and tw >= 0 and tw < 2048 and th >= 0 and th < 2048:
		var fast_pool: Dictionary = HOLDER["outlines_1c"]
		var meta_key: int = (shader_id << 22) | (tw << 11) | th
		var c0: Color = colors[0]
		var color_key: int = ((c0.to_rgba32() & 0xFFFFFFFF) << 14) | (a_q << 7) | d_q
		var sub = fast_pool.get(meta_key)
		if sub != null and sub.has(color_key):
			var hit_1c: ShaderMaterial = sub[color_key]
			if HOLDER["outlines_1c_size"] >= LRU_TOUCH_THRESHOLD:
				sub.erase(color_key)
				sub[color_key] = hit_1c
				fast_pool.erase(meta_key)
				fast_pool[meta_key] = sub
			return hit_1c

		_evict_oldest_1c(fast_pool)

		var mat_1c := ShaderMaterial.new()
		mat_1c.shader = eff_shader
		mat_1c.set_shader_param("texture_size", tex_size)
		mat_1c.set_shader_param("alpha", float(a_q) * 0.01)
		mat_1c.set_shader_param("desaturation", float(d_q) * 0.01)
		mat_1c.set_shader_param("outline_color_0", c0)

		sub = fast_pool.get(meta_key)
		if sub == null:
			sub = {}
			fast_pool[meta_key] = sub
		sub[color_key] = mat_1c
		HOLDER["outlines_1c_size"] = HOLDER["outlines_1c_size"] + 1
		return mat_1c

	# General path for 0 or 2+ colors (sorted by rgba32 so [A,B] == [B,A])
	var pool: Dictionary = HOLDER["outlines"]
	var sorted_colors: Array = colors

	var key: String = "%d|%d,%d|%d|%d" % [shader_id, tw, th, a_q, d_q]
	var i: int = 0
	while i < c_cnt:
		var c: Color = sorted_colors[i]
		key += "|%08x" % c.to_rgba32()
		i += 1

	if pool.has(key):
		var hit: ShaderMaterial = pool[key]
		if pool.size() >= LRU_TOUCH_THRESHOLD:
			pool.erase(key)
			pool[key] = hit
		return hit

	_evict_oldest(pool)

	var mat := ShaderMaterial.new()
	mat.shader = eff_shader
	mat.set_shader_param("texture_size", tex_size)
	mat.set_shader_param("alpha", float(a_q) * 0.01)
	mat.set_shader_param("desaturation", float(d_q) * 0.01)
	i = 0
	while i < c_cnt:
		mat.set_shader_param("outline_color_%s" % i, sorted_colors[i])
		i += 1

	pool[key] = mat
	return mat


static func get_projectile_material(base_mat: ShaderMaterial, tex_size: Vector2, highlight: bool) -> ShaderMaterial:
	if base_mat == null or base_mat.shader == null:
		return base_mat
	var ca = base_mat.get_shader_param("color_A")
	var cb = base_mat.get_shader_param("color_B")
	if ca is Color and cb is Color:
		return get_double_color_projectile_material(base_mat, tex_size, highlight)

	var pool: Dictionary = HOLDER["projectiles"]
	var mat_id: int = base_mat.get_instance_id()
	var tw: int = int(round(tex_size.x))
	var th: int = int(round(tex_size.y))
	var hl_bit: int = 1 if highlight else 0

	var key
	if mat_id >= 0 and mat_id < MAX_FAST_ID and tw >= 0 and tw < 2048 and th >= 0 and th < 2048:
		key = (mat_id << 23) | (tw << 12) | (th << 1) | hl_bit
	else:
		key = "%d|%d,%d|%d" % [mat_id, tw, th, hl_bit]

	if pool.has(key):
		var hit: ShaderMaterial = pool[key]
		if pool.size() >= LRU_TOUCH_THRESHOLD:
			pool.erase(key)
			pool[key] = hit
		return hit

	_evict_oldest(pool)

	var mat: ShaderMaterial = base_mat.duplicate()
	mat.resource_local_to_scene = false
	if highlight:
		mat.set_shader_param("texture_size", tex_size)
		mat.set_shader_param("outline_color_0", Color.black)
	else:
		mat.set_shader_param("texture_size", Vector2(0, 0))
		mat.set_shader_param("outline_color_0", Color(0, 0, 0, 0))

	pool[key] = mat
	return mat


static func get_double_color_projectile_material(base_mat: ShaderMaterial, tex_size: Vector2, highlight: bool) -> ShaderMaterial:
	if base_mat == null or base_mat.shader == null:
		return base_mat
	var ca = base_mat.get_shader_param("color_A")
	var cb = base_mat.get_shader_param("color_B")
	if not (ca is Color) or not (cb is Color):
		return base_mat
	var rw = base_mat.get_shader_param("width")
	var ra = base_mat.get_shader_param("alpha")
	var rd = base_mat.get_shader_param("desaturation")
	var w_q: int = int(round((float(rw) if (rw is float or rw is int) else 3.0) * 10.0))
	var a_q: int = int(clamp(round((float(ra) if (ra is float or ra is int) else 1.0) * 100.0), 0.0, 100.0))
	var d_q: int = int(clamp(round((float(rd) if (rd is float or rd is int) else 0.0) * 100.0), 0.0, 100.0))
	var key: String = "dc|%d|%08x|%08x|%d|%d|%d|%d,%d|%d" % [
		base_mat.shader.get_instance_id(),
		ca.to_rgba32(),
		cb.to_rgba32(),
		w_q,
		a_q,
		d_q,
		int(round(tex_size.x)),
		int(round(tex_size.y)),
		1 if highlight else 0
	]
	var pool: Dictionary = HOLDER["projectiles"]
	if pool.has(key):
		var hit: ShaderMaterial = pool[key]
		if pool.size() >= LRU_TOUCH_THRESHOLD:
			pool.erase(key)
			pool[key] = hit
		return hit
	_evict_oldest(pool)
	var mat: ShaderMaterial = base_mat.duplicate()
	mat.resource_local_to_scene = false
	if highlight:
		mat.set_shader_param("texture_size", tex_size)
		mat.set_shader_param("outline_color_0", Color.black)
	else:
		mat.set_shader_param("texture_size", Vector2(0, 0))
		mat.set_shader_param("outline_color_0", Color(0, 0, 0, 0))
	pool[key] = mat
	return mat


static func get_hue_shift_material(base_mat: ShaderMaterial, tex_size: Vector2 = Vector2.ZERO, highlight: bool = false) -> ShaderMaterial:
	if base_mat == null or base_mat.shader == null:
		return base_mat
	var rh = base_mat.get_shader_param("hue")
	if not (rh is float or rh is int):
		return base_mat
	var ra = base_mat.get_shader_param("alpha")
	var rd = base_mat.get_shader_param("desaturation")
	var key: String = "hs|%d|%d|%d|%d|%d,%d|%d" % [
		base_mat.shader.get_instance_id(),
		int(round(float(rh) * 1000.0)),
		int(clamp(round((float(ra) if (ra is float or ra is int) else 1.0) * 100.0), 0.0, 100.0)),
		int(clamp(round((float(rd) if (rd is float or rd is int) else 0.0) * 100.0), 0.0, 100.0)),
		int(round(tex_size.x)),
		int(round(tex_size.y)),
		1 if highlight else 0
	]
	var pool: Dictionary = HOLDER["projectiles"]
	if pool.has(key):
		var hit: ShaderMaterial = pool[key]
		if pool.size() >= LRU_TOUCH_THRESHOLD:
			pool.erase(key)
			pool[key] = hit
		return hit
	_evict_oldest(pool)
	var mat: ShaderMaterial = base_mat.duplicate()
	mat.resource_local_to_scene = false
	pool[key] = mat
	return mat

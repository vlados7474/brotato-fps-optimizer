extends Reference
# =============================================================================
# Saffron-Turbo 5.6.1 - Baked Enemy Projectile Outline Texture Cache & Normalizer
# -----------------------------------------------------------------------------
# Pre-bakes standard enemy projectile textures with shader_outline_double_color
# (color_A / color_B tinting + 3px black outline) into cached ImageTextures
# using fast PoolByteArray buffer reads and a shared unshaded CanvasItemMaterial.
# 5.5.0:
# - Keys cache by base_mat.shader.get_instance_id() (immune to local_to_scene).
# - Adds normalize_projectile() covering AcidProjectile, BulletHellProjectile,
#   charmed hue_shift projectiles, and animated pillar/slash projectiles.
# =============================================================================

const MAX_CACHE_SIZE: int = 256
const LRU_TOUCH_THRESHOLD: int = 128
const MAX_BAKE_DIM: int = 128
const HOLDER: Dictionary = {
	"cache": {},
	"failed": {},
	"unshaded_mat": null
}

# 13 neighbor offsets matching vanilla shader_outline_double_color.gdshader
const _OUTLINE_OFFSETS: Array = [
	Vector2(0.0, 1.0),
	Vector2(1.0, 0.0),
	Vector2(0.0, -1.0),
	Vector2(-1.0, 1.0),
	Vector2(-1.0, 0.5),
	Vector2(-0.5, 1.0),
	Vector2(0.5, 1.0),
	Vector2(-1.0, -1.0),
	Vector2(-1.0, -0.5),
	Vector2(-0.5, -1.0),
	Vector2(1.0, -1.0),
	Vector2(1.0, -0.5),
	Vector2(0.5, -1.0)
]


static func clear_all() -> void:
	HOLDER["cache"].clear()
	HOLDER["failed"].clear()
	HOLDER["unshaded_mat"] = null


static func get_unshaded_material() -> CanvasItemMaterial:
	var m = HOLDER["unshaded_mat"]
	if m == null:
		m = CanvasItemMaterial.new()
		m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		HOLDER["unshaded_mat"] = m
	return m


static func _evict_oldest(pool: Dictionary) -> void:
	while pool.size() >= MAX_CACHE_SIZE:
		var oldest_key = null
		for k in pool:
			oldest_key = k
			break
		if oldest_key == null:
			break
		pool.erase(oldest_key)


static func normalize_projectile(proj: Node, mat_pool, use_baker: bool, use_pool: bool) -> void:
	if not is_instance_valid(proj) or (not use_baker and not use_pool):
		return
	var sp = proj.get("_sprite") as Sprite
	if sp == null or sp.texture == null:
		return
	if proj is CanvasItem and proj.material is ShaderMaterial and not sp.use_parent_material:
		if proj.material.get_shader_param("color_A") is Color:
			proj.material = null
	var sm: ShaderMaterial = sp.material as ShaderMaterial
	if sm == null or sm.shader == null:
		return
	var hl: bool = bool(ProgressData.settings.projectile_highlighting)
	if sm.get_shader_param("hue") != null:
		if use_pool and mat_pool != null:
			sp.material = mat_pool.get_hue_shift_material(sm, sp.texture.get_size(), hl)
		return
	var ca = sm.get_shader_param("color_A")
	var cb = sm.get_shader_param("color_B")
	if not (ca is Color) or not (cb is Color):
		return
	var ap = proj.get("_animation_player")
	var is_anim: bool = (sp.hframes > 1 or sp.vframes > 1 or sp.region_enabled or (ap is AnimationPlayer and (ap.assigned_animation != "" or ap.get_animation_list().size() > 0)))
	if not ("_has_custom_material" in proj):
		var oc0 = sm.get_shader_param("outline_color_0")
		hl = (oc0 is Color and oc0.a > 0.0)
	if use_baker and not is_anim and ("_turbo_ep_baked_active" in proj):
		var baked: ImageTexture = get_baked_texture(sp.texture, sm, hl)
		if baked != null:
			if not proj._turbo_ep_baked_active:
				proj._turbo_ep_orig_texture = sp.texture
			proj._turbo_ep_baked_texture = baked
			proj._turbo_ep_baked_active = true
			sp.texture = baked
			sp.material = get_unshaded_material()
			return
	if use_pool and mat_pool != null:
		sp.material = mat_pool.get_double_color_projectile_material(sm, sp.texture.get_size(), hl)


static func get_baked_texture(tex: Texture, base_mat: ShaderMaterial, highlight: bool) -> ImageTexture:
	if tex == null or base_mat == null or base_mat.shader == null:
		return null

	var raw_a = base_mat.get_shader_param("color_A")
	var raw_b = base_mat.get_shader_param("color_B")
	if not (raw_a is Color) or not (raw_b is Color):
		return null

	var oc0 = base_mat.get_shader_param("outline_color_0")
	if highlight and oc0 is Color and oc0.a > 0.0 and (oc0.r > 0.01 or oc0.g > 0.01 or oc0.b > 0.01):
		return null
	var oc1 = base_mat.get_shader_param("outline_color_1")
	if oc1 is Color and oc1.a > 0.0:
		return null
	var oc2 = base_mat.get_shader_param("outline_color_2")
	if oc2 is Color and oc2.a > 0.0:
		return null
	var oc3 = base_mat.get_shader_param("outline_color_3")
	if oc3 is Color and oc3.a > 0.0:
		return null

	var color_a: Color = raw_a
	var color_b: Color = raw_b
	var raw_w = base_mat.get_shader_param("width")
	var outline_w: float = float(raw_w) if (raw_w is float or raw_w is int) else 3.0
	var raw_alpha = base_mat.get_shader_param("alpha")
	var mat_alpha: float = float(raw_alpha) if (raw_alpha is float or raw_alpha is int) else 1.0
	var raw_desat = base_mat.get_shader_param("desaturation")
	var desat: float = float(raw_desat) if (raw_desat is float or raw_desat is int) else 0.0

	var key: String = "%d|%d|%d|%08x|%08x|%d|%d|%d" % [
		tex.get_instance_id(),
		base_mat.shader.get_instance_id(),
		1 if highlight else 0,
		color_a.to_rgba32(),
		color_b.to_rgba32(),
		int(round(outline_w * 10.0)),
		int(round(mat_alpha * 100.0)),
		int(round(desat * 100.0))
	]

	var cache: Dictionary = HOLDER["cache"]
	if cache.has(key):
		var hit: ImageTexture = cache[key]
		if cache.size() >= LRU_TOUCH_THRESHOLD:
			cache.erase(key)
			cache[key] = hit
		return hit

	var failed: Dictionary = HOLDER["failed"]
	if failed.has(key):
		return null

	var baked: ImageTexture = _bake_texture(tex, base_mat, highlight, color_a, color_b, outline_w, mat_alpha, desat)
	if baked == null:
		_evict_oldest(failed)
		failed[key] = true
		return null

	_evict_oldest(cache)
	cache[key] = baked
	return baked


static func _bake_texture(tex: Texture, base_mat: ShaderMaterial, highlight: bool, color_a: Color, color_b: Color, outline_w: float, mat_alpha: float, desat: float) -> ImageTexture:
	if not (tex is StreamTexture or tex is ImageTexture):
		return null

	var src_img: Image = tex.get_data()
	if src_img == null:
		return null

	var w: int = src_img.get_width()
	var h: int = src_img.get_height()
	if w <= 0 or h <= 0 or w > MAX_BAKE_DIM or h > MAX_BAKE_DIM:
		return null

	var img: Image = src_img.duplicate()
	if img.is_compressed():
		if img.decompress() != OK:
			return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)

	var src_bytes: PoolByteArray = img.get_data()
	var total_bytes: int = w * h * 4
	if src_bytes.size() < total_bytes:
		return null

	var do_outline: bool = highlight and outline_w > 0.0
	var offsets_x: Array = []
	var offsets_y: Array = []
	var offset_cnt: int = 0
	if do_outline:
		offset_cnt = _OUTLINE_OFFSETS.size()
		var oi: int = 0
		while oi < offset_cnt:
			var ov: Vector2 = _OUTLINE_OFFSETS[oi]
			offsets_x.push_back(int(round(ov.x * outline_w)))
			offsets_y.push_back(int(round(ov.y * outline_w)))
			oi += 1

	var out_bytes: PoolByteArray = PoolByteArray()
	out_bytes.resize(total_bytes)

	var inv255: float = 1.0 / 255.0
	var max_x: int = w - 1
	var max_y: int = h - 1
	var ca_r: float = color_a.r
	var ca_g: float = color_a.g
	var ca_b: float = color_a.b
	var cb_r: float = color_b.r
	var cb_g: float = color_b.g
	var cb_b: float = color_b.b

	var y: int = 0
	while y < h:
		var row_off: int = y * w
		var x: int = 0
		while x < w:
			var idx: int = (row_off + x) * 4
			var sr: float = float(src_bytes[idx]) * inv255
			var sg: float = float(src_bytes[idx + 1]) * inv255
			var sb: float = float(src_bytes[idx + 2]) * inv255
			var sa: float = float(src_bytes[idx + 3]) * inv255

			var out_r: float = ca_r * (1.0 - sr) + cb_r * sr
			var out_g: float = ca_g * (1.0 - sg) + cb_g * sg
			var out_b: float = ca_b * (1.0 - sb) + cb_b * sb
			var out_a: float = sa

			if do_outline:
				var nb_a: float = out_a
				if nb_a < 1.0:
					var k: int = 0
					while k < offset_cnt:
						var nx: int = x + int(offsets_x[k])
						if nx < 0:
							nx = 0
						elif nx > max_x:
							nx = max_x
						var ny: int = y + int(offsets_y[k])
						if ny < 0:
							ny = 0
						elif ny > max_y:
							ny = max_y
						var na_byte: int = src_bytes[(ny * w + nx) * 4 + 3]
						if na_byte > 0:
							nb_a += float(na_byte) * inv255
							if nb_a >= 1.0:
								nb_a = 1.0
								break
						k += 1
				out_r *= out_a
				out_g *= out_a
				out_b *= out_a
				out_a = nb_a

			if desat > 0.0:
				var gray: float = out_r * 0.299 + out_g * 0.587 + out_b * 0.114
				out_r = lerp(out_r, gray, desat)
				out_g = lerp(out_g, gray, desat)
				out_b = lerp(out_b, gray, desat)

			out_a *= mat_alpha
			out_bytes[idx] = int(clamp(round(out_r * 255.0), 0.0, 255.0))
			out_bytes[idx + 1] = int(clamp(round(out_g * 255.0), 0.0, 255.0))
			out_bytes[idx + 2] = int(clamp(round(out_b * 255.0), 0.0, 255.0))
			out_bytes[idx + 3] = int(clamp(round(out_a * 255.0), 0.0, 255.0))
			x += 1
		y += 1

	var out_img := Image.new()
	out_img.create_from_data(w, h, false, Image.FORMAT_RGBA8, out_bytes)
	var baked := ImageTexture.new()
	baked.create_from_image(out_img, tex.flags)
	return baked

extends "res://projectiles/bullet_enemy/enemy_projectile.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Baked Outline Texture & Pooled Material (_turbo_ep_)
# -----------------------------------------------------------------------------
# Uses TurboProjectileBaker when optimize_projectiles is enabled and no custom
# material is set: assigns pre-baked ImageTexture with a shared unshaded
# CanvasItemMaterial (1 texture tap + unshaded parity + 2D batching). Safely
# restores original texture only if still holding our baked texture.
# =============================================================================

const _turbo_ep_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_ep_MAT_POOL = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_material_pool.gd")
const _turbo_ep_BAKER = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_projectile_baker.gd")

var _turbo_ep_orig_texture: Texture = null
var _turbo_ep_baked_texture: Texture = null
var _turbo_ep_baked_active: bool = false
var _turbo_ep_stepped: bool = false


func _exit_tree() -> void: # ADDITION
	if _turbo_ep_stepped:
		_turbo_ep_unregister_stepper()


func _turbo_ep_register_stepper(s) -> void:
	if s == null or not s.optimize_projectiles or s.stepper == null:
		_turbo_ep_unregister_stepper()
		set_physics_process(true)
		return
	if get_script() != s.stepper.ep_leaf_script or _enable_stop_delay or sinusoidal_motion != Vector2.ZERO:
		_turbo_ep_unregister_stepper()
		set_physics_process(true)
		return
	if not _turbo_ep_stepped:
		_turbo_ep_stepped = true
		set_physics_process(false)
		s.stepper.register_enemy(self)


func _turbo_ep_unregister_stepper() -> void:
	if not _turbo_ep_stepped:
		return
	_turbo_ep_stepped = false
	set_physics_process(true)
	var s = _turbo_ep_STATE_SCRIPT.HOLDER.get("state")
	if s != null and s.stepper != null:
		s.stepper.unregister_enemy(self)


func _turbo_ep_restore_orig_texture() -> void:
	if _turbo_ep_baked_active:
		if _sprite != null and _turbo_ep_orig_texture != null and _sprite.texture == _turbo_ep_baked_texture:
			_sprite.texture = _turbo_ep_orig_texture
		_turbo_ep_orig_texture = null
		_turbo_ep_baked_texture = null
		_turbo_ep_baked_active = false


func shoot() -> void:
	_turbo_ep_restore_orig_texture()

	var s = _turbo_ep_STATE_SCRIPT.HOLDER.get("state")
	var use_baker: bool = (s == null or s.optimize_projectiles)
	var use_pool: bool = (s == null or s.pool_outline_materials)

	if (not use_baker and not use_pool) or _has_custom_material or _sprite == null:
		.shoot()
		_turbo_ep_register_stepper(s)
		return

	var sink: ShaderMaterial = _turbo_ep_MAT_POOL.get_noop_material()
	_has_custom_material = true
	_sprite.material = sink
	.shoot()

	if _sprite.material != sink:
		_turbo_ep_register_stepper(s)
		return

	_has_custom_material = false
	var raw_mat = Utils.projectile_outline_petrol_shadermat if evolution_puddle_type == EVOLUTION_PUDDLE_PETROL else Utils.projectile_outline_shadermat
	var base_mat: ShaderMaterial = raw_mat as ShaderMaterial
	if base_mat == null or _sprite.texture == null:
		_sprite.material = raw_mat
		_turbo_ep_register_stepper(s)
		return

	var highlight: bool = bool(ProgressData.settings.projectile_highlighting)

	var is_anim: bool = (_sprite.hframes > 1 or _sprite.vframes > 1 or _sprite.region_enabled or (_animation_player != null and (_animation_player.assigned_animation != "" or _animation_player.get_animation_list().size() > 0)))
	if use_baker and not is_anim:
		var orig_tex: Texture = _sprite.texture
		var baked: ImageTexture = _turbo_ep_BAKER.get_baked_texture(orig_tex, base_mat, highlight)
		if baked != null:
			_turbo_ep_orig_texture = orig_tex
			_turbo_ep_baked_texture = baked
			_turbo_ep_baked_active = true
			_sprite.texture = baked
			_sprite.material = _turbo_ep_BAKER.get_unshaded_material()
			_turbo_ep_register_stepper(s)
			return

	if use_pool:
		var pooled: ShaderMaterial = _turbo_ep_MAT_POOL.get_projectile_material(
			base_mat,
			_sprite.texture.get_size(),
			highlight
		)
		if pooled != null and pooled != base_mat:
			_sprite.material = pooled
			_turbo_ep_register_stepper(s)
			return

	_sprite.material = base_mat
	if highlight:
		base_mat.set_shader_param("texture_size", _sprite.texture.get_size())
		base_mat.set_shader_param("outline_color_0", Color.black)
	else:
		base_mat.set_shader_param("texture_size", Vector2(0, 0))
		base_mat.set_shader_param("outline_color_0", Color(0, 0, 0, 0))
	_turbo_ep_register_stepper(s)


func set_sprite_material(material: ShaderMaterial) -> void:
	_turbo_ep_restore_orig_texture()
	var s = _turbo_ep_STATE_SCRIPT.HOLDER.get("state")
	var use_mat = material
	if (s == null or s.pool_outline_materials) and material != null and _sprite != null and _sprite.texture != null:
		use_mat = _turbo_ep_MAT_POOL.get_hue_shift_material(material, _sprite.texture.get_size(), bool(ProgressData.settings.projectile_highlighting))
	.set_sprite_material(use_mat)


func stop(from_screen_border: bool = false) -> void:
	if _turbo_ep_stepped:
		_turbo_ep_unregister_stepper()
	.stop(from_screen_border)


func _return_to_pool() -> void:
	_turbo_ep_unregister_stepper()
	_turbo_ep_restore_orig_texture()
	if _animation_time_factor == 0.0:
		_animation_time_factor = 1.0
		if _animation_player != null:
			_animation_player.playback_speed = 1.0
	._return_to_pool()

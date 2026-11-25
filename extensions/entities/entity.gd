extends "res://entities/entity.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Pooled Outline ShaderMaterial & Shadow Z-Bucketing (_turbo_ent_)
# -----------------------------------------------------------------------------
# Replaces per-entity ShaderMaterial.duplicate() in _set_outlines() with a
# shared pooled ShaderMaterial so Godot 3.x GLES2/GLES3 2D batching merges
# identical enemy sprites, and optionally Z-buckets Shadow sprites at z=-10.
# =============================================================================

const _turbo_ent_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_ent_MAT_POOL = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_material_pool.gd")


func _ready() -> void: # ADDITION
	_turbo_ent_apply_shadow_z_bucket()


func _turbo_ent_apply_shadow_z_bucket() -> void:
	var s = _turbo_ent_STATE_SCRIPT.HOLDER.get("state")
	if s == null or not s.z_bucket_shadows_gold:
		return
	var shadow: Node = get_node_or_null("Shadow")
	if shadow != null and shadow is Node2D:
		shadow.z_as_relative = false
		shadow.z_index = -10


func _turbo_ent_apply_material(mat: ShaderMaterial) -> void:
	if sprite == null:
		return
	var fm = get("flash_mat")
	var fsm = get("flash_shield_mat")
	var handled: bool = false
	if fm != null and sprite.material == fm:
		set("_non_flash_material", mat)
		handled = true
	if fsm != null and sprite.material == fsm:
		set("_non_flash_shield_material", mat)
		handled = true
	if handled:
		return
	if sprite.material != mat:
		sprite.material = mat


func _set_outlines(alpha: float = 1.0, desaturation: float = 0.0) -> void:
	var s = _turbo_ent_STATE_SCRIPT.HOLDER.get("state")
	if s != null and not s.pool_outline_materials:
		._set_outlines(alpha, desaturation)
		return
	if not _outline_colors:
		_turbo_ent_apply_material(null)
		return
	if sprite == null or sprite.texture == null or outline_material == null or outline_material.shader == null:
		return

	var eff_alpha: float = alpha if alpha < 1.0 else _current_material_alpha
	if alpha < 1.0:
		_current_material_alpha = alpha
	var eff_desat: float = desaturation if desaturation > 0.0 else _current_material_desaturation
	if desaturation > 0.0:
		_current_material_desaturation = desaturation

	var pooled: ShaderMaterial = _turbo_ent_MAT_POOL.get_outline_material(
		outline_material.shader,
		sprite.texture.get_size(),
		eff_alpha,
		eff_desat,
		_outline_colors
	)
	if pooled != null:
		_turbo_ent_apply_material(pooled)
	else:
		._set_outlines(alpha, desaturation)

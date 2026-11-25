extends "res://items/global/inventory_element.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Shared StyleBox Pool for InventoryElement (_turbo_ie_)
# -----------------------------------------------------------------------------
# Includes live tier color from ItemService.get_color_from_tier(tier) in key
# (respects accessibility color changes), caps pool size at 128, and updates
# _frame_panel directly via ItemService.change_panel_from_tier().
# =============================================================================

const _turbo_ie_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_ie_STYLE_POOL: Dictionary = {}
const _turbo_ie_MAX_POOL: int = 128

var _turbo_base_normal_sb: StyleBox = null


func update_background_color(p_color: int = -1) -> void:
	var s = _turbo_ie_STATE_SCRIPT.HOLDER.get("state")
	if s != null and not s.optimize_hud_inventory:
		.update_background_color(p_color)
		return
	if item == null:
		return
	if item is ItemEntity:
		.update_background_color(p_color)
		return

	if _turbo_base_normal_sb == null:
		_turbo_base_normal_sb = get_stylebox("normal")

	var tier: int = p_color if p_color != -1 else item.tier
	var tier_rgba: int = ItemService.get_color_from_tier(tier).to_rgba32()
	var key: String = "%d|%d|%08x|%08x|%d" % [
		_turbo_base_normal_sb.get_instance_id(),
		tier,
		tier_rgba,
		background_modulate.to_rgba32(),
		int(round(background_transparency * 1000.0))
	]

	var pooled_sb: StyleBox = _turbo_ie_STYLE_POOL.get(key, null)
	if pooled_sb != null:
		if _frame_panel != null:
			ItemService.change_panel_from_tier(_frame_panel, tier)
		add_stylebox_override("normal", pooled_sb)
		return

	var stylebox_color: StyleBox = _turbo_base_normal_sb.duplicate()
	ItemService.change_inventory_element_stylebox_from_tier(stylebox_color, tier, 0.25, _frame_panel)
	stylebox_color.bg_color = lerp(
		stylebox_color.bg_color,
		Color(background_modulate.r, background_modulate.g, background_modulate.b),
		background_modulate.a
	)
	stylebox_color.bg_color.a = background_transparency
	if _turbo_ie_STYLE_POOL.size() >= _turbo_ie_MAX_POOL:
		_turbo_ie_STYLE_POOL.clear()
	_turbo_ie_STYLE_POOL[key] = stylebox_color
	add_stylebox_override("normal", stylebox_color)

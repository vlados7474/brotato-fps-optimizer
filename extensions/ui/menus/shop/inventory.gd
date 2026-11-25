extends "res://ui/menus/shop/inventory.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Batched Inventory set_elements (O(N^2) -> O(N)) (_turbo_inv_)
# =============================================================================

const _turbo_inv_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")

var _turbo_batching: bool = false
var _turbo_batch_dirty: bool = false


func set_elements(elements: Array, reverse_order: bool = false, replace: bool = true, prioritize_gameplay_elements: bool = false, animated_entrance: bool = false) -> void:
	var s = _turbo_inv_STATE_SCRIPT.HOLDER.get("state")
	if s != null and not s.optimize_hud_inventory:
		.set_elements(elements, reverse_order, replace, prioritize_gameplay_elements, animated_entrance)
		return
	var was_batching: bool = _turbo_batching
	_turbo_batching = true
	if not was_batching:
		_turbo_batch_dirty = false
	.set_elements(elements, reverse_order, replace, prioritize_gameplay_elements, animated_entrance)
	_turbo_batching = was_batching
	if not _turbo_batching and _turbo_batch_dirty:
		_turbo_batch_dirty = false
		emit_signal("elements_changed")
		queue_set_focus_neighbours()


func clear_elements() -> void:
	if not _turbo_batching:
		.clear_elements()
		return
	order_of_addition.clear()
	for n in get_children():
		remove_child(n)
		n.queue_free()
	_turbo_batch_dirty = true


func _spawn_element(element: Resource, _display_banned: float = 0, animated_entrance = false):
	if not _turbo_batching:
		return ._spawn_element(element, _display_banned, animated_entrance)
	var instance = element_scene.instance()
	instance.call_deferred("set_font", element_font)
	instance.player_index = player_index
	instance.display_banned = _display_banned
	instance.display_recently_mutated = display_recently_mutated_icon
	instance.background_transparency = item_background_transparency
	instance.background_modulate = item_background_modulate

	if element_size != Utils.BASE_INVENTORY_ELEMENT_SIZE:
		instance.set_element_size(element_size)
		if element_size.x <= 80 and element_size.y <= 80:
			instance.call_deferred("set_font", element_font_small)

	add_child(instance)
	_update_mouse_focus_for_control(instance)
	instance.set_element(element)

	if silhouette_locked_items:
		instance.silouhette_if_hidden_in_codex()

	if _reversed_order:
		move_child(instance, 0)

	connect_signals(instance)
	order_of_addition.append(instance)
	if animated_entrance:
		UIService._entrance_animation(instance)

	_turbo_batch_dirty = true
	return instance


func add_special_element(p_icon: Texture, p_is_random: bool = false, p_alpha: float = 1, p_item: Resource = null, sort_inventory: bool = true, animated_entrance = false) -> void:
	if not _turbo_batching:
		.add_special_element(p_icon, p_is_random, p_alpha, p_item, sort_inventory, animated_entrance)
		return
	var instance = element_scene.instance()
	instance.display_banned = 0
	instance.player_index = player_index
	add_child(instance)
	_update_mouse_focus_for_control(instance)
	instance.is_special = true
	instance.is_random = p_is_random
	instance.modulate.a = p_alpha
	instance.set_icon(p_icon)
	instance.item = p_item
	instance.set_element_size(element_size)
	if animated_entrance:
		UIService._entrance_animation(instance)
	connect_signals(instance)
	if sort_inventory:
		emit_signal("need_to_sort_inventory")
	_turbo_batch_dirty = true


func queue_set_focus_neighbours() -> void:
	if _turbo_batching:
		_turbo_batch_dirty = true
		return
	.queue_set_focus_neighbours()

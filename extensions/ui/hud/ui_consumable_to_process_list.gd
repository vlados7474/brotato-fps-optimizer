extends "res://ui/hud/ui_consumable_to_process_list.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Bounded HUD Consumable Icon Nodes (_turbo_cpl_)
# =============================================================================

const _turbo_cpl_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")

var _turbo_overflow_by_icon: Dictionary = {}


func _exit_tree() -> void: # ADDITION
	_turbo_overflow_by_icon.clear()


func add_element(item_data: ItemParentData) -> void:
	if _elements.empty() and get_child_count() == 0 and not _turbo_overflow_by_icon.empty():
		_turbo_overflow_by_icon.clear()

	var s = _turbo_cpl_STATE_SCRIPT.HOLDER.get("state")
	if s != null and not s.optimize_hud_inventory and _turbo_overflow_by_icon.empty():
		.add_element(item_data)
		return

	var icon: Resource = item_data.icon
	var similar_icons: Array = _get_all_similar_elements(icon)
	var overflow: Array = _turbo_overflow_by_icon.get(icon, [])
	var total_count: int = similar_icons.size() + overflow.size() + 1

	if total_count > UIItemList.MAX_SIMILAR_ICONS + 1 and not similar_icons.empty():
		if not _turbo_overflow_by_icon.has(icon):
			_turbo_overflow_by_icon[icon] = []
		_turbo_overflow_by_icon[icon].push_back(item_data)
		_elements.push_back(item_data)
		similar_icons[similar_icons.size() - 1].set_count(total_count)
		return

	if total_count > UIItemList.MAX_SIMILAR_ICONS:
		if total_count == UIItemList.MAX_SIMILAR_ICONS + 1:
			for element in similar_icons:
				element.hide()
		else:
			var hide_idx: int = int(min(total_count - 2, similar_icons.size() - 1))
			if hide_idx >= 0:
				similar_icons[hide_idx].hide()

	var node = element_scene.instance()
	node.set_item_data(item_data)
	node.set_count(total_count)
	_elements.push_back(item_data)
	_add_ui_node(node)


func remove_element(item_data: ItemParentData) -> void:
	var icon: Resource = item_data.icon
	var similar_icons: Array = _get_all_similar_elements(icon)
	var overflow: Array = _turbo_overflow_by_icon.get(icon, [])

	if not overflow.empty():
		var ov_idx: int = overflow.find(item_data)
		if ov_idx != -1:
			overflow.remove(ov_idx)
			_elements.erase(item_data)
		else:
			var target_node = null
			for node in similar_icons:
				if node.item_data == item_data:
					target_node = node
					break
			if target_node != null:
				var replacement = overflow[0]
				overflow.remove(0)
				target_node.set_item_data(replacement)
				_elements.erase(item_data)
			else:
				_elements.erase(item_data)
				return
		if overflow.empty():
			_turbo_overflow_by_icon.erase(icon)
		var total_count: int = similar_icons.size() + overflow.size()
		if not similar_icons.empty():
			similar_icons[similar_icons.size() - 1].set_count(total_count)
		return

	var count: int = similar_icons.size() - 1
	if count >= UIItemList.MAX_SIMILAR_ICONS:
		if count == UIItemList.MAX_SIMILAR_ICONS:
			for element in similar_icons:
				element.show()
				element.set_count(count)
		else:
			var upd_idx: int = int(min(count, similar_icons.size() - 1))
			if upd_idx >= 0:
				similar_icons[upd_idx].set_count(count)

	_elements.erase(item_data)
	var elements_nodes: Array = get_children()
	for node in elements_nodes:
		if node.item_data == item_data:
			_remove_ui_node(node)
			break

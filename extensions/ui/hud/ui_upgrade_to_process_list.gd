extends "res://ui/hud/ui_upgrade_to_process_list.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Bounded HUD Upgrade Icon Nodes (_turbo_upl_)
# -----------------------------------------------------------------------------
# Per-icon overflow dictionary avoids cross-icon index crashes and preserves
# exact per-icon counts across multi-icon upgrade queues.
# =============================================================================

const _turbo_upl_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")

var _turbo_overflow_by_icon: Dictionary = {}


func _exit_tree() -> void: # ADDITION
	_turbo_overflow_by_icon.clear()


func add_element(icon: Resource, level: int) -> void:
	if _elements.empty() and get_child_count() == 0 and not _turbo_overflow_by_icon.empty():
		_turbo_overflow_by_icon.clear()

	var s = _turbo_upl_STATE_SCRIPT.HOLDER.get("state")
	if s != null and not s.optimize_hud_inventory and _turbo_overflow_by_icon.empty():
		.add_element(icon, level)
		return

	var similar_icons: Array = _get_all_similar_elements(icon)
	var overflow: Array = _turbo_overflow_by_icon.get(icon, [])
	var total_count: int = similar_icons.size() + overflow.size() + 1

	if total_count > UIItemList.MAX_SIMILAR_ICONS + 1 and not similar_icons.empty():
		if not _turbo_overflow_by_icon.has(icon):
			_turbo_overflow_by_icon[icon] = []
		_turbo_overflow_by_icon[icon].push_back(level)
		_elements.push_back(level)
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
	node.set_data(icon, level, true)
	node.set_count(total_count)
	_elements.push_back(level)
	_add_ui_node(node)


func remove_element(level: int) -> void:
	var children: Array = get_children()

	if not _turbo_overflow_by_icon.empty():
		for icon_key in _turbo_overflow_by_icon.keys():
			var ov: Array = _turbo_overflow_by_icon[icon_key]
			var ov_idx: int = ov.find(level)
			if ov_idx != -1:
				ov.remove(ov_idx)
				_elements.erase(level)
				if ov.empty():
					_turbo_overflow_by_icon.erase(icon_key)
				var sim_ov: Array = _get_all_similar_elements(icon_key)
				if not sim_ov.empty():
					sim_ov[sim_ov.size() - 1].set_count(sim_ov.size() + ov.size())
				return

		var target_node = null
		for node in children:
			if node.level == level:
				target_node = node
				break
		if target_node != null:
			var icon_k = target_node.texture if ("texture" in target_node) else null
			if icon_k != null and _turbo_overflow_by_icon.has(icon_k):
				var ov2: Array = _turbo_overflow_by_icon[icon_k]
				if not ov2.empty():
					var rep_level: int = int(ov2[0])
					ov2.remove(0)
					_elements.erase(level)
					target_node.set_data(icon_k, rep_level, true)
					if ov2.empty():
						_turbo_overflow_by_icon.erase(icon_k)
					var sim2: Array = _get_all_similar_elements(icon_k)
					if not sim2.empty():
						sim2[sim2.size() - 1].set_count(sim2.size() + ov2.size())
					return

	var rm_node = null
	for node in children:
		if node.level == level:
			rm_node = node
			break

	var group_nodes: Array = children
	if rm_node != null and "texture" in rm_node and rm_node.texture != null:
		group_nodes = _get_all_similar_elements(rm_node.texture)

	var count: int = group_nodes.size() - 1
	if count >= UIItemList.MAX_SIMILAR_ICONS:
		if count == UIItemList.MAX_SIMILAR_ICONS:
			for element in group_nodes:
				element.show()
				element.set_count(count)
		else:
			var upd_idx: int = int(min(count, group_nodes.size() - 1))
			if upd_idx >= 0:
				group_nodes[upd_idx].set_count(count)

	_elements.erase(level)
	if rm_node != null:
		_remove_ui_node(rm_node)

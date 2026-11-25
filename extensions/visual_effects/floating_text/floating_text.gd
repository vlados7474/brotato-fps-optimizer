extends "res://visual_effects/floating_text/floating_text.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - FloatingText GUI Hit-Test Stripper (_turbo_ft_)
# =============================================================================


func _ready() -> void: # ADDITION
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	set_process_unhandled_key_input(false)
	_turbo_ft_strip_gui_picking(self)


func _turbo_ft_strip_gui_picking(node: Node) -> void:
	if node is Control:
		var ctrl: Control = node
		ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ctrl.focus_mode = Control.FOCUS_NONE
	var count: int = node.get_child_count()
	for i in range(count):
		_turbo_ft_strip_gui_picking(node.get_child(i))

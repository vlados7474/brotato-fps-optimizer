extends "res://singletons/ui_service.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Disable Idle UIService._process on PC (_turbo_uis_)
# =============================================================================


func _ready(): # ADDITION
	if not Utils.on_nintendo_nx_or_ounce:
		set_process(false)

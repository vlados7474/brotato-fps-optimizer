extends "res://ui/hud/fps_label.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Disable Translation Lookups on FPSLabel (_turbo_fps_)
# =============================================================================


func _ready() -> void: # ADDITION
	set_message_translation(false)

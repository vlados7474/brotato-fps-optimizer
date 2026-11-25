extends Node
# =============================================================================
# Saffron-Turbo 5.6.1 - Late-Frame Camera Offset Integer Pixel Stabilizer
# -----------------------------------------------------------------------------
# Sleeps with set_process(false) at 0.000 ms cost whenever no shake is active.
# =============================================================================

var host: Node = null


func _ready() -> void:
	process_priority = 10000
	pause_mode = Node.PAUSE_MODE_INHERIT
	set_process(false)


func _process(_delta: float) -> void:
	if is_instance_valid(host):
		host._turbo_shk_quantize_camera_offset()
	else:
		set_process(false)

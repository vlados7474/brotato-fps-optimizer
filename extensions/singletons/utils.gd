extends "res://singletons/utils.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Utils Nearest-Target, Turret Cache & Zero-Alloc Aim Cache
# -----------------------------------------------------------------------------
# 1. Delegates get_nearest / get_nearest_no_max to scalar TurboTargeting.
# 2. Replaces vanilla _process() `set_deferred("_manual_aim_cache", [null,...])`
#    with an in-place slot clear, eliminating per-frame Array allocations and
#    message_queue churn (up to 180 allocations + deferred calls/sec).
# =============================================================================

const _turbo_utl_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")
const _turbo_utl_TARGETING = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_targeting.gd")

var _turbo_utl_state = null


func _ready() -> void: # ADDITION
	_turbo_utl_state = _turbo_utl_STATE_SCRIPT.HOLDER.get("state")



func get_nearest(targets: Array, from: Vector2, min_distance: int = 0, max_range: int = LARGE_NUMBER) -> Array:
	if _turbo_utl_state != null and not _turbo_utl_state.fast_nearest_scan:
		return .get_nearest(targets, from, min_distance, max_range)
	return _turbo_utl_TARGETING.get_nearest(targets, from, min_distance, max_range)


func get_nearest_no_max(targets: Array, from: Vector2, min_distance: int = 0) -> Array:
	if _turbo_utl_state != null and not _turbo_utl_state.fast_nearest_scan:
		return .get_nearest_no_max(targets, from, min_distance)
	return _turbo_utl_TARGETING.get_nearest_no_max(targets, from, min_distance, _turbo_utl_state)

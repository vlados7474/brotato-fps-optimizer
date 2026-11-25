extends "res://entities/structures/turret/turret.gd"
# =============================================================================
# Saffron-Turbo 5.6.1 - Turret Curse-Particle Guard & Dead Range Monitoring Cut
# -----------------------------------------------------------------------------
# Intentionally does NOT override _physics_process (zero per-tick overhead,
# zero conflicts with turret AI or firing-rate mods, Defect #12 safe).
# =============================================================================

const _turbo_turret_STATE_SCRIPT = preload("res://mods-unpacked/Saffron-Turbo/scripts/turbo_state.gd")

onready var _turbo_turret_range: Area2D = get_node_or_null("Range") as Area2D


func set_data(data: Resource) -> void:
	if is_instance_valid(curse_particle_instance):
		curse_particle_instance.queue_free()
		curse_particle_instance = null

	if data != null and data.is_cursed and curse_particles == null:
		data.is_cursed = false
		.set_data(data)
		data.is_cursed = true
		is_cursed = true
		add_outline(Utils.CURSE_COLOR)
		return

	.set_data(data)

	if is_instance_valid(curse_particle_instance):
		_turbo_turret_apply_particle_policy(curse_particle_instance)


func respawn() -> void:
	.respawn()
	if is_instance_valid(_turbo_turret_range):
		_turbo_turret_range.set_deferred("monitoring", true)


func die(args: Entity.DieArgs = Utils.default_die_args) -> void:
	_turbo_turret_disable_range()
	.die(args)


func _on_despawn(args: Entity.DieArgs) -> void:
	_turbo_turret_disable_range()
	._on_despawn(args)


func _turbo_turret_disable_range() -> void:
	if is_instance_valid(_turbo_turret_range):
		_turbo_turret_range.set_deferred("monitoring", false)


func _turbo_turret_apply_particle_policy(node: Node) -> void:
	var s = _turbo_turret_STATE_SCRIPT.HOLDER.get("state")
	if s == null:
		return
	if s.stream_potato or s.tier >= 4:
		node.queue_free()
		curse_particle_instance = null
		return
	if s.throttle_particle_sim_fps and s.fx_sim_fps > 0 and node is CPUParticles2D:
		node.fixed_fps = s.fx_sim_fps
		node.fract_delta = false

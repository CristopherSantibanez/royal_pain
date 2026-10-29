extends SceneTree
func _initialize() -> void:
	for bus_name in ["Music", "Ambience", "SFX"]:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, limiter)
	print(ResourceSaver.save(AudioServer.generate_bus_layout(), "res://default_bus_layout.tres"))
	quit()

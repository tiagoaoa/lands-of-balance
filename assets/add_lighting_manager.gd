extends SceneTree
## Run with: godot --headless --script res://assets/add_lighting_manager.gd

func _init() -> void:
	print("Adding LightingManager to scene...")

	var scene_path := "res://stage/lands_of_balance.tscn"
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Failed to load scene")
		quit()
		return

	var scene: Node3D = packed.instantiate()

	# Check if LightingManager already exists
	if scene.has_node("LightingManager"):
		print("LightingManager already exists, skipping")
		scene.queue_free()
		quit()
		return

	# Create LightingManager node
	var lighting_manager := Node.new()
	lighting_manager.name = "LightingManager"
	lighting_manager.set_script(load("res://stage/lighting_manager.gd"))

	# Add as first child so it loads early
	scene.add_child(lighting_manager)
	scene.move_child(lighting_manager, 0)
	lighting_manager.owner = scene

	# Save the modified scene
	var new_packed := PackedScene.new()
	new_packed.pack(scene)
	var err := ResourceSaver.save(new_packed, scene_path)
	if err == OK:
		print("Done! Added LightingManager to scene")
		print("Features:")
		print("  - Export variable 'time_of_day' (DAY or NIGHT)")
		print("  - Press 'L' in-game to toggle day/night")
		print("  - Smooth 2-second transitions")
	else:
		push_error("Failed to save: " + str(err))

	scene.queue_free()
	quit()

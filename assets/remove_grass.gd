extends SceneTree
## Run with: godot --headless --script res://assets/remove_grass.gd

func _init() -> void:
	print("Removing auto-generated grass, keeping earth terrain...")

	var scene_path := "res://stage/lands_of_balance.tscn"
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Failed to load scene")
		quit()
		return

	var scene: Node3D = packed.instantiate()

	# Remove Grass node if it exists
	if scene.has_node("Grass"):
		var grass_node = scene.get_node("Grass")
		grass_node.queue_free()
		print("Removed auto-generated Grass node")

	# Save
	var new_packed := PackedScene.new()
	new_packed.pack(scene)
	var err := ResourceSaver.save(new_packed, scene_path)
	if err == OK:
		print("Done! Scene saved with earth terrain only")
		print("You can now manually place grass using assets/realistic_grass.glb in the editor")
	else:
		push_error("Failed to save: " + str(err))

	scene.queue_free()
	quit()

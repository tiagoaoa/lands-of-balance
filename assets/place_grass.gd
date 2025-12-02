extends SceneTree
## Run with: godot --headless --script res://assets/place_grass.gd

func _init() -> void:
	print("Placing realistic grass on terrain using MultiMesh...")

	var scene_path := "res://stage/lands_of_balance.tscn"
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Failed to load scene")
		quit()
		return

	var scene: Node3D = packed.instantiate()

	# Load realistic grass GLB
	var grass_scene: PackedScene = load("res://assets/realistic_grass.glb")
	if grass_scene == null:
		push_error("Failed to load realistic_grass.glb")
		quit()
		return

	# Extract mesh from the GLB
	var grass_instance: Node3D = grass_scene.instantiate()
	var grass_mesh := _find_mesh_in_node(grass_instance)
	if grass_mesh == null:
		push_error("No mesh found in realistic_grass.glb")
		grass_instance.free()
		quit()
		return

	print("Found grass mesh: ", grass_mesh.resource_name if grass_mesh.resource_name else "unnamed")
	grass_instance.free()

	# Create or get Grass container
	var grass_container: Node3D
	if scene.has_node("Grass"):
		grass_container = scene.get_node("Grass")
		for child in grass_container.get_children():
			child.queue_free()
	else:
		grass_container = Node3D.new()
		grass_container.name = "Grass"
		scene.add_child(grass_container)
		grass_container.owner = scene

	var rng := RandomNumberGenerator.new()
	rng.seed = 54321  # Fixed seed for reproducibility

	# Terrain is 300x300 centered at origin
	var grass_count := 3000

	# Create MultiMeshInstance3D
	var multi_mesh := MultiMesh.new()
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.mesh = grass_mesh
	multi_mesh.instance_count = grass_count

	for i in range(grass_count):
		var x := rng.randf_range(-130.0, 130.0)
		var z := rng.randf_range(-130.0, 130.0)

		# Skip village center area (smaller exclusion zone)
		if abs(x) < 20.0 and abs(z) < 20.0:
			x = rng.randf_range(25.0, 130.0) * (1 if rng.randf() > 0.5 else -1)

		var y := 0.0

		# Random rotation
		var rot := rng.randf_range(0, TAU)

		# Random scale (0.8 to 1.5 for variety)
		var scale_factor := rng.randf_range(0.8, 1.5)

		var transform := Transform3D()
		transform = transform.rotated(Vector3.UP, rot)
		transform = transform.scaled(Vector3(scale_factor, scale_factor, scale_factor))
		transform.origin = Vector3(x, y, z)

		multi_mesh.set_instance_transform(i, transform)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "RealisticGrass"
	mmi.multimesh = multi_mesh
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grass_container.add_child(mmi)
	mmi.owner = scene

	# Save
	var new_packed := PackedScene.new()
	new_packed.pack(scene)
	var err := ResourceSaver.save(new_packed, scene_path)
	if err == OK:
		print("Done! Placed %d realistic grass instances across the terrain" % grass_count)
	else:
		push_error("Failed to save: " + str(err))

	scene.queue_free()
	quit()

func _find_mesh_in_node(node: Node) -> Mesh:
	if node is MeshInstance3D:
		return node.mesh
	for child in node.get_children():
		var mesh := _find_mesh_in_node(child)
		if mesh:
			return mesh
	return null

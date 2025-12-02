extends SceneTree
## Run with: godot --headless --script res://assets/trees/place_trees.gd

func _init() -> void:
	print("Placing random trees on terrain...")

	# Load the scene
	var scene_path := "res://stage/lands_of_balance.tscn"
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Failed to load scene")
		quit()
		return

	var scene: Node3D = packed.instantiate()

	# Tree scenes to use
	var tree_scenes := [
		preload("res://assets/trees/individual/Tree_EZTree1_Large001.tscn"),
		preload("res://assets/trees/individual/Tree_EZTree1_Large009.tscn"),
		preload("res://assets/trees/individual/Tree_EZTree0_Large.tscn"),
		preload("res://assets/trees/individual/Tree_EZTree0_Medium010.tscn"),
		preload("res://assets/trees/individual/Tree_EZTree0_Medium011.tscn"),
		preload("res://assets/trees/individual/Tree_EZTree1_Medium002.tscn"),
		preload("res://assets/trees/individual/Tree_EZTree1_Bush006.tscn"),
	]

	# Create Trees container node
	var trees_node: Node3D
	if scene.has_node("Trees"):
		trees_node = scene.get_node("Trees")
		# Clear existing trees
		for child in trees_node.get_children():
			child.queue_free()
	else:
		trees_node = Node3D.new()
		trees_node.name = "Trees"
		scene.add_child(trees_node)
		trees_node.owner = scene

	# MainGround is 300x300 centered at origin
	# Village is around (0,0), River runs through center
	# Place trees around the perimeter, avoiding center areas
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# Define tree placement zones (edges of map, not center)
	var zones := [
		# North edge
		{"min_x": -140.0, "max_x": 140.0, "min_z": -140.0, "max_z": -80.0, "count": 12},
		# South edge
		{"min_x": -140.0, "max_x": 140.0, "min_z": 40.0, "max_z": 140.0, "count": 12},
		# West edge
		{"min_x": -140.0, "max_x": -40.0, "min_z": -80.0, "max_z": 40.0, "count": 10},
		# East edge
		{"min_x": 40.0, "max_x": 140.0, "min_z": -80.0, "max_z": 40.0, "count": 10},
	]

	var tree_index := 0
	for zone in zones:
		for i in range(zone.count):
			var tree_scene: PackedScene = tree_scenes[rng.randi() % tree_scenes.size()]
			var tree: Node3D = tree_scene.instantiate()

			# Random position within zone
			var x := rng.randf_range(zone.min_x, zone.max_x)
			var z := rng.randf_range(zone.min_z, zone.max_z)
			var y := 0.0

			tree.position = Vector3(x, y, z)

			# Random rotation around Y axis
			tree.rotation.y = rng.randf_range(0, TAU)

			# Random scale (0.7 to 1.4 for variety)
			var scale_factor := rng.randf_range(0.7, 1.4)
			tree.scale = Vector3(scale_factor, scale_factor, scale_factor)

			tree.name = "Tree_%03d" % tree_index
			trees_node.add_child(tree)
			tree.owner = scene
			tree_index += 1

	# Save the modified scene
	var new_packed := PackedScene.new()
	new_packed.pack(scene)
	var err := ResourceSaver.save(new_packed, scene_path)
	if err == OK:
		print("Done! Added %d trees to %s" % [tree_index, scene_path])
		print("Trees are under the 'Trees' node - you can move/delete them individually in editor")
	else:
		push_error("Failed to save: " + str(err))

	scene.queue_free()
	quit()

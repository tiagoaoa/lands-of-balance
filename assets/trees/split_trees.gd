extends SceneTree
## Run with: godot --headless --script res://assets/trees/split_trees.gd

func _init() -> void:
	print("Splitting realistic_trees_collection.glb into individual scenes...")

	var glb_path := "res://assets/trees/realistic_trees_collection.glb"
	var output_dir := "res://assets/trees/individual/"

	# Create output directory
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))

	# Load the GLB
	var collection: PackedScene = load(glb_path)
	if collection == null:
		push_error("Failed to load: " + glb_path)
		quit()
		return

	var root: Node3D = collection.instantiate()

	# Find tree parent nodes (nodes that contain mesh children)
	var tree_nodes: Array[Node3D] = []
	_find_tree_nodes(root, tree_nodes)
	print("Found ", tree_nodes.size(), " complete trees")

	var tree_count := 0

	for tree_node in tree_nodes:
		var tree_name: String = tree_node.name
		# Clean up name
		tree_name = tree_name.replace(" ", "_").replace(".", "_")
		print("Processing complete tree: ", tree_name)

		# Create a new scene with this tree as root
		var new_root := Node3D.new()
		new_root.name = tree_name

		# Clone the entire tree node with all its children
		var cloned := tree_node.duplicate()
		cloned.position = Vector3.ZERO  # Reset position
		new_root.add_child(cloned)
		cloned.owner = new_root
		_set_owner_recursive(cloned, new_root)

		# Save as scene
		var packed := PackedScene.new()
		packed.pack(new_root)

		var save_path := output_dir + tree_name + ".tscn"
		var err := ResourceSaver.save(packed, save_path)
		if err == OK:
			print("  Saved: ", save_path)
			tree_count += 1
		else:
			push_error("  Failed to save: " + save_path)

		new_root.free()

	root.free()
	print("Done! Split ", tree_count, " complete trees at ", output_dir)
	quit()

func _find_tree_nodes(node: Node, results: Array[Node3D]) -> void:
	# A tree node is a Node3D that:
	# 1. Has "Tree" in its name
	# 2. Has MeshInstance3D children (branches/leaves)
	if node is Node3D and "Tree" in node.name:
		var has_mesh_children := false
		for child in node.get_children():
			if child is MeshInstance3D:
				has_mesh_children = true
				break
		if has_mesh_children:
			results.append(node as Node3D)
			return  # Don't recurse into this node's children

	for child in node.get_children():
		_find_tree_nodes(child, results)

func _set_owner_recursive(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_set_owner_recursive(child, owner)

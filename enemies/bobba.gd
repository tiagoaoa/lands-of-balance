class_name Bobba
extends CharacterBody3D
## Bobba - A roaming creature that attacks when the player gets close.
## Roams around the map randomly, switches to attack mode within 10 meters of player.

enum State { ROAMING, CHASING, ATTACKING, IDLE }

const ROAM_SPEED: float = 2.0
const CHASE_SPEED: float = 5.0
const ATTACK_RANGE: float = 10.0  # Detection radius in meters
const ATTACK_DISTANCE: float = 2.0  # Distance to start attack animation
const ROAM_CHANGE_TIME: float = 3.0  # Time between direction changes
const ROTATION_SPEED: float = 5.0

var state: State = State.ROAMING
var player: Node3D = null
var roam_direction: Vector3 = Vector3.ZERO
var roam_timer: float = 0.0
var attack_cooldown: float = 0.0

# Animation
var _anim_player: AnimationPlayer
var _model: Node3D
var _current_anim: StringName = &""

# Animation paths
const ANIM_PATHS: Dictionary = {
	"idle": "res://assets/bobba/mutant idle.fbx",
	"walk": "res://assets/bobba/mutant walking.fbx",
	"run": "res://assets/bobba/mutant run.fbx",
	"attack": "res://assets/bobba/mutant swiping.fbx",
	"roar": "res://assets/bobba/mutant roaring.fbx",
	"dying": "res://assets/bobba/mutant dying.fbx",
	"jump_attack": "res://assets/bobba/mutant jump attack.fbx",
}

@onready var gravity: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity") * \
		ProjectSettings.get_setting("physics/3d/default_gravity_vector")


func _ready() -> void:
	_find_player()
	_setup_model()
	_pick_new_roam_direction()


func _find_player() -> void:
	# Find the player in the scene
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		# Try to find by class name
		for node in get_tree().get_nodes_in_group(""):
			if node is CharacterBody3D and node.name == "Player":
				player = node
				break
	if player == null:
		# Search entire tree
		player = _find_node_by_name(get_tree().root, "Player")


func _find_node_by_name(node: Node, target_name: String) -> Node:
	if node.name == target_name:
		return node
	for child in node.get_children():
		var result = _find_node_by_name(child, target_name)
		if result:
			return result
	return null


func _setup_model() -> void:
	# Find the model and animation player
	for child in get_children():
		if child is Node3D and child.name != "CollisionShape3D":
			_model = child
			print("Bobba: Found model: ", child.name)
			break

	if _model:
		# Always force-apply our material to ensure visibility
		print("Bobba: Force-applying material to model")
		_apply_textures(_model)

		_anim_player = _find_animation_player(_model)
		if _anim_player:
			print("Bobba: Found AnimationPlayer: ", _anim_player.name)
			print("Bobba: AnimationPlayer root node: ", _anim_player.root_node)
			_anim_player.animation_finished.connect(_on_animation_finished)
			_load_animations()
			print("Bobba: Available animations after load: ", _anim_player.get_animation_list())
			_play_anim(&"bobba/Idle")
		else:
			print("Bobba: ERROR - No AnimationPlayer found in model!")
			_print_node_tree(_model, 0)
	else:
		print("Bobba: ERROR - No model found!")


func _print_node_tree(node: Node, depth: int) -> void:
	var indent = ""
	for i in range(depth):
		indent += "  "
	print(indent, node.name, " [", node.get_class(), "]")
	for child in node.get_children():
		_print_node_tree(child, depth + 1)


func _check_needs_material(node: Node) -> bool:
	# Check if any mesh has a valid albedo texture
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.mesh:
			for i in range(mesh_inst.mesh.get_surface_count()):
				var mat = mesh_inst.get_surface_override_material(i)
				if mat == null:
					mat = mesh_inst.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					var std_mat = mat as StandardMaterial3D
					if std_mat.albedo_texture != null:
						print("Bobba: Found existing texture on ", mesh_inst.name)
						return false
	for child in node.get_children():
		if not _check_needs_material(child):
			return false
	return true


func _apply_textures(node: Node) -> void:
	# Load the pre-made material with textures
	var bobba_mat = load("res://assets/bobba/bobba_material.tres") as StandardMaterial3D
	if bobba_mat == null:
		print("Bobba: Failed to load material!")
		return

	_apply_material_recursive(node, bobba_mat)


func _apply_material_recursive(node: Node, mat: Material) -> void:
	print("Bobba: Checking node ", node.name, " [", node.get_class(), "]")

	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		print("Bobba: Found MeshInstance3D: ", mesh_inst.name)

		# Apply material override to the entire mesh
		mesh_inst.material_override = mat
		print("Bobba: Applied material_override")

		# Also try applying to individual surfaces
		if mesh_inst.mesh:
			var surface_count = mesh_inst.mesh.get_surface_count()
			print("Bobba: Mesh has ", surface_count, " surfaces")
			for i in range(surface_count):
				mesh_inst.set_surface_override_material(i, mat)
				print("Bobba: Applied to surface ", i)

	for child in node.get_children():
		_apply_material_recursive(child, mat)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null


func _load_animations() -> void:
	if _anim_player == null or _model == null:
		return

	var skeleton: Skeleton3D = _find_skeleton(_model)
	if skeleton == null:
		print("Bobba: No skeleton found")
		return

	var anim_root: Node = _anim_player.get_node(_anim_player.root_node)
	var skel_path: String = str(anim_root.get_path_to(skeleton))

	var anim_config: Dictionary = {
		"idle": ["Idle", true],
		"walk": ["Walk", true],
		"run": ["Run", true],
		"attack": ["Attack", false],
		"roar": ["Roar", false],
		"dying": ["Dying", false],
		"jump_attack": ["JumpAttack", false],
	}

	for anim_key in ANIM_PATHS:
		var fbx_path: String = ANIM_PATHS[anim_key]
		var scene: PackedScene = load(fbx_path) as PackedScene
		if scene == null:
			print("Bobba: Failed to load animation: ", fbx_path)
			continue

		var instance: Node3D = scene.instantiate()
		var anim_player_src: AnimationPlayer = _find_animation_player(instance)
		if anim_player_src == null:
			instance.queue_free()
			continue

		# Find best animation
		var best_anim: Animation = null
		var best_key_count: int = 0

		for src_lib_name in anim_player_src.get_animation_library_list():
			var src_lib: AnimationLibrary = anim_player_src.get_animation_library(src_lib_name)
			for src_anim_name in src_lib.get_animation_list():
				var anim: Animation = src_lib.get_animation(src_anim_name)
				var total_keys: int = 0
				for t in range(anim.get_track_count()):
					total_keys += anim.track_get_key_count(t)
				if total_keys > best_key_count:
					best_anim = anim
					best_key_count = total_keys

		if best_anim != null:
			var new_anim: Animation = best_anim.duplicate()
			var config: Array = anim_config.get(anim_key, [anim_key, false])
			new_anim.loop_mode = Animation.LOOP_LINEAR if config[1] else Animation.LOOP_NONE

			# Retarget animation
			_retarget_animation(new_anim, skel_path, skeleton)

			var lib_name: StringName = &"bobba"
			if not _anim_player.has_animation_library(lib_name):
				_anim_player.add_animation_library(lib_name, AnimationLibrary.new())
			_anim_player.get_animation_library(lib_name).add_animation(StringName(config[0]), new_anim)
			print("Bobba: Loaded animation bobba/", config[0])

		instance.queue_free()


func _retarget_animation(anim: Animation, target_skeleton_path: String, skeleton: Skeleton3D) -> void:
	var tracks_to_remove: Array[int] = []

	# Debug: print skeleton bone names once
	if skeleton.get_bone_count() > 0:
		print("Bobba: Skeleton has ", skeleton.get_bone_count(), " bones")
		print("Bobba: First few bones: ", skeleton.get_bone_name(0), ", ", skeleton.get_bone_name(1) if skeleton.get_bone_count() > 1 else "")

	for i in range(anim.get_track_count()):
		var track_path: NodePath = anim.track_get_path(i)
		var path_str: String = str(track_path)

		# Find the bone name part (after the last colon for skeleton tracks)
		var colon_pos: int = path_str.rfind(":")
		if colon_pos == -1:
			continue

		var bone_name: String = path_str.substr(colon_pos + 1)

		# Convert animation bone names (mixamorig:BoneName) to Godot format (mixamorig_BoneName)
		var godot_bone_name: String = bone_name.replace(":", "_")

		# Remove root motion from Hips
		if godot_bone_name == "mixamorig_Hips" and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			tracks_to_remove.append(i)
			continue

		# Verify bone exists in skeleton
		if skeleton.find_bone(godot_bone_name) == -1:
			# Try original name as fallback
			if skeleton.find_bone(bone_name) != -1:
				godot_bone_name = bone_name
			else:
				print("Bobba: Bone not found: ", bone_name, " / ", godot_bone_name)
				continue

		var new_path: String = target_skeleton_path + ":" + godot_bone_name
		anim.track_set_path(i, NodePath(new_path))

	tracks_to_remove.reverse()
	for track_idx in tracks_to_remove:
		anim.remove_track(track_idx)


func _play_anim(anim_name: StringName) -> void:
	if _anim_player == null:
		return
	if _current_anim == anim_name:
		return
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
		_current_anim = anim_name


func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == &"bobba/Attack" or anim_name == &"bobba/JumpAttack":
		attack_cooldown = 0.5
		state = State.CHASING


func _pick_new_roam_direction() -> void:
	var angle = randf() * TAU
	roam_direction = Vector3(cos(angle), 0, sin(angle))
	roam_timer = ROAM_CHANGE_TIME


func _physics_process(delta: float) -> void:
	if attack_cooldown > 0:
		attack_cooldown -= delta

	# Apply gravity
	velocity += gravity * delta

	# Check distance to player
	var distance_to_player: float = INF
	if player and is_instance_valid(player):
		distance_to_player = global_position.distance_to(player.global_position)

	# State machine
	match state:
		State.ROAMING:
			_handle_roaming(delta, distance_to_player)
		State.CHASING:
			_handle_chasing(delta, distance_to_player)
		State.ATTACKING:
			_handle_attacking(delta)
		State.IDLE:
			_handle_idle(delta, distance_to_player)

	move_and_slide()


func _handle_roaming(delta: float, distance_to_player: float) -> void:
	# Check if player is within attack range
	if distance_to_player <= ATTACK_RANGE:
		state = State.CHASING
		_play_anim(&"bobba/Roar")
		return

	# Update roam timer
	roam_timer -= delta
	if roam_timer <= 0:
		_pick_new_roam_direction()

	# Move in roam direction
	var horizontal_velocity = roam_direction * ROAM_SPEED
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	# Rotate to face movement direction
	if _model and roam_direction.length() > 0.1:
		var target_rotation = atan2(roam_direction.x, roam_direction.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_rotation, ROTATION_SPEED * delta)

	_play_anim(&"bobba/Walk")


func _handle_chasing(delta: float, distance_to_player: float) -> void:
	# If player escapes attack range, go back to roaming
	if distance_to_player > ATTACK_RANGE * 1.5:
		state = State.ROAMING
		_pick_new_roam_direction()
		return

	# If close enough, attack
	if distance_to_player <= ATTACK_DISTANCE and attack_cooldown <= 0:
		state = State.ATTACKING
		_play_anim(&"bobba/Attack")
		velocity.x = 0
		velocity.z = 0
		return

	# Chase the player
	if player and is_instance_valid(player):
		var direction = (player.global_position - global_position).normalized()
		direction.y = 0

		var horizontal_velocity = direction * CHASE_SPEED
		velocity.x = horizontal_velocity.x
		velocity.z = horizontal_velocity.z

		# Rotate to face player
		if _model and direction.length() > 0.1:
			var target_rotation = atan2(direction.x, direction.z)
			_model.rotation.y = lerp_angle(_model.rotation.y, target_rotation, ROTATION_SPEED * delta)

		_play_anim(&"bobba/Run")


func _handle_attacking(_delta: float) -> void:
	# Stay in attacking state until animation finishes
	velocity.x = 0
	velocity.z = 0


func _handle_idle(delta: float, distance_to_player: float) -> void:
	if distance_to_player <= ATTACK_RANGE:
		state = State.CHASING
	else:
		# Randomly start roaming
		if randf() < 0.01:
			state = State.ROAMING
			_pick_new_roam_direction()

	_play_anim(&"bobba/Idle")

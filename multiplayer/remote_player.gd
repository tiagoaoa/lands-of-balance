extends CharacterBody3D
class_name RemotePlayer

## Represents another player in the multiplayer game
## Receives position updates from the server and interpolates movement
## Supports Archer and Paladin character classes with proper animations

@export var player_id: int = 0
@export var interpolation_speed: float = 20.0

var target_position: Vector3 = Vector3.ZERO
var target_rotation_y: float = 0.0
var current_state: int = 0
var combat_mode: int = 1
var health: float = 100.0
var current_anim_name: String = "Idle"

var _character_model: Node3D
var _anim_player: AnimationPlayer
var _name_label: Label3D
var _current_playing_anim: StringName = &""

# State constants
const STATE_IDLE = 0
const STATE_WALKING = 1
const STATE_RUNNING = 2
const STATE_ATTACKING = 3
const STATE_BLOCKING = 4
const STATE_JUMPING = 5

# Archer character and animations (default)
const ARCHER_CHARACTER_PATH = "res://player/character/archer/Archer.fbx"
const ARCHER_ANIM_PATHS: Dictionary = {
	"Idle": "res://player/character/archer/Idle.fbx",
	"Walk": "res://player/character/archer/Walk.fbx",
	"Run": "res://player/character/archer/Run.fbx",
	"Jump": "res://player/character/archer/Jump.fbx",
	"Attack": "res://player/character/archer/Attack.fbx",
	"Block": "res://player/character/archer/Block.fbx",
	"Sprint": "res://player/character/archer/Sprint.fbx",
}


func _ready() -> void:
	# Setup collision
	collision_layer = 8  # Layer 4 for remote players
	collision_mask = 1   # Collide with world

	_setup_character_model()
	_setup_collision()
	_setup_name_label()


func _physics_process(delta: float) -> void:
	# Interpolate position
	global_position = global_position.lerp(target_position, interpolation_speed * delta)

	# Interpolate rotation - apply to model, not body
	if _character_model:
		_character_model.rotation.y = lerp_angle(_character_model.rotation.y, target_rotation_y, interpolation_speed * delta)

	# Apply gravity and move
	if not is_on_floor():
		velocity.y -= 22.0 * delta
	else:
		velocity.y = 0

	move_and_slide()

	# Update animation based on state
	_update_animation()


func update_from_network(data: Dictionary) -> void:
	target_position = data.get("position", target_position)
	target_rotation_y = data.get("rotation_y", target_rotation_y)
	current_state = data.get("state", current_state)
	combat_mode = data.get("combat_mode", combat_mode)
	health = data.get("health", health)
	current_anim_name = data.get("anim_name", current_anim_name)


func _setup_character_model() -> void:
	# Load Archer character (all players start as Archer)
	var character_scene = load(ARCHER_CHARACTER_PATH)

	if character_scene:
		_character_model = character_scene.instantiate()
		_character_model.name = "Model"
		add_child(_character_model)

		# Scale character appropriately (same as player.gd)
		var skeleton = _find_skeleton(_character_model)
		if skeleton and skeleton.get_bone_count() > 0:
			var hips_idx: int = skeleton.find_bone("mixamorig_Hips")
			if hips_idx >= 0:
				var hips_pos: Vector3 = skeleton.get_bone_global_rest(hips_idx).origin
				if hips_pos.y > 50:
					_character_model.scale = Vector3(0.01, 0.01, 0.01)
				else:
					_character_model.scale = Vector3(1.0, 1.0, 1.0)
			else:
				_character_model.scale = Vector3(0.01, 0.01, 0.01)
		else:
			_character_model.scale = Vector3(0.01, 0.01, 0.01)

		# Find existing AnimationPlayer in the model
		_anim_player = _find_animation_player(_character_model)

		if _anim_player == null:
			# Create AnimationPlayer if not found
			_anim_player = AnimationPlayer.new()
			_anim_player.name = "AnimationPlayer"
			_character_model.add_child(_anim_player)

		# Find skeleton for animation retargeting
		if skeleton:
			_load_animations(skeleton)
			print("RemotePlayer: Loaded animations for player %d" % player_id)

		# Play idle by default
		if _anim_player.has_animation("Idle"):
			_anim_player.play("Idle")
			_current_playing_anim = &"Idle"

		# Apply a different color tint to distinguish from local player
		_apply_remote_player_tint()
	else:
		push_error("RemotePlayer: Failed to load character model")
		# Fallback: create a simple capsule mesh
		_create_fallback_model()


func _create_fallback_model() -> void:
	var mesh_instance = MeshInstance3D.new()
	var capsule = CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	mesh_instance.mesh = capsule
	mesh_instance.position.y = 0.9

	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.6, 1.0)  # Blue tint for remote players
	mesh_instance.material_override = material

	add_child(mesh_instance)
	_character_model = mesh_instance


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result:
			return result
	return null


func _load_animations(skeleton: Skeleton3D) -> void:
	# Get animation root and skeleton path for retargeting
	var anim_root: Node = _anim_player.get_node(_anim_player.root_node)
	var skel_path: String = str(anim_root.get_path_to(skeleton))

	print("RemotePlayer: Loading animations - skeleton path: ", skel_path)

	# Animation configs: name -> [display_name, loop]
	var anim_configs: Dictionary = {
		"Idle": ["Idle", true],
		"Walk": ["Walk", true],
		"Run": ["Run", true],
		"Jump": ["Jump", false],
		"Attack": ["Attack", false],
		"Block": ["Block", true],
		"Sprint": ["Sprint", true],
	}

	for anim_name in ARCHER_ANIM_PATHS:
		var anim_path = ARCHER_ANIM_PATHS[anim_name]
		var anim_scene = load(anim_path)
		if anim_scene == null:
			print("RemotePlayer: Failed to load animation: ", anim_path)
			continue

		var anim_instance = anim_scene.instantiate()
		var source_anim_player = _find_animation_player(anim_instance)

		if source_anim_player == null:
			print("RemotePlayer: No AnimationPlayer in: ", anim_path)
			anim_instance.queue_free()
			continue

		# Find best animation (most keyframes)
		var best_anim: Animation = null
		var best_key_count: int = 0

		for lib_name in source_anim_player.get_animation_library_list():
			var lib: AnimationLibrary = source_anim_player.get_animation_library(lib_name)
			for src_anim_name in lib.get_animation_list():
				var anim: Animation = lib.get_animation(src_anim_name)
				var total_keys: int = 0
				for t in range(anim.get_track_count()):
					total_keys += anim.track_get_key_count(t)
				var keys_per_track: float = float(total_keys) / max(anim.get_track_count(), 1)
				if total_keys > best_key_count and keys_per_track > 1.5:
					best_anim = anim
					best_key_count = total_keys

		if best_anim != null:
			var new_anim: Animation = best_anim.duplicate()

			# Set loop mode
			var config = anim_configs.get(anim_name, [anim_name, false])
			new_anim.loop_mode = Animation.LOOP_LINEAR if config[1] else Animation.LOOP_NONE

			# Retarget animation tracks to our skeleton
			_retarget_animation(new_anim, skel_path, skeleton)

			# Add to default library
			if not _anim_player.has_animation_library(&""):
				_anim_player.add_animation_library(&"", AnimationLibrary.new())
			_anim_player.get_animation_library(&"").add_animation(anim_name, new_anim)
			print("RemotePlayer: Loaded animation: ", anim_name)

		anim_instance.queue_free()

	print("RemotePlayer: Animation library has: ", _anim_player.get_animation_list())


func _retarget_animation(anim: Animation, target_skeleton_path: String, skeleton: Skeleton3D) -> void:
	var tracks_to_remove: Array[int] = []

	for i in range(anim.get_track_count()):
		var track_path: NodePath = anim.track_get_path(i)
		var path_str: String = str(track_path)

		var colon_pos: int = path_str.find(":")
		if colon_pos == -1:
			continue

		var bone_name: String = path_str.substr(colon_pos + 1)

		# Remove root motion from Hips
		if bone_name == "mixamorig_Hips" and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			tracks_to_remove.append(i)
			continue

		# Check if bone exists in our skeleton
		if skeleton.find_bone(bone_name) == -1:
			tracks_to_remove.append(i)
			continue

		# Retarget to our skeleton path
		var new_path: String = target_skeleton_path + ":" + bone_name
		anim.track_set_path(i, NodePath(new_path))

	# Remove invalid tracks in reverse order
	tracks_to_remove.reverse()
	for idx in tracks_to_remove:
		anim.remove_track(idx)


func _setup_collision() -> void:
	var collision = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)


func _setup_name_label() -> void:
	_name_label = Label3D.new()
	_name_label.text = "Player %d" % player_id
	_name_label.position = Vector3(0, 2.5, 0)
	_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_name_label.no_depth_test = true
	_name_label.font_size = 20
	_name_label.modulate = Color(0.8, 0.9, 1.0)
	add_child(_name_label)


func _apply_remote_player_tint() -> void:
	# Apply a slight blue-ish emission to distinguish remote players
	_apply_tint_recursive(_character_model)


func _apply_tint_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		# Create a tinted material
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.85, 1.0)  # Slight blue tint
		mat.emission_enabled = true
		mat.emission = Color(0.1, 0.15, 0.3)
		mat.emission_energy_multiplier = 0.3
		# Don't override for now - let original textures show
		# mesh_instance.material_override = mat

	for child in node.get_children():
		_apply_tint_recursive(child)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null


func _update_animation() -> void:
	if _anim_player == null:
		return

	# Use the animation name received from network
	var anim_name = current_anim_name

	# Map animation names from player format to remote player format
	# The player uses "archer/Idle" format, we just need "Idle"
	if "/" in anim_name:
		anim_name = anim_name.split("/")[-1]

	# Capitalize first letter if needed
	if not anim_name.is_empty():
		anim_name = anim_name[0].to_upper() + anim_name.substr(1)

	# Fallback to state-based animation if name not found
	if not _anim_player.has_animation(anim_name):
		match current_state:
			STATE_IDLE:
				anim_name = "Idle"
			STATE_WALKING:
				anim_name = "Walk"
			STATE_RUNNING:
				anim_name = "Run"
			STATE_ATTACKING:
				anim_name = "Attack"
			STATE_BLOCKING:
				anim_name = "Block"
			STATE_JUMPING:
				anim_name = "Jump"

	# Try to play the animation if it exists and different from current
	if _anim_player.has_animation(anim_name):
		if _current_playing_anim != anim_name:
			_anim_player.play(anim_name)
			_current_playing_anim = anim_name

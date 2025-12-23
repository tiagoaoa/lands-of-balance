extends CharacterBody3D
class_name RemotePlayer

## Represents another player in the multiplayer game
## Receives position updates from the server and interpolates movement

@export var player_id: int = 0
@export var interpolation_speed: float = 15.0

var target_position: Vector3 = Vector3.ZERO
var target_rotation_y: float = 0.0
var current_state: int = 0
var combat_mode: int = 1
var health: float = 100.0
var current_anim_name: String = "Idle"

var _character_model: Node3D
var _anim_player: AnimationPlayer
var _name_label: Label3D

# State constants
const STATE_IDLE = 0
const STATE_WALKING = 1
const STATE_RUNNING = 2
const STATE_ATTACKING = 3
const STATE_BLOCKING = 4
const STATE_JUMPING = 5

# Animation paths
const ARMED_ANIM_PATHS: Dictionary = {
	"Idle": "res://player/character/armed/Idle.fbx",
	"Walk": "res://player/character/armed/Walk.fbx",
	"Run": "res://player/character/armed/Run.fbx",
	"Jump": "res://player/character/armed/Jump.fbx",
	"Attack1": "res://player/character/armed/Attack1.fbx",
	"Block": "res://player/character/armed/Block.fbx",
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

	# Interpolate rotation
	rotation.y = lerp_angle(rotation.y, target_rotation_y, interpolation_speed * delta)

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
	# Load the same character model as the player
	var character_path = "res://player/character/armed/Paladin.fbx"
	var character_scene = load(character_path)

	if character_scene:
		_character_model = character_scene.instantiate()
		_character_model.name = "Model"
		add_child(_character_model)

		# Create AnimationPlayer and load animations
		_anim_player = AnimationPlayer.new()
		_anim_player.name = "AnimationPlayer"
		_character_model.add_child(_anim_player)

		# Find skeleton for animation retargeting
		var skeleton = _find_skeleton(_character_model)
		if skeleton:
			_load_animations(skeleton)

		# Play idle by default
		if _anim_player.has_animation("Idle"):
			_anim_player.play("Idle")

		# Apply a different color tint to distinguish from local player
		_apply_remote_player_material()
	else:
		# Fallback: create a simple capsule mesh
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
	# Get skeleton path relative to AnimationPlayer
	var skel_path = _anim_player.get_path_to(skeleton)
	var skel_path_str = str(skel_path)

	# Create a single animation library
	var lib = AnimationLibrary.new()

	for anim_name in ARMED_ANIM_PATHS:
		var anim_path = ARMED_ANIM_PATHS[anim_name]
		var anim_scene = load(anim_path)
		if anim_scene == null:
			continue

		var anim_instance = anim_scene.instantiate()
		var source_anim_player = _find_animation_player(anim_instance)

		if source_anim_player and source_anim_player.get_animation_list().size() > 0:
			var source_anim_name = source_anim_player.get_animation_list()[0]
			var anim = source_anim_player.get_animation(source_anim_name)

			if anim:
				# Clone and add animation
				var new_anim = anim.duplicate()

				# Fix animation paths for our skeleton
				for i in range(new_anim.get_track_count()):
					var track_path = new_anim.track_get_path(i)
					var path_str = str(track_path)

					# Update path to point to our skeleton
					if ":" in path_str:
						var parts = path_str.split(":")
						if parts.size() >= 2:
							var bone_part = parts[-1]
							var new_path = skel_path_str + ":" + bone_part
							new_anim.track_set_path(i, NodePath(new_path))

				lib.add_animation(anim_name, new_anim)

		anim_instance.queue_free()

	_anim_player.add_animation_library("", lib)


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


func _apply_remote_player_material() -> void:
	# Apply a blue-ish tint to remote players to distinguish them
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.8, 1.0)  # Slight blue tint

	_apply_material_recursive(_character_model, material)


func _apply_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		# Don't override, just tint
		# mesh_instance.material_override = material

	for child in node.get_children():
		_apply_material_recursive(child, material)


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

	# Map animation names from player to remote player format
	# The player uses "armed/Idle" format, we just need "Idle"
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
				anim_name = "Attack1"
			STATE_BLOCKING:
				anim_name = "Block"
			STATE_JUMPING:
				anim_name = "Jump"

	# Try to play the animation if it exists
	if _anim_player.has_animation(anim_name):
		if _anim_player.current_animation != anim_name:
			_anim_player.play(anim_name)

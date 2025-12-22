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


func _setup_character_model() -> void:
	# Load the same character model as the player
	var character_path = "res://player/character/armed/Paladin.fbx"
	var character_scene = load(character_path)

	if character_scene:
		_character_model = character_scene.instantiate()
		_character_model.name = "Model"
		add_child(_character_model)

		# Find animation player
		_anim_player = _find_animation_player(_character_model)

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

	var anim_name = "Idle"

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

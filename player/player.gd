class_name Player
extends CharacterBody3D
## Douglass, the Keeper of Balance, walking through the Lands of Balance.
## Third-person style controls with mouse look.
## Uses FBX character model with Mixamo animations.

const MAX_SPEED: float = 5.0
const ACCEL: float = 12.0
const DEACCEL: float = 12.0
const JUMP_VELOCITY: float = 6.0
const MOUSE_SENSITIVITY: float = 0.002
const CAMERA_VERTICAL_LIMIT: float = 85.0  # degrees

# FBX character paths - all Mixamo animations
const CHARACTER_MODEL_PATH: String = "res://player/character/Idle.fbx"
const ANIM_PATHS: Dictionary = {
	"walk": "res://player/character/Walking.fbx",
	"strafe_left": "res://player/character/Walk Strafe Left.fbx",
	"jump": "res://player/character/Unarmed Jump.fbx",
	"turn": "res://player/character/Change Direction.fbx",
	"crouch": "res://player/character/Crouch Turn To Stand.fbx",
	"turn_right": "res://player/character/Right Turn W_ Briefcase.fbx",
	"combat_idle": "res://player/character/Action Idle To Fight Idle.fbx",
}

var camera_rotation := Vector2.ZERO  # x = yaw, y = pitch
var _character_model: Node3D
var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
var moving: bool = false
var strafing_left: bool = false
var strafing_right: bool = false
var is_jumping: bool = false
var _current_anim: StringName = &""

@onready var initial_position := position
@onready var gravity: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity") * \
		ProjectSettings.get_setting("physics/3d/default_gravity_vector")

@onready var _camera_pivot := $CameraPivot as Node3D
@onready var _camera := $CameraPivot/Camera3D as Camera3D


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_create_character()


func _create_character() -> void:
	# Try to load FBX character first
	var success: bool = _try_create_fbx_character()
	if success:
		return

	# Fallback to placeholder
	_create_placeholder_humanoid()


func _try_create_fbx_character() -> bool:
	# Load the character model from FBX
	var character_scene: PackedScene = load(CHARACTER_MODEL_PATH) as PackedScene
	if character_scene == null:
		print("Failed to load character model from: ", CHARACTER_MODEL_PATH)
		return false

	# Instance the character
	var character_instance: Node3D = character_scene.instantiate() as Node3D
	if character_instance == null:
		print("Failed to instantiate character model")
		return false

	# Create a container for the character model
	_character_model = Node3D.new()
	_character_model.name = "CharacterModel"
	add_child(_character_model)

	# Add the character instance to the container
	_character_model.add_child(character_instance)
	character_instance.name = "MixamoCharacter"

	# Check if we need to scale - Mixamo exports at different scales
	# If exported "in meters", scale is 1.0. If in centimeters, scale is 0.01
	var skeleton: Skeleton3D = _find_skeleton(character_instance)
	if skeleton and skeleton.get_bone_count() > 0:
		# Check the height by looking at head bone position
		var hips_idx: int = skeleton.find_bone("mixamorig_Hips")
		if hips_idx >= 0:
			var hips_pos: Vector3 = skeleton.get_bone_global_rest(hips_idx).origin
			# If hips are at ~100, it's in centimeters, scale to 0.01
			# If hips are at ~1, it's in meters, no scaling needed
			if hips_pos.y > 50:
				character_instance.scale = Vector3(0.01, 0.01, 0.01)
			else:
				character_instance.scale = Vector3(1.0, 1.0, 1.0)
	else:
		# Default scale
		character_instance.scale = Vector3(0.01, 0.01, 0.01)

	# Add a material to make the Y Bot visible (it comes with no textures)
	_apply_character_material(character_instance)

	# Find the AnimationPlayer in the imported scene
	_anim_player = _find_animation_player(character_instance)
	if _anim_player == null:
		# Create one if not found
		_anim_player = AnimationPlayer.new()
		_anim_player.name = "AnimationPlayer"
		character_instance.add_child(_anim_player)

	# Load additional animations from other FBX files
	_load_additional_animations()

	# Setup AnimationTree for blend control
	_setup_animation_tree()

	print("FBX character loaded with animations")
	return true


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result: AnimationPlayer = _find_animation_player(child)
		if result != null:
			return result
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var result: Skeleton3D = _find_skeleton(child)
		if result != null:
			return result
	return null


func _print_node_tree(node: Node, depth: int) -> void:
	var indent: String = "  ".repeat(depth)
	var info: String = node.name + " (" + node.get_class() + ")"
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh:
			info += " mesh=" + str(mi.mesh.get_class())
			info += " surfaces=" + str(mi.mesh.get_surface_count())
		else:
			info += " NO MESH"
	print(indent + info)
	for child in node.get_children():
		_print_node_tree(child, depth + 1)


func _apply_character_material(node: Node) -> void:
	# Apply a visible material to all mesh instances (Mixamo Y Bot has no textures)
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		var material := StandardMaterial3D.new()
		# Create a nice character color
		material.albedo_color = Color(0.35, 0.55, 0.75)  # Blue-gray
		material.roughness = 0.7
		material.metallic = 0.0
		# Apply to all surfaces
		for i in range(mi.get_surface_override_material_count()):
			mi.set_surface_override_material(i, material)
		print("Applied material to: ", node.name)

	for child in node.get_children():
		_apply_character_material(child)


func _load_additional_animations() -> void:
	# Animation config: library name -> (animation name, should loop)
	var anim_config: Dictionary = {
		"walk": ["Walking", true],
		"strafe_left": ["StrafeLeft", true],
		"jump": ["Jump", false],
		"turn": ["Turn", false],
		"crouch": ["Crouch", false],
		"turn_right": ["TurnRight", false],
		"combat_idle": ["CombatIdle", true],
	}

	# Load all animations from FBX files
	for lib_name in ANIM_PATHS:
		var fbx_path: String = ANIM_PATHS[lib_name]
		var scene: PackedScene = load(fbx_path) as PackedScene
		if scene == null:
			continue

		var instance: Node3D = scene.instantiate()
		var anim_player_src: AnimationPlayer = _find_animation_player(instance)
		if anim_player_src:
			# Find the animation with actual keyframes (mixamo_com)
			for src_lib_name in anim_player_src.get_animation_library_list():
				var src_lib: AnimationLibrary = anim_player_src.get_animation_library(src_lib_name)
				for src_anim_name in src_lib.get_animation_list():
					var anim: Animation = src_lib.get_animation(src_anim_name)
					var total_keys: int = 0
					for t in range(anim.get_track_count()):
						total_keys += anim.track_get_key_count(t)
					# Only use animations with actual keyframe data (not just T-pose)
					if total_keys > 100:
						var new_anim: Animation = anim.duplicate()
						var config: Array = anim_config[lib_name]
						new_anim.loop_mode = Animation.LOOP_LINEAR if config[1] else Animation.LOOP_NONE
						if not _anim_player.has_animation_library(StringName(lib_name)):
							_anim_player.add_animation_library(StringName(lib_name), AnimationLibrary.new())
						_anim_player.get_animation_library(StringName(lib_name)).add_animation(StringName(config[0]), new_anim)
						print("Loaded animation: ", lib_name, "/", config[0])
						break  # Found the real animation, stop searching
		instance.queue_free()


func _setup_animation_tree() -> void:
	# Find the skeleton
	var skel: Skeleton3D = _find_skeleton(_anim_player.get_parent())
	if skel == null:
		print("ERROR: No skeleton found!")
		return

	# Get the skeleton path relative to the AnimationPlayer's root_node
	var anim_root: Node = _anim_player.get_node(_anim_player.root_node)
	var skel_path: String = str(anim_root.get_path_to(skel))

	# Retarget all animations to use the correct skeleton path and remove root motion
	for lib_name in _anim_player.get_animation_library_list():
		var lib: AnimationLibrary = _anim_player.get_animation_library(lib_name)
		for anim_name in lib.get_animation_list():
			var anim: Animation = lib.get_animation(anim_name)
			var tracks_before: int = anim.get_track_count()
			_retarget_animation(anim, skel_path, skel)
			var tracks_after: int = anim.get_track_count()
			if tracks_before != tracks_after:
				print("Removed root motion from: ", lib_name, "/", anim_name)

	# Set idle animation (mixamo_com) to loop
	if _anim_player.has_animation(&"mixamo_com"):
		var idle_anim: Animation = _anim_player.get_animation(&"mixamo_com")
		idle_anim.loop_mode = Animation.LOOP_LINEAR

	# Start with idle animation
	if _anim_player.has_animation(&"mixamo_com"):
		_anim_player.play(&"mixamo_com")


func _retarget_animation(anim: Animation, target_skeleton_path: String, skeleton: Skeleton3D) -> void:
	# Retarget animation track paths to point to the correct skeleton
	# Also remove root motion from Hips bone (position tracks only)
	var tracks_to_remove: Array[int] = []

	for i in range(anim.get_track_count()):
		var track_path: NodePath = anim.track_get_path(i)
		var path_str: String = str(track_path)

		# Check if this is a bone track (contains a colon for property/bone name)
		var colon_pos: int = path_str.find(":")
		if colon_pos == -1:
			continue

		var bone_name: String = path_str.substr(colon_pos + 1)

		# Remove position tracks from Hips bone to prevent root motion snap-back
		# Check this BEFORE skeleton validation since we want to remove it regardless
		if bone_name == "mixamorig_Hips" and anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
			tracks_to_remove.append(i)
			continue

		# Verify the bone exists in the skeleton
		if skeleton.find_bone(bone_name) == -1:
			continue

		# Only retarget if the path is different
		var new_path: String = target_skeleton_path + ":" + bone_name
		if path_str != new_path:
			anim.track_set_path(i, NodePath(new_path))

	# Remove tracks in reverse order to preserve indices
	tracks_to_remove.reverse()
	for track_idx in tracks_to_remove:
		anim.remove_track(track_idx)


func _play_anim(anim_name: StringName) -> void:
	# Play animation only if it's different from current
	if _anim_player == null:
		return
	if _current_anim == anim_name:
		return
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)
		_current_anim = anim_name


func _update_animation(input_dir: Vector2) -> void:
	if _anim_player == null:
		return

	# Determine the desired animation based on input
	var desired_anim: StringName = &""

	# Jump takes priority (when in air)
	if not is_on_floor():
		if is_jumping and _anim_player.has_animation(&"jump/Jump"):
			desired_anim = &"jump/Jump"
		else:
			# Keep current animation while falling
			return

	# Check for strafe (pure left/right movement without forward/back)
	elif abs(input_dir.x) > 0.5 and abs(input_dir.y) < 0.3:
		if input_dir.x < 0 and _anim_player.has_animation(&"strafe_left/StrafeLeft"):
			desired_anim = &"strafe_left/StrafeLeft"
		elif input_dir.x > 0:
			# Mirror left strafe for right (or use turn animation)
			if _anim_player.has_animation(&"strafe_left/StrafeLeft"):
				desired_anim = &"strafe_left/StrafeLeft"  # TODO: could mirror this
			elif _anim_player.has_animation(&"turn_right/TurnRight"):
				desired_anim = &"turn_right/TurnRight"

	# Walking forward/back (with or without strafe)
	elif input_dir.length() > 0.1:
		if _anim_player.has_animation(&"walk/Walking"):
			desired_anim = &"walk/Walking"

	# Idle - no movement
	else:
		if _anim_player.has_animation(&"mixamo_com"):
			desired_anim = &"mixamo_com"

	# Play the animation if we determined one
	if desired_anim != &"":
		_play_anim(desired_anim)


func _create_placeholder_humanoid() -> void:
	# Create character model container
	_character_model = Node3D.new()
	_character_model.name = "CharacterModel"
	add_child(_character_model)

	# Create a simple humanoid figure using CSG primitives
	var skin_material := StandardMaterial3D.new()
	skin_material.albedo_color = Color(0.9, 0.75, 0.65)
	skin_material.roughness = 0.8

	var shirt_material := StandardMaterial3D.new()
	shirt_material.albedo_color = Color(0.2, 0.35, 0.5)
	shirt_material.roughness = 0.9

	var pants_material := StandardMaterial3D.new()
	pants_material.albedo_color = Color(0.3, 0.25, 0.2)
	pants_material.roughness = 0.85

	var hair_material := StandardMaterial3D.new()
	hair_material.albedo_color = Color(0.25, 0.15, 0.1)
	hair_material.roughness = 0.95

	var boot_material := StandardMaterial3D.new()
	boot_material.albedo_color = Color(0.15, 0.1, 0.05)
	boot_material.roughness = 0.7

	# Head
	var head := CSGSphere3D.new()
	head.radius = 0.12
	head.transform.origin = Vector3(0, 1.6, 0)
	head.material = skin_material
	_character_model.add_child(head)

	# Hair
	var hair := CSGSphere3D.new()
	hair.radius = 0.13
	hair.transform.origin = Vector3(0, 1.65, 0)
	hair.material = hair_material
	_character_model.add_child(hair)

	# Torso
	var torso := CSGCylinder3D.new()
	torso.radius = 0.2
	torso.height = 0.5
	torso.transform.origin = Vector3(0, 1.2, 0)
	torso.material = shirt_material
	_character_model.add_child(torso)

	# Belt
	var belt := CSGCylinder3D.new()
	belt.radius = 0.18
	belt.height = 0.1
	belt.transform.origin = Vector3(0, 0.9, 0)
	belt.material = pants_material
	_character_model.add_child(belt)

	# Arms
	var left_arm := CSGCylinder3D.new()
	left_arm.radius = 0.05
	left_arm.height = 0.5
	left_arm.transform.origin = Vector3(-0.25, 1.15, 0)
	left_arm.material = shirt_material
	_character_model.add_child(left_arm)

	var right_arm := CSGCylinder3D.new()
	right_arm.radius = 0.05
	right_arm.height = 0.5
	right_arm.transform.origin = Vector3(0.25, 1.15, 0)
	right_arm.material = shirt_material
	_character_model.add_child(right_arm)

	# Hands
	var left_hand := CSGSphere3D.new()
	left_hand.radius = 0.05
	left_hand.transform.origin = Vector3(-0.25, 0.85, 0)
	left_hand.material = skin_material
	_character_model.add_child(left_hand)

	var right_hand := CSGSphere3D.new()
	right_hand.radius = 0.05
	right_hand.transform.origin = Vector3(0.25, 0.85, 0)
	right_hand.material = skin_material
	_character_model.add_child(right_hand)

	# Legs
	var left_leg := CSGCylinder3D.new()
	left_leg.radius = 0.07
	left_leg.height = 0.5
	left_leg.transform.origin = Vector3(-0.1, 0.55, 0)
	left_leg.material = pants_material
	_character_model.add_child(left_leg)

	var right_leg := CSGCylinder3D.new()
	right_leg.radius = 0.07
	right_leg.height = 0.5
	right_leg.transform.origin = Vector3(0.1, 0.55, 0)
	right_leg.material = pants_material
	_character_model.add_child(right_leg)

	# Boots
	var left_boot := CSGCylinder3D.new()
	left_boot.radius = 0.08
	left_boot.height = 0.25
	left_boot.transform.origin = Vector3(-0.1, 0.15, 0)
	left_boot.material = boot_material
	_character_model.add_child(left_boot)

	var right_boot := CSGCylinder3D.new()
	right_boot.radius = 0.08
	right_boot.height = 0.25
	right_boot.transform.origin = Vector3(0.1, 0.15, 0)
	right_boot.material = boot_material
	_character_model.add_child(right_boot)

	print("Using placeholder character")


func _input(event: InputEvent) -> void:
	# Quit with Q key
	if event is InputEventKey and event.pressed and event.keycode == KEY_Q:
		get_tree().quit()

	# Toggle mouse capture with Escape
	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_rotation.x -= event.relative.x * MOUSE_SENSITIVITY
		camera_rotation.y -= event.relative.y * MOUSE_SENSITIVITY
		camera_rotation.y = clamp(camera_rotation.y, deg_to_rad(-CAMERA_VERTICAL_LIMIT), deg_to_rad(CAMERA_VERTICAL_LIMIT))

		# Apply rotation to camera pivot
		_camera_pivot.rotation.y = camera_rotation.x
		_camera_pivot.rotation.x = camera_rotation.y


func _physics_process(delta: float) -> void:
	if Input.is_action_pressed(&"reset_position") or global_position.y < -12:
		position = initial_position
		velocity = Vector3.ZERO
		reset_physics_interpolation()

	velocity += gravity * delta

	# Handle jumping
	if is_on_floor():
		if is_jumping:
			is_jumping = false  # Landed
		if Input.is_action_just_pressed(&"jump"):
			velocity.y = JUMP_VELOCITY
			is_jumping = true

	var horizontal_velocity := Vector3(velocity.x, 0, velocity.z)

	# Get movement input
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed(&"move_forward"):
		input_dir.y -= 1
	if Input.is_action_pressed(&"move_back"):
		input_dir.y += 1
	if Input.is_action_pressed(&"move_left"):
		input_dir.x -= 1
	if Input.is_action_pressed(&"move_right"):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	# Convert to world direction based on camera yaw
	var cam_yaw: float = _camera_pivot.rotation.y
	var forward := Vector3.FORWARD.rotated(Vector3.UP, cam_yaw)
	var right := Vector3.RIGHT.rotated(Vector3.UP, cam_yaw)

	var movement_direction := (forward * -input_dir.y + right * input_dir.x).normalized()

	if is_on_floor():
		if movement_direction.length() > 0.1:
			horizontal_velocity = horizontal_velocity.move_toward(movement_direction * MAX_SPEED, ACCEL * delta)
		else:
			horizontal_velocity = horizontal_velocity.move_toward(Vector3.ZERO, DEACCEL * delta)

		# Update character mesh rotation to face movement direction
		if _character_model and horizontal_velocity.length() > 0.1:
			var mesh_target_rotation: float = atan2(horizontal_velocity.x, horizontal_velocity.z)
			var current_rot: float = _character_model.rotation.y
			_character_model.rotation.y = lerp_angle(current_rot, mesh_target_rotation, 10.0 * delta)
	else:
		# Air control
		if movement_direction.length() > 0.1:
			horizontal_velocity += movement_direction * (ACCEL * 0.3 * delta)
			if horizontal_velocity.length() > MAX_SPEED:
				horizontal_velocity = horizontal_velocity.normalized() * MAX_SPEED

	velocity = horizontal_velocity + Vector3.UP * velocity.y

	move_and_slide()

	# Update animation based on movement state
	_update_animation(input_dir)

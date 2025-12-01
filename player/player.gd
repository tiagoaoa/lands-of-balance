class_name Player
extends CharacterBody3D
## Douglass, the Keeper of Balance, walking through the Lands of Balance.
## Third-person style controls with mouse look.
## Uses FBX character models with Mixamo animations.
## Supports armed (Paladin with sword & shield) and unarmed (Y Bot) combat modes.

const MAX_SPEED: float = 5.0
const RUN_SPEED: float = 8.0
const ACCEL: float = 12.0
const DEACCEL: float = 12.0
const JUMP_VELOCITY: float = 6.0
const MOUSE_SENSITIVITY: float = 0.002
const CAMERA_VERTICAL_LIMIT: float = 85.0  # degrees

# Combat mode enum
enum CombatMode { UNARMED, ARMED }

# Character model paths
const UNARMED_CHARACTER_PATH: String = "res://player/character/unarmed/Paladin.fbx"
const ARMED_CHARACTER_PATH: String = "res://player/character/armed/Paladin.fbx"

# Unarmed animations (Paladin without weapons)
const UNARMED_ANIM_PATHS: Dictionary = {
	"idle": "res://player/character/unarmed/Idle.fbx",
	"walk": "res://player/character/unarmed/Walk.fbx",
	"run": "res://player/character/unarmed/Run.fbx",
	"strafe_left": "res://player/character/unarmed/StrafeLeft.fbx",
	"strafe_right": "res://player/character/unarmed/StrafeRight.fbx",
	"jump": "res://player/character/unarmed/Jump.fbx",
	"turn_left": "res://player/character/unarmed/TurnLeft.fbx",
	"turn_right": "res://player/character/unarmed/TurnRight.fbx",
	"attack": "res://player/character/unarmed/Attack.fbx",
	"block": "res://player/character/unarmed/Block.fbx",
	"action_to_idle": "res://player/character/unarmed/ActionIdleToIdle.fbx",
	"idle_to_fight": "res://player/character/unarmed/IdleToFight.fbx",
}

# Armed animations (Paladin with sword & shield)
const ARMED_ANIM_PATHS: Dictionary = {
	"idle": "res://player/character/armed/Idle.fbx",
	"walk": "res://player/character/armed/Walk.fbx",
	"run": "res://player/character/armed/Run.fbx",
	"jump": "res://player/character/armed/Jump.fbx",
	"attack1": "res://player/character/armed/Attack1.fbx",
	"attack2": "res://player/character/armed/Attack2.fbx",
	"block": "res://player/character/armed/Block.fbx",
	"sheath": "res://player/character/armed/Sheath.fbx",
}

var camera_rotation := Vector2.ZERO  # x = yaw, y = pitch
var _character_model: Node3D  # Container for both characters
var _unarmed_character: Node3D
var _armed_character: Node3D
var _unarmed_anim_player: AnimationPlayer
var _armed_anim_player: AnimationPlayer
var _current_anim_player: AnimationPlayer
var moving: bool = false
var is_jumping: bool = false
var is_running: bool = false
var _current_anim: StringName = &""

# Combat state
var combat_mode: CombatMode = CombatMode.UNARMED
var is_attacking: bool = false
var is_blocking: bool = false
var is_sheathing: bool = false
var is_transitioning: bool = false  # For attack/idle transitions
var attack_combo: int = 0
var _attack_cooldown: float = 0.0

@onready var initial_position := position
@onready var gravity: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity") * \
		ProjectSettings.get_setting("physics/3d/default_gravity_vector")

@onready var _camera_pivot := $CameraPivot as Node3D
@onready var _camera := $CameraPivot/Camera3D as Camera3D


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_create_characters()


func _create_characters() -> void:
	# Create container for both character models
	_character_model = Node3D.new()
	_character_model.name = "CharacterModel"
	add_child(_character_model)

	# Load unarmed character (Paladin without weapons)
	_unarmed_character = _load_character(UNARMED_CHARACTER_PATH, "UnarmedCharacter", Color(0.35, 0.55, 0.75))
	if _unarmed_character:
		_character_model.add_child(_unarmed_character)
		_unarmed_anim_player = _find_animation_player(_unarmed_character)
		print("Unarmed AnimationPlayer found: ", _unarmed_anim_player != null)
		if _unarmed_anim_player:
			_unarmed_anim_player.animation_finished.connect(_on_animation_finished)
			_load_animations_for_character(_unarmed_anim_player, UNARMED_ANIM_PATHS, _get_unarmed_config(), "unarmed", _unarmed_character)
		else:
			# Create AnimationPlayer if not found
			print("Creating AnimationPlayer for unarmed character")
			_unarmed_anim_player = AnimationPlayer.new()
			_unarmed_anim_player.name = "AnimationPlayer"
			_unarmed_character.add_child(_unarmed_anim_player)
			_unarmed_anim_player.animation_finished.connect(_on_animation_finished)
			_load_animations_for_character(_unarmed_anim_player, UNARMED_ANIM_PATHS, _get_unarmed_config(), "unarmed", _unarmed_character)

	# Load armed character (Paladin)
	_armed_character = _load_character(ARMED_CHARACTER_PATH, "ArmedCharacter", Color(0.6, 0.5, 0.3))
	if _armed_character:
		_character_model.add_child(_armed_character)
		_armed_character.visible = false  # Start hidden
		_armed_anim_player = _find_animation_player(_armed_character)
		if _armed_anim_player:
			_armed_anim_player.animation_finished.connect(_on_animation_finished)
			_load_animations_for_character(_armed_anim_player, ARMED_ANIM_PATHS, _get_armed_config(), "armed", _armed_character)

	# Set initial animation player
	_current_anim_player = _unarmed_anim_player

	# Play initial idle animation
	if _unarmed_anim_player and _unarmed_anim_player.has_animation(&"unarmed/Idle"):
		_unarmed_anim_player.play(&"unarmed/Idle")
		_current_anim = &"unarmed/Idle"

	print("Characters loaded - Unarmed: ", _unarmed_character != null, ", Armed: ", _armed_character != null)


func _get_unarmed_config() -> Dictionary:
	return {
		"idle": ["Idle", true],
		"walk": ["Walk", true],
		"run": ["Run", true],
		"strafe_left": ["StrafeLeft", true],
		"strafe_right": ["StrafeRight", true],
		"jump": ["Jump", false],
		"turn_left": ["TurnLeft", false],
		"turn_right": ["TurnRight", false],
		"attack": ["Attack", false],
		"block": ["Block", true],
		"action_to_idle": ["ActionToIdle", false],
		"idle_to_fight": ["IdleToFight", false],
	}


func _get_armed_config() -> Dictionary:
	return {
		"idle": ["Idle", true],
		"walk": ["Walk", true],
		"run": ["Run", true],
		"jump": ["Jump", false],
		"attack1": ["Attack1", false],
		"attack2": ["Attack2", false],
		"block": ["Block", true],
		"sheath": ["Sheath", false],
	}


func _load_character(path: String, name: String, fallback_color: Color) -> Node3D:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		print("Failed to load character: ", path)
		return null

	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		print("Failed to instantiate character: ", path)
		return null

	instance.name = name

	# Scale character appropriately
	var skeleton: Skeleton3D = _find_skeleton(instance)
	if skeleton and skeleton.get_bone_count() > 0:
		var hips_idx: int = skeleton.find_bone("mixamorig_Hips")
		if hips_idx >= 0:
			var hips_pos: Vector3 = skeleton.get_bone_global_rest(hips_idx).origin
			if hips_pos.y > 50:
				instance.scale = Vector3(0.01, 0.01, 0.01)
			else:
				instance.scale = Vector3(1.0, 1.0, 1.0)
		else:
			instance.scale = Vector3(0.01, 0.01, 0.01)
	else:
		instance.scale = Vector3(0.01, 0.01, 0.01)

	# Only apply fallback material if character has no textures (like Y Bot)
	# Paladin and other textured characters keep their original materials
	if not _character_has_textures(instance):
		_apply_character_material(instance, fallback_color)

	print("Loaded character: ", name, " from ", path)
	return instance


func _character_has_textures(node: Node) -> bool:
	# Check if any mesh has a material with a texture
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		for i in range(mi.get_surface_override_material_count()):
			var mat: Material = mi.get_surface_override_material(i)
			if mat == null and mi.mesh:
				mat = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var std_mat: StandardMaterial3D = mat as StandardMaterial3D
				if std_mat.albedo_texture != null:
					return true

	for child in node.get_children():
		if _character_has_textures(child):
			return true

	return false


func _load_animations_for_character(anim_player: AnimationPlayer, paths: Dictionary, config: Dictionary, library_prefix: String, character: Node3D) -> void:
	var skeleton: Skeleton3D = _find_skeleton(character)
	if skeleton == null:
		print("ERROR: No skeleton found for character!")
		return

	var anim_root: Node = anim_player.get_node(anim_player.root_node)
	var skel_path: String = str(anim_root.get_path_to(skeleton))
	print("Loading animations for ", library_prefix, " - skeleton path: ", skel_path)

	for anim_key in paths:
		var fbx_path: String = paths[anim_key]
		var scene: PackedScene = load(fbx_path) as PackedScene
		if scene == null:
			print("  Failed to load FBX: ", fbx_path)
			continue

		var instance: Node3D = scene.instantiate()
		var anim_player_src: AnimationPlayer = _find_animation_player(instance)
		if anim_player_src == null:
			print("  No AnimationPlayer in: ", fbx_path)
			instance.queue_free()
			continue

		# Find best animation
		var best_anim: Animation = null
		var best_anim_name: String = ""
		var best_key_count: int = 0

		for src_lib_name in anim_player_src.get_animation_library_list():
			var src_lib: AnimationLibrary = anim_player_src.get_animation_library(src_lib_name)
			for src_anim_name in src_lib.get_animation_list():
				var anim: Animation = src_lib.get_animation(src_anim_name)
				var total_keys: int = 0
				for t in range(anim.get_track_count()):
					total_keys += anim.track_get_key_count(t)
				var keys_per_track: float = float(total_keys) / max(anim.get_track_count(), 1)
				if total_keys > best_key_count and keys_per_track > 1.5:
					best_anim = anim
					best_anim_name = src_anim_name
					best_key_count = total_keys

		if best_anim != null:
			var new_anim: Animation = best_anim.duplicate()
			var anim_config: Array = config.get(anim_key, [anim_key, false])
			new_anim.loop_mode = Animation.LOOP_LINEAR if anim_config[1] else Animation.LOOP_NONE

			# Retarget animation
			_retarget_animation(new_anim, skel_path, skeleton)

			var lib_name: StringName = StringName(library_prefix)
			if not anim_player.has_animation_library(lib_name):
				anim_player.add_animation_library(lib_name, AnimationLibrary.new())
			anim_player.get_animation_library(lib_name).add_animation(StringName(anim_config[0]), new_anim)
			print("  Loaded: ", library_prefix, "/", anim_config[0])

		instance.queue_free()


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


func _apply_character_material(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.7
		material.metallic = 0.0
		for i in range(mi.get_surface_override_material_count()):
			mi.set_surface_override_material(i, material)

	for child in node.get_children():
		_apply_character_material(child, color)


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

		# Verify bone exists
		if skeleton.find_bone(bone_name) == -1:
			var alt_bone_name: String = bone_name.replace("mixamorig:", "mixamorig_")
			if skeleton.find_bone(alt_bone_name) == -1:
				continue
			bone_name = alt_bone_name

		var new_path: String = target_skeleton_path + ":" + bone_name
		if path_str != new_path:
			anim.track_set_path(i, NodePath(new_path))

	tracks_to_remove.reverse()
	for track_idx in tracks_to_remove:
		anim.remove_track(track_idx)


func _on_animation_finished(anim_name: StringName) -> void:
	if is_attacking:
		is_attacking = false
		_attack_cooldown = 0.2
		# Play transition from attack to idle (unarmed mode only)
		if combat_mode == CombatMode.UNARMED and _current_anim_player.has_animation(&"unarmed/ActionToIdle"):
			is_transitioning = true
			_current_anim_player.play(&"unarmed/ActionToIdle")
			_current_anim = &"unarmed/ActionToIdle"
	if is_transitioning:
		# Transition animation finished
		if anim_name == &"unarmed/ActionToIdle" or anim_name == &"unarmed/IdleToFight":
			is_transitioning = false
	if is_sheathing:
		is_sheathing = false


func _play_anim(anim_name: StringName) -> void:
	if _current_anim_player == null:
		return
	if _current_anim == anim_name:
		return
	if _current_anim_player.has_animation(anim_name):
		_current_anim_player.play(anim_name)
		_current_anim = anim_name


func _get_current_mode_prefix() -> String:
	return "armed" if combat_mode == CombatMode.ARMED else "unarmed"


func _update_animation(input_dir: Vector2) -> void:
	if _current_anim_player == null:
		return

	if is_attacking or is_sheathing or is_transitioning:
		return

	var prefix: String = _get_current_mode_prefix()
	var desired_anim: StringName = &""

	# Jump takes priority
	if not is_on_floor():
		if is_jumping:
			var jump_anim: StringName = StringName(prefix + "/Jump")
			if _current_anim_player.has_animation(jump_anim):
				desired_anim = jump_anim
		if desired_anim == &"":
			return

	# Blocking (both modes - shield in armed, center block in unarmed)
	elif is_blocking:
		var block_anim: StringName = StringName(prefix + "/Block")
		if _current_anim_player.has_animation(block_anim):
			desired_anim = block_anim

	# Strafe
	elif abs(input_dir.x) > 0.5 and abs(input_dir.y) < 0.3:
		var strafe_dir: String = "StrafeLeft" if input_dir.x < 0 else "StrafeRight"
		var strafe_anim: StringName = StringName(prefix + "/" + strafe_dir)
		if _current_anim_player.has_animation(strafe_anim):
			desired_anim = strafe_anim
		else:
			# Fallback to left strafe or walk
			var fallback_strafe: StringName = StringName(prefix + "/StrafeLeft")
			if _current_anim_player.has_animation(fallback_strafe):
				desired_anim = fallback_strafe
			else:
				var walk_anim: StringName = StringName(prefix + "/Walk")
				if _current_anim_player.has_animation(walk_anim):
					desired_anim = walk_anim

	# Running
	elif is_running and input_dir.length() > 0.1:
		var run_anim: StringName = StringName(prefix + "/Run")
		if _current_anim_player.has_animation(run_anim):
			desired_anim = run_anim
		else:
			var walk_anim: StringName = StringName(prefix + "/Walk")
			if _current_anim_player.has_animation(walk_anim):
				desired_anim = walk_anim

	# Walking
	elif input_dir.length() > 0.1:
		var walk_anim: StringName = StringName(prefix + "/Walk")
		if _current_anim_player.has_animation(walk_anim):
			desired_anim = walk_anim

	# Idle
	else:
		var idle_anim: StringName = StringName(prefix + "/Idle")
		if _current_anim_player.has_animation(idle_anim):
			desired_anim = idle_anim

	if desired_anim != &"":
		_play_anim(desired_anim)


func _toggle_combat_mode() -> void:
	if is_sheathing:
		return

	if combat_mode == CombatMode.UNARMED:
		# Switch to armed mode
		combat_mode = CombatMode.ARMED
		_unarmed_character.visible = false
		_armed_character.visible = true
		_current_anim_player = _armed_anim_player
		_current_anim = &""

		# Play idle animation
		if _armed_anim_player.has_animation(&"armed/Idle"):
			_armed_anim_player.play(&"armed/Idle")
			_current_anim = &"armed/Idle"

		print("Switched to ARMED mode (Paladin)")
	else:
		# Switch to unarmed mode
		combat_mode = CombatMode.UNARMED
		_armed_character.visible = false
		_unarmed_character.visible = true
		_current_anim_player = _unarmed_anim_player
		_current_anim = &""

		# Play idle animation
		if _unarmed_anim_player.has_animation(&"unarmed/Idle"):
			_unarmed_anim_player.play(&"unarmed/Idle")
			_current_anim = &"unarmed/Idle"

		print("Switched to UNARMED mode (Paladin)")


func _do_attack() -> void:
	if is_attacking or _attack_cooldown > 0:
		return

	is_attacking = true

	if combat_mode == CombatMode.ARMED:
		attack_combo = (attack_combo + 1) % 2
		var attack_anim: StringName = &"armed/Attack1" if attack_combo == 0 else &"armed/Attack2"
		if _current_anim_player.has_animation(attack_anim):
			_current_anim_player.play(attack_anim)
			_current_anim = attack_anim
		else:
			is_attacking = false
	else:
		# Unarmed boxing attack - play transition first if coming from idle
		if _current_anim == &"unarmed/Idle" and _current_anim_player.has_animation(&"unarmed/IdleToFight"):
			# Play idle to fight transition, then queue attack
			_current_anim_player.play(&"unarmed/IdleToFight")
			_current_anim_player.queue(&"unarmed/Attack")
			_current_anim = &"unarmed/IdleToFight"
		elif _current_anim_player.has_animation(&"unarmed/Attack"):
			_current_anim_player.play(&"unarmed/Attack")
			_current_anim = &"unarmed/Attack"
		else:
			is_attacking = false


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

	# Toggle combat mode with Tab or middle mouse button
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_toggle_combat_mode()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		_toggle_combat_mode()

	# Attack with left mouse button or F key
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_do_attack()
	if event is InputEventKey and event.pressed and event.keycode == KEY_F:
		_do_attack()

	# Block with right mouse button (armed mode)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			is_blocking = event.pressed

	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_rotation.x -= event.relative.x * MOUSE_SENSITIVITY
		camera_rotation.y -= event.relative.y * MOUSE_SENSITIVITY
		camera_rotation.y = clamp(camera_rotation.y, deg_to_rad(-CAMERA_VERTICAL_LIMIT), deg_to_rad(CAMERA_VERTICAL_LIMIT))

		_camera_pivot.rotation.y = camera_rotation.x
		_camera_pivot.rotation.x = camera_rotation.y


func _physics_process(delta: float) -> void:
	if _attack_cooldown > 0:
		_attack_cooldown -= delta

	if Input.is_action_pressed(&"reset_position") or global_position.y < -12:
		position = initial_position
		velocity = Vector3.ZERO
		reset_physics_interpolation()

	velocity += gravity * delta

	# Handle jumping
	if is_on_floor():
		if is_jumping:
			is_jumping = false
		if Input.is_action_just_pressed(&"jump") and not is_attacking:
			velocity.y = JUMP_VELOCITY
			is_jumping = true

	# Check for running (Shift key)
	is_running = Input.is_action_pressed(&"run") if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else false

	var current_max_speed: float = RUN_SPEED if is_running else MAX_SPEED
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

	# Reduce movement speed while attacking
	if is_attacking:
		input_dir *= 0.3

	# Convert to world direction based on camera yaw
	var cam_yaw: float = _camera_pivot.rotation.y
	var forward := Vector3.FORWARD.rotated(Vector3.UP, cam_yaw)
	var right := Vector3.RIGHT.rotated(Vector3.UP, cam_yaw)

	var movement_direction := (forward * -input_dir.y + right * input_dir.x).normalized()

	if is_on_floor():
		if movement_direction.length() > 0.1:
			horizontal_velocity = horizontal_velocity.move_toward(movement_direction * current_max_speed, ACCEL * delta)
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
			if horizontal_velocity.length() > current_max_speed:
				horizontal_velocity = horizontal_velocity.normalized() * current_max_speed

	velocity = horizontal_velocity + Vector3.UP * velocity.y

	move_and_slide()

	# Update animation based on movement state
	_update_animation(input_dir)

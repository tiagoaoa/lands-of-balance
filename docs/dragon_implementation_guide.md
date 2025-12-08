# Dragon Implementation Guide for Godot 4.x

Complete guide for implementing an animated dragon from the Elder Scrolls Blades model in Godot 4.x with patrol behavior, landing, and attacks.

---

## 1. Asset Download and Import Steps

### 1.1 Download the Dragon Model
1. Visit: https://sketchfab.com/3d-models/the-elder-scrolls-blades-ancient-dragon-67441fe2ce9d4d028e5370faaf4c4b14
2. Download in **GLTF/GLB format** (best compatibility with Godot)
3. Place the file in your project's `res://assets/dragon.glb`

### 1.2 Import Settings
Godot auto-imports GLB files. To customize:
1. Select `dragon.glb` in FileSystem
2. Click "Import" tab
3. Recommended settings:
   - **Meshes > Light Baking**: Disabled (for dynamic lighting)
   - **Animation > Import**: Enabled
   - **Animation > FPS**: 30
   - **Skeleton > Retarget**: Keep original
4. Click "Reimport"

### 1.3 Model Structure (Elder Scrolls Blades Dragon)
The imported model contains:
- **Skeleton3D** with 84 bones including wings, neck, tail, legs
- **AnimationPlayer** with 35+ animations:
  - `Dragon_Ancient_Patrol_Idle` - Ground idle
  - `Dragon_Ancient_Idle_FlyTransition` - Transition to flight
  - `Dragon_Ancient_Attack_PowerAttack` - Primary attack
  - `Dragon_Ancient_Attack_Breath` - Fire breath
  - Various dialogue, recoil, and stagger animations

---

## 2. Scene/Node Setup

### 2.1 Dragon Node Structure
```
Dragon (CharacterBody3D)
├── DragonModel (imported GLB instance)
│   ├── Skeleton3D
│   │   └── MeshInstance3D (dragon mesh)
│   └── AnimationPlayer
└── CollisionShape3D (ConvexPolygonShape3D)
```

### 2.2 Adding Dragon to Your Scene
In your main scene (e.g., `lands_of_balance.tscn`):

```gdscript
[node name="Dragon" type="CharacterBody3D" parent="."]
script = ExtResource("path_to_dragon.gd")
patrol_radius = 15.0
patrol_height = 8.0
patrol_speed = 5.0
landing_spot = Vector3(0, 50, 0)  # Top of hill
attack_range = 15.0
detection_range = 30.0
```

### 2.3 Collision Layers
- **Layer 2**: Enemies (Dragon is on this layer)
- **Mask 1**: World/Player (Dragon collides with these)

---

## 3. GDScript Code

### 3.1 Main Dragon Controller (`dragon.gd`)

```gdscript
class_name Dragon
extends CharacterBody3D

## Ancient Dragon that patrols the map flying, lands on hills, and attacks nearby players

const DragonWingFlapClass := preload("res://enemies/dragon_wing_flap.gd")

enum DragonState { PATROL, FLYING_TO_LAND, LANDING, WAIT, TAKING_OFF, ATTACKING }

signal lap_completed(lap_number: int)
signal state_changed(new_state: DragonState)

# Patrol settings
@export var patrol_radius: float = 50.0  # 100x100 unit area (radius = 50)
@export var patrol_height: float = 10.0  # Low height for visibility (5-15 units)
@export var patrol_speed: float = 8.0   # Flying speed
@export var laps_before_landing: int = 2  # Land after 2 laps
@export var wait_time: float = 5.0       # Seconds to wait when landed

# Landing spot (top of main hill)
@export var landing_spot: Vector3 = Vector3(0, 50, 0)

# Combat settings
@export var attack_range: float = 25.0
@export var detection_range: float = 50.0

# State machine
var state: DragonState = DragonState.PATROL:
	set(value):
		state = value
		state_changed.emit(state)

var patrol_angle: float = 0.0
var patrol_center: Vector3 = Vector3.ZERO
var laps_completed: int = 0
var wait_timer: float = 0.0
var target_player: Node3D = null

# Components
var _model: Node3D
var _anim_player: AnimationPlayer
var _path: Path3D
var _path_follow: PathFollow3D

# Animation names
var anim_fly: StringName = &""
var anim_idle: StringName = &""
var anim_attack: StringName = &""
var anim_land: StringName = &""
var anim_takeoff: StringName = &""

@onready var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
	_setup_dragon_model()
	_setup_collision()
	_setup_patrol_path()

	# Initial position
	patrol_center = Vector3(0, 0, 10)
	position = _get_patrol_position()

	await get_tree().process_frame
	_find_player()

	print("Dragon ready! State: PATROL")


func _setup_dragon_model() -> void:
	var dragon_scene: PackedScene = load("res://assets/dragon.glb") as PackedScene
	if dragon_scene == null:
		push_error("Dragon: Failed to load dragon.glb")
		return

	_model = dragon_scene.instantiate()
	_model.name = "DragonModel"
	add_child(_model)

	# Scale: Elder Scrolls Blades dragons are large
	_model.scale = Vector3(0.5, 0.5, 0.5)

	# Find AnimationPlayer and setup animations
	_anim_player = _find_animation_player(_model)
	if _anim_player:
		_anim_player.animation_finished.connect(_on_animation_finished)
		DragonWingFlapClass.add_to_animation_player(_anim_player, &"WingFlap")
		_detect_animations()


func _setup_collision() -> void:
	var existing := get_node_or_null("CollisionShape3D")
	if existing:
		return

	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"

	# ConvexPolygonShape3D for realistic collision
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([
		# Head
		Vector3(0.0, 1.0, 2.5),
		Vector3(-0.4, 0.8, 2.0),
		Vector3(0.4, 0.8, 2.0),
		Vector3(0.0, 1.5, 1.5),
		# Body
		Vector3(-1.0, 0.5, 0.0),
		Vector3(1.0, 0.5, 0.0),
		Vector3(-1.2, 1.5, 0.0),
		Vector3(1.2, 1.5, 0.0),
		Vector3(0.0, 2.0, 0.0),
		# Wings
		Vector3(-2.5, 1.0, -0.5),
		Vector3(2.5, 1.0, -0.5),
		# Rear
		Vector3(-0.8, 0.5, -1.5),
		Vector3(0.8, 0.5, -1.5),
		Vector3(-0.6, 1.2, -1.5),
		Vector3(0.6, 1.2, -1.5),
		# Tail
		Vector3(0.0, 0.8, -2.5),
	])

	collision.shape = shape
	collision.position = Vector3(0, 0.5, 0)
	add_child(collision)

	collision_layer = 2  # Enemy layer
	collision_mask = 1   # World layer


func _setup_patrol_path() -> void:
	# Create Path3D for smooth curved flight
	_path = Path3D.new()
	_path.name = "PatrolPath"
	add_child(_path)

	# Create oval/circular patrol curve
	var curve := Curve3D.new()
	var segments := 32

	for i in range(segments + 1):
		var angle := (float(i) / segments) * TAU
		var x := cos(angle) * patrol_radius
		var z := sin(angle) * patrol_radius * 0.5  # Oval shape
		var y := patrol_height + sin(angle * 2) * 2.0  # Slight height variation
		curve.add_point(Vector3(x, y, z))

	_path.curve = curve

	# PathFollow3D for smooth movement
	_path_follow = PathFollow3D.new()
	_path_follow.name = "PathFollow"
	_path_follow.loop = true
	_path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	_path.add_child(_path_follow)


func _physics_process(delta: float) -> void:
	match state:
		DragonState.PATROL:
			_process_patrol(delta)
		DragonState.FLYING_TO_LAND:
			_process_flying_to_land(delta)
		DragonState.LANDING:
			_process_landing(delta)
		DragonState.WAIT:
			_process_wait(delta)
		DragonState.TAKING_OFF:
			_process_takeoff(delta)
		DragonState.ATTACKING:
			_process_attacking(delta)

	move_and_slide()


func _process_patrol(delta: float) -> void:
	_play_animation(anim_fly, true)

	# Move along patrol path
	patrol_angle += (patrol_speed / patrol_radius) * delta

	# Check lap completion
	if patrol_angle >= TAU:
		patrol_angle -= TAU
		laps_completed += 1
		lap_completed.emit(laps_completed)
		print("Dragon completed lap ", laps_completed)

		if laps_completed >= laps_before_landing:
			laps_completed = 0
			state = DragonState.FLYING_TO_LAND
			return

	# Move towards patrol position
	var target_pos := _get_patrol_position()
	var direction := (target_pos - position).normalized()
	velocity = direction * patrol_speed

	_face_direction(direction, delta)


func _process_flying_to_land(delta: float) -> void:
	_play_animation(anim_fly, true)

	var target := landing_spot + Vector3(0, 5, 0)  # Approach from above
	var direction := (target - position).normalized()
	var dist := position.distance_to(target)

	velocity = direction * patrol_speed
	_face_direction(direction, delta)

	if dist < 3.0:
		state = DragonState.LANDING
		if anim_land != &"":
			_play_animation(anim_land, false)


func _process_landing(delta: float) -> void:
	var target := landing_spot
	var direction := (target - position).normalized()
	var dist := position.distance_to(target)

	var speed := clampf(dist * 0.5, 1.0, 5.0)
	velocity = direction * speed
	_face_direction(direction, delta)

	if dist < 1.0:
		position = target
		velocity = Vector3.ZERO
		state = DragonState.WAIT
		wait_timer = 0.0
		_play_animation(anim_idle, true)
		print("Dragon landed, waiting for ", wait_time, " seconds")


func _process_wait(delta: float) -> void:
	velocity = Vector3.ZERO

	if not is_on_floor():
		velocity.y -= gravity * delta

	wait_timer += delta

	# Check for player attack opportunity
	if target_player and is_instance_valid(target_player):
		var dist := position.distance_to(target_player.global_position)
		if dist < attack_range:
			state = DragonState.ATTACKING
			return

	# Wait complete, take off
	if wait_timer >= wait_time:
		state = DragonState.TAKING_OFF
		print("Wait complete, taking off")
		if anim_takeoff != &"":
			_play_animation(anim_takeoff, false)


func _process_takeoff(delta: float) -> void:
	velocity = Vector3(0, 8.0, 0)

	if position.y >= patrol_height:
		state = DragonState.PATROL
		patrol_angle = 0.0
		print("Dragon resuming patrol")


func _process_attacking(delta: float) -> void:
	velocity = Vector3.ZERO

	if target_player and is_instance_valid(target_player):
		var dir := (target_player.global_position - position).normalized()
		_face_direction(dir, delta)


func _face_direction(direction: Vector3, delta: float) -> void:
	if _model and direction.length() > 0.1:
		var target_rot := atan2(direction.x, direction.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_rot, 5.0 * delta)


func _get_patrol_position() -> Vector3:
	var x := patrol_center.x + cos(patrol_angle) * patrol_radius
	var z := patrol_center.z + sin(patrol_angle) * patrol_radius * 0.5
	var y := patrol_height + sin(patrol_angle * 2) * 2.0
	return Vector3(x, y, z)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_animation_player(child)
		if result:
			return result
	return null


func _detect_animations() -> void:
	if not _anim_player:
		return

	var anims := _anim_player.get_animation_list()

	# Procedural wing flap for flying
	if _anim_player.has_animation(&"WingFlap"):
		anim_fly = &"WingFlap"

	for anim_name in anims:
		var lower := String(anim_name).to_lower()
		if "patrol_idle" in lower:
			anim_idle = anim_name
		elif "idle" in lower and anim_idle == &"":
			anim_idle = anim_name
		elif "powerattack" in lower:
			anim_attack = anim_name
		elif "attack" in lower and anim_attack == &"":
			anim_attack = anim_name
		elif "land" in lower and "take" not in lower:
			anim_land = anim_name
		elif "takeoff" in lower or "take_off" in lower:
			anim_takeoff = anim_name


func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		target_player = players[0]
	else:
		target_player = get_tree().root.find_child("Player", true, false)


func _play_animation(anim_name: StringName, _loop: bool = false) -> void:
	if not _anim_player or anim_name == &"":
		return
	if _anim_player.current_animation == anim_name:
		return
	if _anim_player.has_animation(anim_name):
		_anim_player.play(anim_name)


func _on_animation_finished(anim_name: StringName) -> void:
	match state:
		DragonState.ATTACKING:
			if target_player and is_instance_valid(target_player):
				var dist := position.distance_to(target_player.global_position)
				if dist < attack_range:
					_play_animation(anim_attack, false)
				else:
					state = DragonState.WAIT
			else:
				state = DragonState.WAIT

		DragonState.LANDING:
			state = DragonState.WAIT
			_play_animation(anim_idle, true)

		DragonState.TAKING_OFF:
			state = DragonState.PATROL
```

### 3.2 Procedural Wing Flap Animation (`dragon_wing_flap.gd`)

```gdscript
class_name DragonWingFlap
extends RefCounted

## Creates procedural wing flapping animation for the dragon

const SKELETON_PATH := "Sketchfab_model/Dragon_Ancient_Skeleton_fbx/Object_2/RootNode/Dragon_Ancient_Skeleton/NPC /NPC Root [Root]/Object_9/Skeleton3D"

const WING_BONES := {
	"L_UpArm1": "NPC LUpArm1_025",
	"L_UpArm2": "NPC LUpArm2_026",
	"L_Forearm1": "NPC LForearm1_028",
	"L_Hand": "NPC LHand_030",
	"R_UpArm1": "NPC RUpArm1_059",
	"R_UpArm2": "NPC RUpArm2_060",
	"R_Forearm1": "NPC RForearm1_062",
	"R_Hand": "NPC RHand_064",
}

const NECK_BONES := {
	"Neck1": "NPC Neck1_040",
	"Neck2": "NPC Neck2_041",
	"Neck3": "NPC Neck3_042",
	"Head": "NPC Head_046",
}


static func create_wing_flap_animation(duration: float = 1.0) -> Animation:
	var anim := Animation.new()
	anim.length = duration
	anim.loop_mode = Animation.LOOP_LINEAR

	var downstroke := duration * 0.4

	# Wing bones - vertical flapping
	_add_wing_track(anim, "L_UpArm1", duration, downstroke, 45, -35)
	_add_wing_track(anim, "L_Forearm1", duration, downstroke, 25, -20)
	_add_wing_track(anim, "L_Hand", duration, downstroke, 30, -25)
	_add_wing_track(anim, "R_UpArm1", duration, downstroke, 45, -35)
	_add_wing_track(anim, "R_Forearm1", duration, downstroke, 25, -20)
	_add_wing_track(anim, "R_Hand", duration, downstroke, 30, -25)

	# Head compensation to look forward
	_add_head_track(anim, duration, downstroke)

	return anim


static func _add_wing_track(anim: Animation, bone_key: String, duration: float,
		downstroke: float, up_angle: float, down_angle: float) -> void:
	var bone_name: String = WING_BONES.get(bone_key, "")
	if bone_name == "":
		return

	var track_path := SKELETON_PATH + ":" + bone_name
	var idx := anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(idx, track_path)
	anim.track_set_interpolation_type(idx, Animation.INTERPOLATION_CUBIC)

	anim.rotation_track_insert_key(idx, 0.0,
		Quaternion.from_euler(Vector3(deg_to_rad(up_angle), 0, 0)))
	anim.rotation_track_insert_key(idx, downstroke,
		Quaternion.from_euler(Vector3(deg_to_rad(down_angle), 0, 0)))
	anim.rotation_track_insert_key(idx, duration,
		Quaternion.from_euler(Vector3(deg_to_rad(up_angle), 0, 0)))


static func _add_head_track(anim: Animation, duration: float, downstroke: float) -> void:
	# Pitch head up to look forward (compensate for model default pose)
	var offset := -25.0

	for bone_key in NECK_BONES:
		var bone_name: String = NECK_BONES[bone_key]
		var track_path := SKELETON_PATH + ":" + bone_name
		var idx := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(idx, track_path)

		var pitch := offset * 0.2  # Distribute across neck segments
		anim.rotation_track_insert_key(idx, 0.0,
			Quaternion.from_euler(Vector3(deg_to_rad(pitch), 0, 0)))
		anim.rotation_track_insert_key(idx, duration,
			Quaternion.from_euler(Vector3(deg_to_rad(pitch), 0, 0)))


static func add_to_animation_player(anim_player: AnimationPlayer,
		anim_name: StringName = &"WingFlap") -> void:
	if not anim_player:
		return

	var anim := create_wing_flap_animation(1.0)

	var lib_name := &""
	var lib: AnimationLibrary
	if anim_player.has_animation_library(lib_name):
		lib = anim_player.get_animation_library(lib_name)
	else:
		lib = AnimationLibrary.new()
		anim_player.add_animation_library(lib_name, lib)

	if lib.has_animation(anim_name):
		lib.remove_animation(anim_name)
	lib.add_animation(anim_name, anim)

	print("DragonWingFlap: Added '%s' animation" % anim_name)
```

---

## 4. Troubleshooting Tips

### 4.1 Model Issues

**Problem**: Dragon not visible
- Check scale (default may be too small/large)
- Verify position is within camera view
- Check if materials imported correctly

**Problem**: Dragon facing wrong direction
- Adjust `_model.rotation_degrees.y` in `_setup_dragon_model()`
- The model may need 180° rotation

**Problem**: Head looking down
- The wing flap animation includes neck/head pitch correction
- Adjust `head_pitch_offset` in `dragon_wing_flap.gd` (default: -25°)

### 4.2 Animation Issues

**Problem**: No animations playing
- Verify AnimationPlayer is found: check console for "AnimationPlayer found"
- Ensure animation names match (case-sensitive)
- Check skeleton path matches your model

**Problem**: Animations jerky/broken
- Increase interpolation smoothness
- Check animation FPS matches import settings
- Verify bone names in `WING_BONES` dictionary

### 4.3 Collision Issues

**Problem**: "This node has no shape" warning
- The script creates collision at runtime; warning is expected in editor
- To silence: add CollisionShape3D as child in scene

**Problem**: Dragon clipping through terrain
- Increase collision shape size
- Adjust `collision.position` offset
- Use ConcavePolygonShape3D for more precise collision (slower)

### 4.4 Patrol/Path Issues

**Problem**: Dragon not following path smoothly
- Increase `patrol_speed` or decrease `patrol_radius`
- Check Path3D curve has enough points
- Verify PathFollow3D.loop = true

**Problem**: Dragon not landing correctly
- Verify `landing_spot` coordinates match hill top
- Increase landing distance check threshold
- Check for physics layer conflicts

### 4.5 Performance Tips

1. Use ConvexPolygonShape3D (not ConcavePolygonShape3D) for moving objects
2. Limit bone animation tracks to essential bones
3. Use AnimationTree for complex blending instead of manual transitions
4. Set appropriate LOD distances for large models

---

## 5. Integration Checklist

- [ ] Dragon.glb in `res://assets/`
- [ ] dragon.gd in `res://enemies/`
- [ ] dragon_wing_flap.gd in `res://enemies/`
- [ ] Dragon node added to main scene
- [ ] Export variables configured (patrol_radius, landing_spot, etc.)
- [ ] Player node has "player" group for detection
- [ ] Collision layers configured (dragon: layer 2, world: layer 1)
- [ ] Hill/landing spot coordinates set correctly

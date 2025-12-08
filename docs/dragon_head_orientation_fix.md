# Dragon Head-Down Orientation Fix Guide

Complete troubleshooting and fix guide for the Elder Scrolls Blades dragon model's head-down orientation issue in Godot 4.x.

---

## 1. Diagnosis Steps

### 1.1 Identify the Problem
The dragon flies with its head pointing down instead of forward. This can be caused by:

1. **Model Default Pose**: GLTF models from Sketchfab often have non-standard orientations
2. **Skeleton Bind Pose**: The dragon's neck/head bones are rotated down in the bind pose
3. **Animation Override**: The flying animation may not correct the head position
4. **GLTF Forward Direction**: GLTF uses +Z forward, Godot uses -Z forward

### 1.2 Check Model Orientation
```gdscript
# In _ready() or a debug function:
print("Model rotation: ", _model.rotation_degrees)
print("Model scale: ", _model.scale)

# Check skeleton bone poses
var skeleton = _find_skeleton(_model)
if skeleton:
    for i in skeleton.get_bone_count():
        var name = skeleton.get_bone_name(i)
        if "neck" in name.to_lower() or "head" in name.to_lower():
            var pose = skeleton.get_bone_pose_rotation(i)
            print("Bone %s rotation: %s" % [name, pose.get_euler()])
```

### 1.3 Quantify the Correction Needed
The Elder Scrolls Blades Ancient Dragon model has its head pitched down approximately **60-70 degrees** in the default bind pose. This requires distributing correction across the neck chain for natural appearance.

---

## 2. Scene Fixes

### 2.1 Scene Hierarchy
```
Stage (Node3D)
├── Dragon (CharacterBody3D)
│   ├── DragonModel (imported GLB instance)
│   │   ├── Sketchfab_model
│   │   │   └── Dragon_Ancient_Skeleton_fbx
│   │   │       └── Skeleton3D (84 bones)
│   │   │           └── MeshInstance3D
│   │   └── AnimationPlayer (35+ animations)
│   └── CollisionShape3D (ConvexPolygonShape3D)
├── Player (CharacterBody3D)
└── TheHills (StaticBody3D)
```

### 2.2 Model Import Settings
1. Select `dragon.glb` in FileSystem
2. Click "Import" tab
3. Verify settings:
   - **Meshes > Light Baking**: Disabled
   - **Animation > Import**: Enabled
   - **Skeleton > Bone Renaming**: None (keep original names)
4. Click "Reimport"

### 2.3 GLTF Orientation Fix (if needed)
If the model faces the wrong direction overall:
```gdscript
# In _setup_dragon_model():
_model.rotation_degrees.y = 180  # Flip to face -Z (Godot forward)
```

---

## 3. Updated GDScript Code

### 3.1 Dragon Controller with Banking (`dragon.gd`)

Key changes:
- Added banking on turns for natural flight
- Smooth orientation interpolation
- Pitch adjustment based on vertical movement
- State-based orientation handling

```gdscript
# Orientation tracking for smooth banking
var _last_direction: Vector3 = Vector3.FORWARD
var _current_bank_angle: float = 0.0

func _face_direction(direction: Vector3, delta: float, enable_banking: bool = true) -> void:
    ## Orient dragon to face direction with optional banking on turns
    if not _model or direction.length_squared() < 0.01:
        return

    var dir_normalized := direction.normalized()

    # Calculate yaw (Y-axis rotation) to face movement direction
    var target_yaw := atan2(dir_normalized.x, dir_normalized.z)

    # Calculate banking based on turn rate (change in direction)
    var bank_angle := 0.0
    if enable_banking and state == DragonState.PATROL:
        # Compute angular velocity (how fast we're turning)
        var cross := _last_direction.cross(dir_normalized)
        var turn_rate := cross.y  # Positive = turning right, Negative = turning left

        # Bank into the turn (negative roll for right turn, positive for left)
        var max_bank := deg_to_rad(25.0)  # Maximum bank angle
        bank_angle = clampf(-turn_rate * 15.0, -max_bank, max_bank)

        # Smooth the bank angle
        _current_bank_angle = lerp(_current_bank_angle, bank_angle, 3.0 * delta)
    else:
        # No banking when not in patrol
        _current_bank_angle = lerp(_current_bank_angle, 0.0, 5.0 * delta)

    # Calculate slight pitch based on vertical movement
    var pitch := 0.0
    if state == DragonState.PATROL or state == DragonState.FLYING_TO_LAND:
        pitch = clampf(-dir_normalized.y * 0.3, deg_to_rad(-15.0), deg_to_rad(15.0))

    # Build target rotation using euler angles
    var target_euler := Vector3(pitch, target_yaw, _current_bank_angle)

    # Smoothly interpolate rotation
    _model.rotation.x = lerp_angle(_model.rotation.x, target_euler.x, 5.0 * delta)
    _model.rotation.y = lerp_angle(_model.rotation.y, target_euler.y, 5.0 * delta)
    _model.rotation.z = lerp_angle(_model.rotation.z, target_euler.z, 5.0 * delta)

    # Store direction for next frame's turn rate calculation
    _last_direction = dir_normalized
```

---

## 4. Animation Fixes

### 4.1 Procedural Neck/Head Correction

The key fix is in `dragon_wing_flap.gd`. The neck chain has 5 segments plus the head. Each segment needs to pitch up to correct the default pose.

**Total correction needed: ~68 degrees**
- 5 neck segments × 12° each = 60°
- Head bone = 8°
- Extra upward bias = 3° (for heroic flight pose)

```gdscript
static func _add_neck_head_bob(anim: Animation, duration: float, downstroke_end: float, intensity: float) -> void:
    ## Neck/head animation with pose correction
    ## Elder Scrolls Blades dragon has head ~60-70° down in default pose

    var t0 := 0.0
    var t1 := downstroke_end
    var t2 := duration

    var neck_intensity := intensity * 0.25

    # Correction values (negative X = pitch up)
    var neck_pitch_per_segment := -12.0  # Each neck segment pitches up 12°
    var head_pitch := -8.0  # Head adds final 8°
    var upward_bias := -3.0  # Extra upward tilt for majestic look

    var neck_delay := duration * 0.025

    # Neck1 (base) - includes upward bias
    _add_rotation_track(anim, "Neck1",
        [t0, t1, t2],
        [
            Quaternion.from_euler(Vector3(deg_to_rad(neck_pitch_per_segment + upward_bias + -3 * neck_intensity), 0, 0)),
            Quaternion.from_euler(Vector3(deg_to_rad(neck_pitch_per_segment + upward_bias + 4 * neck_intensity), 0, 0)),
            Quaternion.from_euler(Vector3(deg_to_rad(neck_pitch_per_segment + upward_bias + -3 * neck_intensity), 0, 0)),
        ])

    # Neck2-5 (each with 12° correction)
    for i in range(2, 6):
        var bone_name := "Neck" + str(i)
        var delay := neck_delay * (i - 1)
        var bob := 3.0 - (i * 0.3)  # Decreasing bob intensity toward head

        _add_rotation_track(anim, bone_name,
            [t0, t1 + delay, t2],
            [
                Quaternion.from_euler(Vector3(deg_to_rad(neck_pitch_per_segment + -bob * neck_intensity), 0, 0)),
                Quaternion.from_euler(Vector3(deg_to_rad(neck_pitch_per_segment + bob * neck_intensity), 0, 0)),
                Quaternion.from_euler(Vector3(deg_to_rad(neck_pitch_per_segment + -bob * neck_intensity), 0, 0)),
            ])

    # Head - final correction + subtle bob
    _add_rotation_track(anim, "Head",
        [t0, t1 + neck_delay * 5, t2],
        [
            Quaternion.from_euler(Vector3(deg_to_rad(head_pitch + 2 * neck_intensity), 0, 0)),
            Quaternion.from_euler(Vector3(deg_to_rad(head_pitch + -1.5 * neck_intensity), 0, 0)),
            Quaternion.from_euler(Vector3(deg_to_rad(head_pitch + 2 * neck_intensity), 0, 0)),
        ])
```

### 4.2 Bone Name Reference

Elder Scrolls Blades Dragon skeleton neck/head bones:
```
NPC Neck1_040  - Base of neck (connected to spine)
NPC Neck2_041  - Second neck segment
NPC Neck3_042  - Third neck segment
NPC Neck4_043  - Fourth neck segment
NPC Neck5_044  - Fifth neck segment (near head)
NPC NeckHub_045 - Neck-head junction
NPC Head_046   - Head bone
```

### 4.3 Skeleton Path
```
Sketchfab_model/Dragon_Ancient_Skeleton_fbx/Object_2/RootNode/Dragon_Ancient_Skeleton/NPC /NPC Root [Root]/Object_9/Skeleton3D
```

---

## 5. Testing & Troubleshooting

### 5.1 Quick Test Script
Add to dragon.gd for debugging:
```gdscript
func _input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_accept"):  # Space key
        print("Dragon state: ", DragonState.keys()[state])
        print("Model rotation: ", _model.rotation_degrees)
        print("Current bank angle: ", rad_to_deg(_current_bank_angle))
```

### 5.2 Common Issues and Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| Head still down | Correction too small | Increase `neck_pitch_per_segment` (try -15° each) |
| Head points up | Correction too large | Decrease `neck_pitch_per_segment` (try -10° each) |
| Jerky orientation | Interpolation too fast | Decrease lerp factor (try 3.0 instead of 5.0) |
| No banking | Not in PATROL state | Check state machine transitions |
| Dragon spins | Direction vector invalid | Add length check before atan2 |
| Scale affects rotation | Using basis.slerp with scaled model | Use euler angles instead |

### 5.3 Adjusting Values

To fine-tune the head orientation:

1. **More upward tilt**: Increase `upward_bias` (default: -3.0, try -5.0)
2. **Less upward tilt**: Decrease `upward_bias` (try -1.0 or 0.0)
3. **More correction per segment**: Increase `neck_pitch_per_segment` (try -15.0)
4. **Less correction per segment**: Decrease `neck_pitch_per_segment` (try -10.0)

### 5.4 Verify Animation Tracks
Run this to see what tracks are created:
```gdscript
func _ready():
    # After animation is added
    if _anim_player.has_animation(&"WingFlap"):
        var anim = _anim_player.get_animation(&"WingFlap")
        print("WingFlap tracks: ", anim.get_track_count())
        for i in anim.get_track_count():
            print("  ", anim.track_get_path(i))
```

### 5.5 Performance Considerations
- The procedural animation adds 36 tracks (wings, neck, body, tail, legs)
- Banking calculations run every physics frame
- Consider reducing track count for lower-end devices
- Neck wave delay is 2.5% of animation duration (25ms at 1s cycle)

---

## Summary of Changes Made

1. **dragon_wing_flap.gd**:
   - Increased neck pitch correction from -25° total to -68° total
   - Each neck segment: -12° pitch
   - Head bone: -8° pitch
   - Added -3° upward bias for heroic look
   - Reduced neck bob intensity for subtler movement

2. **dragon.gd**:
   - Added banking variables: `_last_direction`, `_current_bank_angle`
   - Updated `_face_direction()` with:
     - Turn rate calculation from direction change
     - Bank angle based on turn rate (max 25°)
     - Pitch based on vertical movement
     - Euler angle interpolation (avoids basis normalization issues)
   - Smooth orientation blending at 5.0 * delta

# Agent Workflow Guide

## Project Overview
3D platformer game built with Godot 4.5.1. Features a third-person character with FBX animations, day/night lighting system, and multiple landmark locations.

## Key Directories
- `player/` - Player character scripts and FBX animations
- `stage/` - Level scenes and stage-related scripts
- `assets/` - 3D models (GLB/FBX), textures, and imported assets
- `ui/` - UI components including minimap and touch controls
- `addons/` - Third-party plugins (lightning effects, spatial gardener, etc.)

## File Conventions
- GDScript files use snake_case: `player.gd`, `lighting_manager.gd`
- Scene files: `.tscn` for scenes, `.tres` for resources
- 3D models: Prefer GLB/FBX formats, import via Godot's resource system

## Running the Game
```bash
# Run game
/home/talves/bin/godot --path /home/talves/mthings/tpgame/godot-demo-projects/3d/platformer

# Import resources (headless)
timeout 60 /home/talves/bin/godot --path /home/talves/mthings/tpgame/godot-demo-projects/3d/platformer --headless --import

# Open editor
/home/talves/bin/godot --path /home/talves/mthings/tpgame/godot-demo-projects/3d/platformer -e
```

## Key Systems

### Lighting System
- `stage/lighting_manager.gd` - Day/night cycle management
- Press `L` to toggle between DAY and NIGHT modes
- Default: DAY

### Player Character
- `player/player.gd` - Main player controller
- FBX animations loaded dynamically from `player/character/`
- Supports armed/unarmed character states

### Village of Eights
- `stage/village_loader.gd` - Loads village FBX with collision
- Uses trimesh collision shapes for accurate wall collision
- Asset: `assets/village_of_eights.fbx`

### Landmarks (from minimap.gd)
| Location | Position |
|----------|----------|
| Village of Eights | (0, 0) |
| Common Ground | (0, 70) |
| Tower of Hakutnas | (-80, -60) |
| Realm of Hudson | (80, -50) |
| The Hills | (-30, 20) |
| The Burning Peaks | (-120, 0) |
| The Silent Woods | (120, 0) |
| Fire Creature Lair | (-115, 5) |
| Silent Creature Lair | (120, 1) |
| Fields | (60, -35) |

## Adding 3D Assets
1. Copy GLB/FBX to `assets/` directory
2. Run headless import: `godot --headless --import`
3. Create loader script if collision is needed (see `village_loader.gd`)
4. Add to scene via `.tscn` file or instantiate in script

## Collision for Imported Models
Use trimesh collision for accurate building/terrain collision:
```gdscript
func _create_collision_for_mesh(mesh_instance: MeshInstance3D) -> void:
    var mesh: Mesh = mesh_instance.mesh
    var static_body := StaticBody3D.new()
    var collision_shape := CollisionShape3D.new()
    collision_shape.shape = mesh.create_trimesh_shape()
    static_body.add_child(collision_shape)
    static_body.transform = mesh_instance.transform
    mesh_instance.get_parent().add_child(static_body)
```

## External Asset Sources
- FBX animations: `/home/talves/mthings/fbxs/` and `/home/talves/mthings/fbx2/`
- GLB models: `/home/talves/mthings/glbs/`

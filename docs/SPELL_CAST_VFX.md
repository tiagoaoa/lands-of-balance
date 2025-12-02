# Spell Cast VFX System Implementation

## Overview

A complete procedural spell casting visual effects system for the 3D platformer, featuring magic circles, dynamic lighting, and particle effects.

## Controls

| Input | Action |
|-------|--------|
| **Tab** | Switch to armed mode (required) |
| **C** (keyboard) | Cast spell |
| **B button** (gamepad) | Cast spell |

## Features

### 1. Magic Circle (Neon Ground Effect)

- **Dual torus rings** - outer ring (1.8-2.0 radius) and inner ring (0.9-1.0 radius)
- **Custom shader** with pulsing glow effect
- **Animated scale** - grows from tiny to full size when casting begins
- **Offset pulse timing** between rings for visual depth

```gdscript
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 glow_color : source_color = vec4(0.2, 0.5, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 10.0) = 3.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;

void fragment() {
    float pulse = 0.7 + 0.3 * sin(TIME * pulse_speed + time_offset);
    ALBEDO = glow_color.rgb * glow_intensity * pulse;
    EMISSION = glow_color.rgb * glow_intensity * pulse * 2.0;
}
```

### 2. Spell Light (Dynamic Illumination)

- **OmniLight3D** positioned at player chest height
- **Blue color** (0.3, 0.5, 1.0) with 8.0 range
- **Shadow enabled** for dramatic effect
- **Animated energy** - fades from 0 to 6.0 over 0.3 seconds

### 3. Particle Systems

#### Core Sparks
- 80 particles with 0.5s lifetime
- Sphere emission (0.8 radius) around player body
- White to blue gradient with alpha fade
- Emission energy: 5.0

#### Rising Sparks
- 60 particles with 1.5s lifetime
- **Ring emission shape** matching magic circle radius
- Upward velocity (2.0-4.0 units/sec)
- Fades in/out with color gradient

#### Lightning Bolts
- 20 particles with 0.3s lifetime (fast flashes)
- **Stretched quad mesh** (0.02 x 0.3) for bolt appearance
- **Billboard mode** for camera-facing orientation
- High emission energy (8.0) for bright streaks
- 0.8 explosiveness for burst effect

### 4. Animation Integration

- Uses **"Sword And Shield Power Up"** animation from Mixamo
- Animation triggers `_start_spell_effects()` on cast
- Effects stop when animation completes via `_on_animation_finished()`
- Prevents casting during attacks or cooldown

## Technical Details

### State Management
```gdscript
var is_casting: bool = false
```

### Effect Lifecycle
1. Player presses cast input
2. `_do_spell_cast()` validates state and sets `is_casting = true`
3. `_start_spell_effects()` creates tween for smooth animation:
   - Magic circle scales from 0.01 to 1.0 over 0.4s
   - Light energy tweens to 6.0 over 0.3s
   - All particle systems start emitting
4. Animation plays "armed/SpellCast"
5. On animation finish, `_stop_spell_effects()`:
   - Magic circle scales back to 0.01 over 0.3s
   - Light energy fades to 0 over 0.4s
   - Particle emitting disabled

### Node Hierarchy
```
Player
└── SpellEffects (Node3D)
    ├── MagicCircle (MeshInstance3D)
    │   └── InnerCircle (MeshInstance3D)
    ├── SpellLight (OmniLight3D)
    ├── CoreSparks (GPUParticles3D)
    ├── RisingSparks (GPUParticles3D)
    └── LightningBolts (GPUParticles3D)
```

## Files Modified

| File | Changes |
|------|---------|
| `player/player.gd` | Added spell VFX system (~300 lines) |
| `project.godot` | Added `spell_cast` input action |
| `player/character/armed/SpellCast.fbx` | Animation asset |

## Color Palette

| Element | Color (RGB) |
|---------|-------------|
| Magic circle outer | (0.2, 0.5, 1.0) |
| Magic circle inner | (0.4, 0.7, 1.0) |
| Spell light | (0.3, 0.5, 1.0) |
| Spark emission | (0.4, 0.6, 1.0) |
| Lightning bolts | (0.5, 0.7, 1.0) |

All effects use a consistent blue theme for cohesive visual style.

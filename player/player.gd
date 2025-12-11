class_name Player
extends CharacterBody3D
## Douglass, the Keeper of Balance, walking through the Lands of Balance.
## Third-person style controls with mouse look.
## Uses FBX character models with Mixamo animations.
## Supports armed (Paladin with sword & shield) and unarmed (Y Bot) combat modes.

# Lightning addon preloads
const Lightning3DBranchedClass = preload("res://addons/lightning/generators/Lightning3DBranched.gd")

const WALK_SPEED: float = 3.5
const RUN_SPEED: float = 7.0
const ACCEL: float = 12.0
const DEACCEL: float = 12.0
const JUMP_VELOCITY: float = 6.0
const MOUSE_SENSITIVITY: float = 0.002
const GAMEPAD_SENSITIVITY: float = 2.5  # radians per second at full stick
const CAMERA_VERTICAL_LIMIT: float = 85.0  # degrees
const RUN_THRESHOLD: float = 0.6  # Stick intensity threshold for running (60%)

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
	"spell_cast": "res://player/character/armed/SpellCast.fbx",
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
var is_casting: bool = false
var attack_combo: int = 0
var _attack_cooldown: float = 0.0

# Damage/knockback state
var _knockback_velocity: Vector3 = Vector3.ZERO
var _is_stunned: bool = false
var _stun_timer: float = 0.0
var _hit_flash_tween: Tween
var _hit_label: Label3D
var _attack_hitbox: Area3D
var _has_hit_this_attack: bool = false
const PLAYER_KNOCKBACK_RESISTANCE: float = 0.8  # Reduce knockback slightly
const PLAYER_ATTACK_DAMAGE: float = 15.0
const PLAYER_KNOCKBACK_FORCE: float = 10.0

# Spell VFX components (ProceduralThunderChannel)
var _spell_effects_container: Node3D
var _lightning_particles: GPUParticles3D
var _rising_sparks: GPUParticles3D
var _magic_circle: MeshInstance3D
var _spell_light: OmniLight3D
var _lightning_bolts: GPUParticles3D
var _spell_tween: Tween
# Enhanced spell VFX
var _spell_time: float = 0.0  # For sin() flicker calculations
var _lightning_bolts_3d: Array = []  # Lightning3DBranched instances from addon
var _character_aura_material: ShaderMaterial  # Fresnel aura shader
var _original_character_materials: Array[Dictionary] = []  # Store {mesh, material} pairs
const NUM_LIGHTNING_BOLTS: int = 6  # Number of 3D lightning bolts
# Audio system placeholders (assign audio streams in inspector or load at runtime)
var _audio_scream: AudioStreamPlayer3D  # Initial power-up scream
var _audio_static: AudioStreamPlayer3D  # Looping electric static
var _audio_discharge: AudioStreamPlayer3D  # One-shot discharge on spell end
# Force Field / Bubble Shield (V2 Asset Rich)
var _force_field_sphere: MeshInstance3D  # Bubble shield around character
var _force_field_light: OmniLight3D  # Constant light inside force field
var _force_field_material: ShaderMaterial  # Bubble shader with noise distortion

@onready var initial_position := position
@onready var gravity: Vector3 = ProjectSettings.get_setting("physics/3d/default_gravity") * \
		ProjectSettings.get_setting("physics/3d/default_gravity_vector")

@onready var _camera_pivot := $CameraPivot as Node3D
@onready var _camera := $CameraPivot/Camera3D as Camera3D


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_create_characters()
	_create_lightning_particles()
	_setup_hit_label()
	_setup_attack_hitbox()


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


func _create_lightning_particles() -> void:
	# Create container for all spell effects (ProceduralThunderChannel)
	_spell_effects_container = Node3D.new()
	_spell_effects_container.name = "SpellEffects"
	add_child(_spell_effects_container)

	_create_magic_circle()
	_create_force_field_sphere()  # V2: Bubble shield
	_create_spell_light()
	_create_spark_particles()
	_create_rising_sparks()
	_create_lightning_bolts()
	_create_character_aura_shader()
	_create_procedural_lightning_bolts()
	_create_spell_audio_system()


func _create_magic_circle() -> void:
	# Create a glowing magic circle on the ground using a torus mesh
	_magic_circle = MeshInstance3D.new()
	_magic_circle.name = "MagicCircle"

	var torus := TorusMesh.new()
	torus.inner_radius = 1.8
	torus.outer_radius = 2.0
	torus.rings = 32
	torus.ring_segments = 32
	_magic_circle.mesh = torus

	# Create glowing shader material for neon effect
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 glow_color : source_color = vec4(0.2, 0.5, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 10.0) = 3.0;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;
uniform float time_offset : hint_range(0.0, 6.28) = 0.0;

void fragment() {
	float pulse = 0.7 + 0.3 * sin(TIME * pulse_speed + time_offset);
	ALBEDO = glow_color.rgb * glow_intensity * pulse;
	ALPHA = glow_color.a * pulse;
	EMISSION = glow_color.rgb * glow_intensity * pulse * 2.0;
}
"""
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = shader
	shader_mat.set_shader_parameter("glow_color", Color(0.2, 0.5, 1.0, 0.9))
	shader_mat.set_shader_parameter("glow_intensity", 4.0)
	shader_mat.set_shader_parameter("pulse_speed", 3.0)
	_magic_circle.material_override = shader_mat

	_magic_circle.position = Vector3(0, 0.05, 0)
	_magic_circle.rotation_degrees.x = 90  # Lay flat on ground
	_magic_circle.scale = Vector3(0.01, 0.01, 0.01)  # Start tiny
	_magic_circle.visible = false

	_spell_effects_container.add_child(_magic_circle)

	# Add inner circle for more detail
	var inner_circle := MeshInstance3D.new()
	inner_circle.name = "InnerCircle"
	var inner_torus := TorusMesh.new()
	inner_torus.inner_radius = 0.9
	inner_torus.outer_radius = 1.0
	inner_torus.rings = 32
	inner_torus.ring_segments = 32
	inner_circle.mesh = inner_torus

	var inner_shader_mat := ShaderMaterial.new()
	inner_shader_mat.shader = shader
	inner_shader_mat.set_shader_parameter("glow_color", Color(0.4, 0.7, 1.0, 0.8))
	inner_shader_mat.set_shader_parameter("glow_intensity", 5.0)
	inner_shader_mat.set_shader_parameter("pulse_speed", 4.0)
	inner_shader_mat.set_shader_parameter("time_offset", 1.57)  # Offset pulse
	inner_circle.material_override = inner_shader_mat

	_magic_circle.add_child(inner_circle)


func _create_force_field_sphere() -> void:
	# Create a protective bubble/force field shield around the character (V2 Asset Rich)
	_force_field_sphere = MeshInstance3D.new()
	_force_field_sphere.name = "ForceFieldSphere"

	var sphere := SphereMesh.new()
	sphere.radius = 1.8
	sphere.height = 3.6
	sphere.radial_segments = 32
	sphere.rings = 16
	_force_field_sphere.mesh = sphere

	# Create bubble/force field shader with Fresnel edge glow and noise distortion
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode blend_add, depth_draw_opaque, cull_front, unshaded;

uniform vec4 bubble_color : source_color = vec4(0.0, 0.8, 1.0, 0.3);
uniform float fresnel_power : hint_range(0.5, 8.0) = 3.0;
uniform float edge_intensity : hint_range(0.0, 5.0) = 2.5;
uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;
uniform float distortion_scale : hint_range(0.0, 2.0) = 0.5;
uniform float distortion_speed : hint_range(0.0, 5.0) = 1.0;

// Simple noise function
float noise(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 45.543))) * 43758.5453);
}

float smooth_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float n000 = noise(i);
	float n001 = noise(i + vec3(0.0, 0.0, 1.0));
	float n010 = noise(i + vec3(0.0, 1.0, 0.0));
	float n011 = noise(i + vec3(0.0, 1.0, 1.0));
	float n100 = noise(i + vec3(1.0, 0.0, 0.0));
	float n101 = noise(i + vec3(1.0, 0.0, 1.0));
	float n110 = noise(i + vec3(1.0, 1.0, 0.0));
	float n111 = noise(i + vec3(1.0, 1.0, 1.0));

	float nx00 = mix(n000, n100, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx11 = mix(n011, n111, f.x);

	float nxy0 = mix(nx00, nx10, f.y);
	float nxy1 = mix(nx01, nx11, f.y);

	return mix(nxy0, nxy1, f.z);
}

void fragment() {
	// Calculate Fresnel effect for edge glow
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);

	// Animated noise for bubble distortion effect
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float noise_val = smooth_noise(world_pos * distortion_scale + TIME * distortion_speed);
	float noise_val2 = smooth_noise(world_pos * distortion_scale * 0.5 - TIME * distortion_speed * 0.7);

	// Pulsing effect
	float pulse = 0.7 + 0.3 * sin(TIME * pulse_speed);

	// Combine effects
	float intensity = fresnel * edge_intensity * pulse;
	intensity += (noise_val * 0.3 + noise_val2 * 0.2) * fresnel;

	ALBEDO = bubble_color.rgb * intensity;
	ALPHA = bubble_color.a * intensity * 0.8;
	EMISSION = bubble_color.rgb * intensity * 1.5;
}
"""
	_force_field_material = ShaderMaterial.new()
	_force_field_material.shader = shader
	_force_field_material.set_shader_parameter("bubble_color", Color(0.0, 0.9, 1.0, 0.4))
	_force_field_material.set_shader_parameter("fresnel_power", 3.0)
	_force_field_material.set_shader_parameter("edge_intensity", 2.5)
	_force_field_material.set_shader_parameter("pulse_speed", 3.0)
	_force_field_material.set_shader_parameter("distortion_scale", 0.8)
	_force_field_material.set_shader_parameter("distortion_speed", 1.2)
	_force_field_sphere.material_override = _force_field_material

	_force_field_sphere.position = Vector3(0, 1.0, 0)  # Center on character
	_force_field_sphere.scale = Vector3(0.01, 0.01, 0.01)  # Start tiny
	_force_field_sphere.visible = false

	_spell_effects_container.add_child(_force_field_sphere)

	# Add constant light inside the force field (non-flickering)
	_force_field_light = OmniLight3D.new()
	_force_field_light.name = "ForceFieldLight"
	_force_field_light.light_color = Color(0.0, 1.0, 1.0)  # Cyan
	_force_field_light.light_energy = 0.0  # Start off
	_force_field_light.omni_range = 4.0
	_force_field_light.omni_attenuation = 1.2
	_force_field_light.shadow_enabled = false
	_force_field_light.position = Vector3(0, 1.0, 0)

	_spell_effects_container.add_child(_force_field_light)


func _create_spell_light() -> void:
	# Create OmniLight3D for blue area illumination
	_spell_light = OmniLight3D.new()
	_spell_light.name = "SpellLight"
	_spell_light.light_color = Color(0.3, 0.5, 1.0)
	_spell_light.light_energy = 0.0  # Start off
	_spell_light.omni_range = 8.0
	_spell_light.omni_attenuation = 1.5
	_spell_light.shadow_enabled = true
	_spell_light.position = Vector3(0, 1.5, 0)

	_spell_effects_container.add_child(_spell_light)


func _create_spark_particles() -> void:
	# Core sparks around player body (ProceduralThunderChannel SparkShower)
	_lightning_particles = GPUParticles3D.new()
	_lightning_particles.name = "CoreSparks"
	_lightning_particles.emitting = false
	_lightning_particles.amount = 150  # Increased per JSON spec
	_lightning_particles.lifetime = 0.5
	_lightning_particles.one_shot = false
	_lightning_particles.explosiveness = 0.6
	_lightning_particles.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.8
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0, 0, 0)
	mat.scale_min = 0.02
	mat.scale_max = 0.08
	mat.damping_min = 2.0
	mat.damping_max = 4.0

	# Updated gradient per JSON spec
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(0.9, 0.95, 1.0, 1.0))  # Near-white start
	gradient.add_point(0.5, Color(0.3, 0.6, 1.0, 1.0))   # Blue mid
	gradient.add_point(1.0, Color(0.1, 0.3, 1.0, 0.0))   # Dark blue fade
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	_lightning_particles.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	mesh.radial_segments = 4
	mesh.rings = 2

	# Additive blend for glow effect
	var spark_mat := StandardMaterial3D.new()
	spark_mat.albedo_color = Color(0.9, 0.95, 1.0)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(0.4, 0.6, 1.0)
	spark_mat.emission_energy_multiplier = 6.0
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # Additive blending
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = spark_mat

	_lightning_particles.draw_pass_1 = mesh
	_lightning_particles.position = Vector3(0, 1.0, 0)

	_spell_effects_container.add_child(_lightning_particles)


func _create_rising_sparks() -> void:
	# Rising sparks from the magic circle
	_rising_sparks = GPUParticles3D.new()
	_rising_sparks.name = "RisingSparks"
	_rising_sparks.emitting = false
	_rising_sparks.amount = 60
	_rising_sparks.lifetime = 1.5
	_rising_sparks.one_shot = false
	_rising_sparks.explosiveness = 0.1
	_rising_sparks.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3(0, 1, 0)
	mat.emission_ring_height = 0.1
	mat.emission_ring_radius = 1.8
	mat.emission_ring_inner_radius = 1.6
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 15.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, 0.5, 0)  # Slight upward pull
	mat.scale_min = 0.03
	mat.scale_max = 0.1

	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(0.5, 0.8, 1.0, 0.0))
	gradient.add_point(0.2, Color(0.4, 0.7, 1.0, 1.0))
	gradient.add_point(0.8, Color(0.3, 0.5, 1.0, 0.8))
	gradient.add_point(1.0, Color(0.2, 0.3, 1.0, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	_rising_sparks.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 6
	mesh.rings = 3

	# Additive blend for glow effect
	var spark_mat := StandardMaterial3D.new()
	spark_mat.albedo_color = Color(0.5, 0.7, 1.0)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(0.3, 0.5, 1.0)
	spark_mat.emission_energy_multiplier = 5.0
	spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # Additive blending
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = spark_mat

	_rising_sparks.draw_pass_1 = mesh
	_rising_sparks.position = Vector3(0, 0.1, 0)

	_spell_effects_container.add_child(_rising_sparks)


func _create_lightning_bolts() -> void:
	# Lightning bolt streaks
	_lightning_bolts = GPUParticles3D.new()
	_lightning_bolts.name = "LightningBolts"
	_lightning_bolts.emitting = false
	_lightning_bolts.amount = 20
	_lightning_bolts.lifetime = 0.3
	_lightning_bolts.one_shot = false
	_lightning_bolts.explosiveness = 0.8
	_lightning_bolts.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 6, 8))

	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 1.5
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 8.0
	mat.initial_velocity_max = 15.0
	mat.gravity = Vector3(0, 0, 0)
	mat.scale_min = 0.02
	mat.scale_max = 0.04

	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.add_point(0.5, Color(0.5, 0.8, 1.0, 1.0))
	gradient.add_point(1.0, Color(0.2, 0.4, 1.0, 0.0))
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex

	_lightning_bolts.process_material = mat

	# Use stretched quads for bolt-like appearance
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.02, 0.3)

	# Additive blend for glow effect
	var bolt_mat := StandardMaterial3D.new()
	bolt_mat.albedo_color = Color(0.7, 0.9, 1.0)
	bolt_mat.emission_enabled = true
	bolt_mat.emission = Color(0.5, 0.7, 1.0)
	bolt_mat.emission_energy_multiplier = 10.0
	bolt_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD  # Additive blending
	bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = bolt_mat

	_lightning_bolts.draw_pass_1 = mesh
	_lightning_bolts.position = Vector3(0, 0.5, 0)

	_spell_effects_container.add_child(_lightning_bolts)


func _create_character_aura_shader() -> void:
	# Create Fresnel aura shader for character glow during casting
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 aura_color : source_color = vec4(0.3, 0.5, 1.0, 1.0);
uniform vec4 secondary_color : source_color = vec4(0.6, 0.3, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 10.0) = 2.0;
uniform float fresnel_power : hint_range(0.1, 10.0) = 2.0;
uniform float pulse_speed : hint_range(0.0, 20.0) = 8.0;
uniform float scale_offset : hint_range(1.0, 1.2) = 1.02;

void vertex() {
	// Expand mesh slightly outward for aura effect
	VERTEX *= scale_offset;
}

void fragment() {
	// Fresnel effect: stronger glow at edges
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), fresnel_power);

	// Pulse effect
	float pulse = 0.7 + 0.3 * sin(TIME * pulse_speed);

	// Color mix between blue and purple
	float color_mix = 0.5 + 0.5 * sin(TIME * 3.0);
	vec3 final_color = mix(aura_color.rgb, secondary_color.rgb, color_mix);

	ALBEDO = final_color * intensity * pulse;
	ALPHA = fresnel * aura_color.a * pulse;
	EMISSION = final_color * intensity * fresnel * pulse * 2.0;
}
"""
	_character_aura_material = ShaderMaterial.new()
	_character_aura_material.shader = shader
	_character_aura_material.set_shader_parameter("aura_color", Color(0.3, 0.5, 1.0, 0.8))
	_character_aura_material.set_shader_parameter("secondary_color", Color(0.6, 0.3, 1.0, 0.6))
	_character_aura_material.set_shader_parameter("intensity", 3.0)
	_character_aura_material.set_shader_parameter("fresnel_power", 2.5)
	_character_aura_material.set_shader_parameter("pulse_speed", 12.0)


func _create_procedural_lightning_bolts() -> void:
	# Create Lightning3DBranched instances from the lightning addon
	# Each bolt shoots from the character upward/outward with branching
	for i in range(NUM_LIGHTNING_BOLTS):
		# Create Lightning3DBranched with parameters:
		# subdivisions=10, max_deviation=0.6, branches=4, branch_deviation=0.4, bias=0.5
		var bolt := Lightning3DBranchedClass.new(10, 0.6, 4, 0.4, 0.5, Lightning3DBranchedClass.UPDATE_MODE.ON_PROCESS)
		bolt.name = "LightningBolt3D_%d" % i
		bolt.visible = false
		bolt.maximum_update_delta = 0.08  # Update every ~80ms for animation
		bolt.branches_to_end = false  # Branches spread out

		# Set initial origin/end points (will be updated when spell starts)
		var angle := TAU * i / NUM_LIGHTNING_BOLTS
		bolt.origin = Vector3(0, 0.5, 0)
		bolt.end = Vector3(cos(angle) * 1.5, 3.0, sin(angle) * 1.5)

		_spell_effects_container.add_child(bolt)
		_lightning_bolts_3d.append(bolt)


func _create_spell_audio_system() -> void:
	# Create audio players for spell sound effects
	# NOTE: Audio streams not provided - assign .ogg/.wav files in inspector or load at runtime

	# Scream/power-up sound - plays once at spell start
	_audio_scream = AudioStreamPlayer3D.new()
	_audio_scream.name = "SpellScream"
	_audio_scream.volume_db = -3.0  # Default volume, range [-5, 0]
	_audio_scream.pitch_scale = 1.0  # Range [0.9, 1.1] for variation
	_audio_scream.max_distance = 20.0
	_audio_scream.unit_size = 3.0
	_spell_effects_container.add_child(_audio_scream)

	# Electric static - loops during spell cast
	_audio_static = AudioStreamPlayer3D.new()
	_audio_static.name = "SpellStatic"
	_audio_static.volume_db = -10.0
	_audio_static.max_distance = 15.0
	_audio_static.unit_size = 2.0
	# Note: Set stream.loop = true when audio is assigned
	_spell_effects_container.add_child(_audio_static)

	# Discharge sound - plays once at spell end
	_audio_discharge = AudioStreamPlayer3D.new()
	_audio_discharge.name = "SpellDischarge"
	_audio_discharge.volume_db = -3.0
	_audio_discharge.max_distance = 25.0
	_audio_discharge.unit_size = 4.0
	_spell_effects_container.add_child(_audio_discharge)


func _randomize_lightning_bolt_endpoints() -> void:
	# Set random endpoints for each Lightning3DBranched bolt
	for i in range(_lightning_bolts_3d.size()):
		var bolt = _lightning_bolts_3d[i]
		if not bolt.visible:
			continue

		# Random start/end points around the character
		var angle := TAU * i / _lightning_bolts_3d.size() + randf_range(-0.3, 0.3)
		var height_start := randf_range(0.3, 0.8)
		var height_end := randf_range(2.5, 4.0)
		var radius_start := randf_range(0.2, 0.4)
		var radius_end := randf_range(1.0, 2.0)

		var start := Vector3(cos(angle) * radius_start, height_start, sin(angle) * radius_start)
		var end_angle := angle + randf_range(-0.5, 0.5)
		var end := Vector3(cos(end_angle) * radius_end, height_end, sin(end_angle) * radius_end)

		bolt.set_origin(start)
		bolt.set_end(end)


func _update_spell_effects(delta: float) -> void:
	if not is_casting:
		return

	_spell_time += delta

	# Flickering light using sin() with high frequency
	var base_energy := 6.0
	var flicker := sin(_spell_time * 20.0) * 2.0 + sin(_spell_time * 33.0) * 1.0 + sin(_spell_time * 47.0) * 0.5
	_spell_light.light_energy = base_energy + flicker

	# Lightning3DBranched auto-updates via ON_PROCESS mode - no manual regeneration needed


func _apply_character_aura() -> void:
	# Apply the Fresnel aura shader as overlay on the active character
	var active_char := _armed_character if combat_mode == CombatMode.ARMED else _unarmed_character
	if active_char == null:
		return

	# Find all MeshInstance3D nodes recursively and apply aura
	_original_character_materials.clear()
	_apply_aura_recursive(active_char)
	print("Applied aura to ", _original_character_materials.size(), " meshes")


func _apply_aura_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		# Store original material
		_original_character_materials.append({"mesh": mesh_inst, "material": mesh_inst.material_override})
		# Apply aura as next_pass to create overlay effect
		if mesh_inst.material_override:
			var mat := mesh_inst.material_override.duplicate() as Material
			mat.next_pass = _character_aura_material
			mesh_inst.material_override = mat
		else:
			# Create a simple pass-through material with the aura as next_pass
			var base_mat := StandardMaterial3D.new()
			base_mat.next_pass = _character_aura_material
			mesh_inst.material_override = base_mat

	for child in node.get_children():
		_apply_aura_recursive(child)


func _remove_character_aura() -> void:
	# Remove the aura shader and restore original materials
	for entry: Dictionary in _original_character_materials:
		var mesh_inst: MeshInstance3D = entry.mesh
		if is_instance_valid(mesh_inst):
			mesh_inst.material_override = entry.material
	_original_character_materials.clear()


func _start_spell_effects() -> void:
	if _spell_tween:
		_spell_tween.kill()

	# Reset spell time for flickering
	_spell_time = 0.0

	_spell_tween = create_tween()
	_spell_tween.set_parallel(true)

	# Show and animate magic circle
	_magic_circle.visible = true
	_magic_circle.scale = Vector3(0.01, 0.01, 0.01)
	_spell_tween.tween_property(_magic_circle, "scale", Vector3(1.0, 1.0, 1.0), 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Show and animate force field sphere (V2: bubble shield)
	_force_field_sphere.visible = true
	_force_field_sphere.scale = Vector3(0.01, 0.01, 0.01)
	_spell_tween.tween_property(_force_field_sphere, "scale", Vector3(1.0, 1.0, 1.0), 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)

	# Animate force field constant light (non-flickering, steady glow)
	_force_field_light.light_energy = 0.0
	_spell_tween.tween_property(_force_field_light, "light_energy", 2.0, 0.4).set_ease(Tween.EASE_OUT)

	# Animate spell light (initial value, will be modulated by _update_spell_effects)
	_spell_light.light_energy = 0.0
	_spell_tween.tween_property(_spell_light, "light_energy", 6.0, 0.3).set_ease(Tween.EASE_OUT)

	# Start all particles
	_lightning_particles.emitting = true
	_rising_sparks.emitting = true
	_lightning_bolts.emitting = true

	# Rotate magic circle
	_spell_tween.tween_property(_magic_circle, "rotation_degrees:y", 360.0, 2.0).from(0.0)

	# Show 3D lightning bolts (addon-based with animated shader)
	for bolt in _lightning_bolts_3d:
		bolt.visible = true
	_randomize_lightning_bolt_endpoints()

	# Apply character aura
	_apply_character_aura()

	# Start audio (only plays if streams are assigned)
	if _audio_scream.stream:
		_audio_scream.pitch_scale = randf_range(0.9, 1.1)  # Slight pitch variation
		_audio_scream.play()
	if _audio_static.stream:
		_audio_static.play()


func _stop_spell_effects() -> void:
	if _spell_tween:
		_spell_tween.kill()

	_spell_tween = create_tween()
	_spell_tween.set_parallel(true)

	# Shrink magic circle
	_spell_tween.tween_property(_magic_circle, "scale", Vector3(0.01, 0.01, 0.01), 0.3).set_ease(Tween.EASE_IN)
	_spell_tween.tween_callback(func(): _magic_circle.visible = false).set_delay(0.3)

	# Shrink and hide force field sphere (V2: bubble shield collapse)
	_spell_tween.tween_property(_force_field_sphere, "scale", Vector3(0.01, 0.01, 0.01), 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	_spell_tween.tween_callback(func(): _force_field_sphere.visible = false).set_delay(0.4)

	# Fade out force field constant light
	_spell_tween.tween_property(_force_field_light, "light_energy", 0.0, 0.3).set_ease(Tween.EASE_IN)

	# Fade out spell light
	_spell_tween.tween_property(_spell_light, "light_energy", 0.0, 0.4).set_ease(Tween.EASE_IN)

	# Stop particles
	_lightning_particles.emitting = false
	_rising_sparks.emitting = false
	_lightning_bolts.emitting = false

	# Hide 3D lightning bolts
	for bolt in _lightning_bolts_3d:
		bolt.visible = false

	# Remove character aura
	_remove_character_aura()

	# Stop audio and play discharge (only plays if streams are assigned)
	if _audio_static.playing:
		_audio_static.stop()
	if _audio_discharge.stream:
		_audio_discharge.play()


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
		"spell_cast": ["SpellCast", false],
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
		disable_attack_hitbox()  # Disable hitbox when attack ends
		_attack_cooldown = 0.2
		# Play transition from attack to idle (unarmed mode only)
		if combat_mode == CombatMode.UNARMED and _current_anim_player.has_animation(&"unarmed/ActionToIdle"):
			is_transitioning = true
			_current_anim_player.play(&"unarmed/ActionToIdle")
			_current_anim = &"unarmed/ActionToIdle"
	if is_casting:
		is_casting = false
		_stop_spell_effects()
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

	if is_attacking or is_sheathing or is_transitioning or is_casting:
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
	enable_attack_hitbox()  # Enable hitbox when attack starts

	if combat_mode == CombatMode.ARMED:
		attack_combo = (attack_combo + 1) % 2
		var attack_anim: StringName = &"armed/Attack1" if attack_combo == 0 else &"armed/Attack2"
		if _current_anim_player.has_animation(attack_anim):
			_current_anim_player.play(attack_anim)
			_current_anim = attack_anim
		else:
			is_attacking = false
			disable_attack_hitbox()
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
			disable_attack_hitbox()


func _do_spell_cast() -> void:
	# Only allow spell cast in armed mode
	if combat_mode != CombatMode.ARMED:
		return
	if is_casting or is_attacking or _attack_cooldown > 0:
		return

	is_casting = true

	# Start all spell effects
	_start_spell_effects()

	# Play spell cast animation
	if _current_anim_player.has_animation(&"armed/SpellCast"):
		_current_anim_player.play(&"armed/SpellCast")
		_current_anim = &"armed/SpellCast"
	else:
		is_casting = false
		_stop_spell_effects()


## Combat - Take damage and knockback from enemy attacks
func take_hit(damage: float, knockback: Vector3, blocked: bool) -> void:
	# Show floating "Hit!" label
	_show_hit_label()

	if blocked:
		# Blocked hit - blue flash, reduced knockback
		_flash_hit(Color(0.2, 0.4, 1.0))
		_knockback_velocity = knockback * PLAYER_KNOCKBACK_RESISTANCE * 0.3
	else:
		# Unblocked hit - blue flash, full knockback, stun
		_flash_hit(Color(0.2, 0.4, 1.0))
		_knockback_velocity = knockback * PLAYER_KNOCKBACK_RESISTANCE
		_is_stunned = true
		_stun_timer = 0.25
		is_attacking = false  # Cancel attack if hit

	# TODO: Apply damage when health system is implemented
	print("Player hit! Damage: ", damage, " Blocked: ", blocked)


func _flash_hit(color: Color) -> void:
	if _hit_flash_tween:
		_hit_flash_tween.kill()

	# Apply color flash to active character model
	var active_char = _armed_character if combat_mode == CombatMode.ARMED else _unarmed_character
	if active_char:
		_apply_hit_flash_recursive(active_char, color)

		# Reset after short delay
		_hit_flash_tween = create_tween()
		_hit_flash_tween.tween_callback(func(): _clear_hit_flash_recursive(active_char)).set_delay(0.15)


func _apply_hit_flash_recursive(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		var mat = mesh_inst.material_override
		if mat == null and mesh_inst.mesh:
			# Create override material if needed
			for i in range(mesh_inst.mesh.get_surface_count()):
				var surface_mat = mesh_inst.mesh.surface_get_material(i)
				if surface_mat is StandardMaterial3D:
					mat = surface_mat
					break
		if mat is StandardMaterial3D:
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 3.0

	for child in node.get_children():
		_apply_hit_flash_recursive(child, color)


func _clear_hit_flash_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		var mat = mesh_inst.material_override
		if mat == null and mesh_inst.mesh:
			for i in range(mesh_inst.mesh.get_surface_count()):
				var surface_mat = mesh_inst.mesh.surface_get_material(i)
				if surface_mat is StandardMaterial3D:
					mat = surface_mat
					break
		if mat is StandardMaterial3D:
			mat.emission_enabled = false

	for child in node.get_children():
		_clear_hit_flash_recursive(child)


func _setup_hit_label() -> void:
	# Create floating "Hit!" label above player
	_hit_label = Label3D.new()
	_hit_label.name = "HitLabel"
	_hit_label.text = "Hit!"
	_hit_label.font_size = 64
	_hit_label.modulate = Color(0.2, 0.4, 1.0)  # Blue for player
	_hit_label.outline_modulate = Color(0.0, 0.0, 0.3)
	_hit_label.outline_size = 8
	_hit_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hit_label.no_depth_test = true  # Always visible
	_hit_label.position = Vector3(0, 2.5, 0)  # Above head
	_hit_label.visible = false
	add_child(_hit_label)


func _setup_attack_hitbox() -> void:
	# Create attack hitbox Area3D for melee attacks
	_attack_hitbox = Area3D.new()
	_attack_hitbox.name = "AttackHitbox"
	_attack_hitbox.collision_layer = 0  # Doesn't collide with anything
	_attack_hitbox.collision_mask = 2   # Detects enemies (layer 2 - Bobba)
	_attack_hitbox.monitoring = false   # Start disabled

	# Create collision shape - box in front of player
	var collision_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(1.5, 1.5, 2.0)  # Wide and deep for sword swings
	collision_shape.shape = box
	collision_shape.position = Vector3(0, 1.0, 1.2)  # In front, at chest height

	_attack_hitbox.add_child(collision_shape)

	# Add hitbox to character model so it rotates with the player
	if _character_model:
		_character_model.add_child(_attack_hitbox)
	else:
		add_child(_attack_hitbox)

	# Connect signal
	_attack_hitbox.body_entered.connect(_on_attack_hitbox_body_entered)


func _on_attack_hitbox_body_entered(body: Node3D) -> void:
	if _has_hit_this_attack:
		return

	# Check if we hit an enemy with take_hit method
	if body.has_method("take_hit"):
		_has_hit_this_attack = true

		# Calculate knockback direction (from player to enemy)
		var knockback_dir = (body.global_position - global_position).normalized()
		knockback_dir.y = 0.2  # Slight upward component

		# Apply damage and knockback
		body.take_hit(PLAYER_ATTACK_DAMAGE, knockback_dir * PLAYER_KNOCKBACK_FORCE, false)
		print("Player hit enemy: ", body.name)


func enable_attack_hitbox() -> void:
	_has_hit_this_attack = false
	_attack_hitbox.monitoring = true


func disable_attack_hitbox() -> void:
	_attack_hitbox.monitoring = false


func _show_hit_label() -> void:
	if _hit_label == null:
		return

	# Reset and show the label
	_hit_label.visible = true
	_hit_label.position = Vector3(0, 2.5, 0)
	_hit_label.modulate.a = 1.0
	_hit_label.scale = Vector3(0.5, 0.5, 0.5)

	# Animate: scale up, float up, fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_hit_label, "scale", Vector3(1.0, 1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_hit_label, "position", Vector3(0, 3.5, 0), 0.6).set_ease(Tween.EASE_OUT)
	tween.tween_property(_hit_label, "modulate:a", 0.0, 0.4).set_delay(0.2)
	tween.chain().tween_callback(func(): _hit_label.visible = false)


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

	# Toggle combat mode with Tab, middle mouse button, or gamepad Back button
	if event.is_action_pressed(&"toggle_combat"):
		_toggle_combat_mode()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		_toggle_combat_mode()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_MIDDLE:
		_toggle_combat_mode()

	# Attack with left mouse button, F key, or gamepad X button
	if event.is_action_pressed(&"attack"):
		_do_attack()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			_do_attack()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F:
		_do_attack()

	# Block with right mouse button or gamepad LB
	if event.is_action_pressed(&"block"):
		is_blocking = true
	elif event.is_action_released(&"block"):
		is_blocking = false
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			is_blocking = event.pressed

	# Spell cast with C key, gamepad B button, or RB (armed mode only)
	if event.is_action_pressed(&"spell_cast") or event.is_action_pressed(&"cast_spell_rb"):
		_do_spell_cast()

	# Mouse look
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		camera_rotation.x -= event.relative.x * MOUSE_SENSITIVITY
		camera_rotation.y -= event.relative.y * MOUSE_SENSITIVITY
		camera_rotation.y = clamp(camera_rotation.y, deg_to_rad(-CAMERA_VERTICAL_LIMIT), deg_to_rad(CAMERA_VERTICAL_LIMIT))

		_camera_pivot.rotation.y = camera_rotation.x
		_camera_pivot.rotation.x = camera_rotation.y


func _physics_process(delta: float) -> void:
	# Skip movement when console is open (still apply gravity)
	if GameConsole.is_console_open:
		velocity += gravity * delta
		move_and_slide()
		return

	if _attack_cooldown > 0:
		_attack_cooldown -= delta

	# Handle stun/knockback state
	if _is_stunned:
		_stun_timer -= delta
		# Apply knockback velocity directly
		velocity.x = _knockback_velocity.x
		velocity.z = _knockback_velocity.z
		velocity.y += gravity.y * delta
		# Decelerate knockback
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, 30.0 * delta)
		if _stun_timer <= 0:
			_is_stunned = false
			_knockback_velocity = Vector3.ZERO
		move_and_slide()
		return

	# Update spell effects (flickering light, procedural bolts)
	_update_spell_effects(delta)

	# Gamepad camera control (right stick)
	var look_x: float = Input.get_action_strength(&"camera_look_right") - Input.get_action_strength(&"camera_look_left")
	var look_y: float = Input.get_action_strength(&"camera_look_down") - Input.get_action_strength(&"camera_look_up")
	if abs(look_x) > 0.01 or abs(look_y) > 0.01:
		camera_rotation.x -= look_x * GAMEPAD_SENSITIVITY * delta
		camera_rotation.y -= look_y * GAMEPAD_SENSITIVITY * delta
		camera_rotation.y = clamp(camera_rotation.y, deg_to_rad(-CAMERA_VERTICAL_LIMIT), deg_to_rad(CAMERA_VERTICAL_LIMIT))
		_camera_pivot.rotation.y = camera_rotation.x
		_camera_pivot.rotation.x = camera_rotation.y

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

	# Get movement input with analog stick support
	var input_dir := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back", 0.15)
	var input_strength := input_dir.length()  # 0.0 to 1.0 for analog stick intensity

	# Determine run state: Shift key OR stick pushed >60%
	var keyboard_run := Input.is_action_pressed(&"run") if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED else false
	is_running = keyboard_run or input_strength > RUN_THRESHOLD

	var current_max_speed: float = RUN_SPEED if is_running else WALK_SPEED
	var horizontal_velocity := Vector3(velocity.x, 0, velocity.z)

	# Normalize input direction for consistent movement
	if input_dir.length() > 0.1:
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

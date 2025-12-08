class_name LightingManager
extends Node

## Manages day/night lighting presets for the game

enum TimeOfDay { DAY, NIGHT }

@export var time_of_day: TimeOfDay = TimeOfDay.DAY:
	set(value):
		time_of_day = value
		if is_inside_tree():
			_apply_lighting()

@export var transition_duration: float = 2.0  ## Seconds to transition between presets

var _world_env: WorldEnvironment
var _dir_light: DirectionalLight3D
var _moon: Node3D
var _tween: Tween

# Day preset (original bright lighting)
const DAY_SETTINGS := {
	"background_energy": 1.0,
	"ambient_color": Color(0.7, 0.75, 0.8),
	"ambient_energy": 0.5,
	"ambient_sky_contribution": 0.3,
	"fog_enabled": true,
	"fog_density": 0.001,
	"fog_color": Color(0.75, 0.82, 0.9),
	"fog_light_energy": 1.0,
	"volumetric_fog_enabled": false,
	"ssao_enabled": false,
	"adjustment_enabled": false,
	"glow_enabled": false,
	"light_color": Color(1.0, 0.95, 0.85),
	"light_energy": 1.3,
	"light_rotation": Vector3(-45, -45, 0),
}

# Night preset (moonlit night - moon is the only light source)
# Fog reduced by 70%, ambient minimal, no directional sun light
const NIGHT_SETTINGS := {
	"background_energy": 0.02,  # Very dim night sky
	"ambient_color": Color(0.08, 0.1, 0.15),  # Very dark blue-gray ambient
	"ambient_energy": 0.05,  # Minimal ambient - moon provides main light
	"ambient_sky_contribution": 0.0,  # No sky contribution
	"fog_enabled": true,
	"fog_density": 0.0105,  # Light fog
	"fog_color": Color(0.15, 0.18, 0.22),  # Dark cool fog
	"fog_light_energy": 0.02,  # Very dim fog scattering
	"volumetric_fog_enabled": true,
	"ssao_enabled": true,
	"adjustment_enabled": true,
	"glow_enabled": true,
	"light_color": Color(0.5, 0.55, 0.65),  # Not used - directional light off
	"light_energy": 0.0,  # Directional light OFF - moon is only source
	"light_rotation": Vector3(-10, -45, 0),
}


func _ready() -> void:
	# Find WorldEnvironment and DirectionalLight3D in parent
	_world_env = _find_node_of_type(get_parent(), "WorldEnvironment")
	_dir_light = _find_node_of_type(get_parent(), "DirectionalLight3D")
	_moon = get_parent().get_node_or_null("Moon")

	if not _world_env:
		push_warning("LightingManager: No WorldEnvironment found")
	if not _dir_light:
		push_warning("LightingManager: No DirectionalLight3D found")
	if not _moon:
		push_warning("LightingManager: No Moon found")

	_apply_lighting()


func _find_node_of_type(parent: Node, type_name: String) -> Node:
	for child in parent.get_children():
		if child.get_class() == type_name:
			return child
	return null


func set_time(new_time: TimeOfDay, instant: bool = false) -> void:
	time_of_day = new_time
	if instant:
		_apply_lighting()
	else:
		_transition_lighting()


func toggle_time() -> void:
	if time_of_day == TimeOfDay.DAY:
		set_time(TimeOfDay.NIGHT)
	else:
		set_time(TimeOfDay.DAY)


func _apply_lighting() -> void:
	if not _world_env or not _world_env.environment:
		return

	var settings: Dictionary = NIGHT_SETTINGS if time_of_day == TimeOfDay.NIGHT else DAY_SETTINGS
	var env := _world_env.environment

	# Apply environment settings
	env.background_energy_multiplier = settings.background_energy
	env.ambient_light_color = settings.ambient_color
	env.ambient_light_energy = settings.ambient_energy
	env.ambient_light_sky_contribution = settings.ambient_sky_contribution

	# Fog
	env.fog_enabled = settings.fog_enabled
	env.fog_density = settings.fog_density
	env.fog_light_color = settings.fog_color
	env.fog_light_energy = settings.fog_light_energy

	# Volumetric fog (night only) - heavy mist for eerie atmosphere
	# Reduced by 70%
	env.volumetric_fog_enabled = settings.volumetric_fog_enabled
	if settings.volumetric_fog_enabled:
		env.volumetric_fog_density = 0.015  # Dense fog reduced 70% (0.05 * 0.3)
		env.volumetric_fog_albedo = Color(0.35, 0.4, 0.45)  # Cool gray mist
		env.volumetric_fog_emission = Color(0.02, 0.025, 0.03)
		env.volumetric_fog_emission_energy = 0.045  # Subtle glow reduced 70%
		env.volumetric_fog_length = 60.0  # Fog visible range

	# SSAO (night only) - harsh shadows on ground and tree bases
	env.ssao_enabled = settings.ssao_enabled
	if settings.ssao_enabled:
		env.ssao_radius = 2.5
		env.ssao_intensity = 2.0  # Strong shadows for contrast

	# Color adjustment (night only) - cool desaturated look
	# Brightness reduced by 50%
	env.adjustment_enabled = settings.adjustment_enabled
	if settings.adjustment_enabled:
		env.adjustment_brightness = 0.425  # Dim overall (50% of 0.85)
		env.adjustment_contrast = 1.25  # High contrast
		env.adjustment_saturation = 0.4  # Desaturated, cool tones

	# Glow (night only) - ethereal haze effect
	# Reduced by 50%
	env.glow_enabled = settings.glow_enabled
	if settings.glow_enabled:
		env.glow_intensity = 0.15  # 50% of 0.3
		env.glow_strength = 0.3  # 50% of 0.6
		env.glow_bloom = 0.075  # 50% of 0.15
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Directional light
	if _dir_light:
		_dir_light.light_color = settings.light_color
		_dir_light.light_energy = settings.light_energy
		_dir_light.rotation_degrees = settings.light_rotation

	# Moon visibility - only show at night
	if _moon and _moon.has_method("set_visible_mode"):
		_moon.set_visible_mode(time_of_day == TimeOfDay.NIGHT)
	elif _moon:
		_moon.visible = (time_of_day == TimeOfDay.NIGHT)


func _transition_lighting() -> void:
	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN_OUT)
	_tween.set_trans(Tween.TRANS_SINE)

	var settings: Dictionary = NIGHT_SETTINGS if time_of_day == TimeOfDay.NIGHT else DAY_SETTINGS
	var env := _world_env.environment

	# Tween main properties
	_tween.tween_property(env, "background_energy_multiplier", settings.background_energy, transition_duration)
	_tween.parallel().tween_property(env, "ambient_light_color", settings.ambient_color, transition_duration)
	_tween.parallel().tween_property(env, "ambient_light_energy", settings.ambient_energy, transition_duration)
	_tween.parallel().tween_property(env, "fog_density", settings.fog_density, transition_duration)
	_tween.parallel().tween_property(env, "fog_light_color", settings.fog_color, transition_duration)
	_tween.parallel().tween_property(env, "fog_light_energy", settings.fog_light_energy, transition_duration)

	if _dir_light:
		_tween.parallel().tween_property(_dir_light, "light_color", settings.light_color, transition_duration)
		_tween.parallel().tween_property(_dir_light, "light_energy", settings.light_energy, transition_duration)
		_tween.parallel().tween_property(_dir_light, "rotation_degrees", settings.light_rotation, transition_duration)

	# Toggle boolean properties at halfway point
	# Values reduced: fog 70%, lighting 50%
	_tween.tween_callback(func():
		env.volumetric_fog_enabled = settings.volumetric_fog_enabled
		env.ssao_enabled = settings.ssao_enabled
		env.adjustment_enabled = settings.adjustment_enabled
		env.glow_enabled = settings.glow_enabled
		if settings.volumetric_fog_enabled:
			env.volumetric_fog_density = 0.015  # 70% reduction
			env.volumetric_fog_albedo = Color(0.35, 0.4, 0.45)
		if settings.ssao_enabled:
			env.ssao_radius = 2.5
			env.ssao_intensity = 2.0
		if settings.adjustment_enabled:
			env.adjustment_brightness = 0.425  # 50% reduction
			env.adjustment_contrast = 1.25
			env.adjustment_saturation = 0.4
		if settings.glow_enabled:
			env.glow_intensity = 0.15  # 50% reduction
			env.glow_strength = 0.3  # 50% reduction
	).set_delay(transition_duration * 0.5)


func _input(event: InputEvent) -> void:
	# Press 'L' to toggle day/night (for testing)
	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		toggle_time()
		print("Switched to: ", "NIGHT" if time_of_day == TimeOfDay.NIGHT else "DAY")

extends SceneTree
## Run with: godot --headless --script res://assets/apply_foggy_atmosphere.gd
## Creates eerie, foggy forest atmosphere with low-key lighting

func _init() -> void:
	print("Applying foggy forest atmosphere...")

	var scene_path := "res://stage/lands_of_balance.tscn"
	var packed: PackedScene = load(scene_path)
	if packed == null:
		push_error("Failed to load scene")
		quit()
		return

	var scene: Node3D = packed.instantiate()

	# Find WorldEnvironment
	var world_env: WorldEnvironment = scene.get_node_or_null("WorldEnvironment")
	if world_env == null:
		push_error("Could not find WorldEnvironment")
		quit()
		return

	# Create new Environment resource with foggy atmosphere
	var env := Environment.new()

	# Background - darker sky
	env.background_mode = Environment.BG_SKY
	env.background_energy_multiplier = 0.225  # Dim sky (+50%)

	# Create overcast/foggy sky
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	# Overcast gray-blue sky
	sky_material.sky_top_color = Color(0.15, 0.18, 0.25)  # Dark blue-gray
	sky_material.sky_horizon_color = Color(0.3, 0.35, 0.4)  # Lighter gray at horizon
	sky_material.ground_bottom_color = Color(0.1, 0.12, 0.15)  # Very dark
	sky_material.ground_horizon_color = Color(0.25, 0.28, 0.32)  # Dark gray
	sky_material.sun_angle_max = 0  # No visible sun
	sky.sky_material = sky_material
	env.sky = sky

	# Ambient light - very dim, cool tones
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.12, 0.15, 0.2)  # Dark blue-gray ambient
	env.ambient_light_energy = 0.45  # Low energy (+50%)

	# Tonemap for moody look
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.8
	env.tonemap_white = 1.0

	# FOG - Heavy volumetric fog
	env.fog_enabled = true
	env.fog_light_color = Color(0.4, 0.45, 0.5)  # Cool gray fog
	env.fog_light_energy = 0.3  # Dim fog lighting
	env.fog_density = 0.025  # Dense fog (0.01-0.05 range)
	env.fog_sky_affect = 0.8  # Fog affects sky visibility
	env.fog_height = 0.0  # Ground level
	env.fog_height_density = 0.1  # Some height-based density

	# Volumetric fog for atmospheric effect
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.03
	env.volumetric_fog_albedo = Color(0.5, 0.55, 0.6)  # Cool gray
	env.volumetric_fog_emission = Color(0.02, 0.025, 0.03)  # Subtle glow
	env.volumetric_fog_emission_energy = 0.5
	env.volumetric_fog_anisotropy = 0.3  # Some forward scattering
	env.volumetric_fog_length = 80.0  # ~20-30m visibility
	env.volumetric_fog_detail_spread = 0.8
	env.volumetric_fog_ambient_inject = 0.1

	# Color correction for desaturated, moody look
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.85  # Slightly darker
	env.adjustment_contrast = 1.15  # Higher contrast for shadows
	env.adjustment_saturation = 0.6  # Desaturated cool tones

	# SSAO for deeper shadows
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.5
	env.ssao_power = 2.0
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.3

	# Glow for subtle ethereal effect
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_strength = 0.8
	env.glow_bloom = 0.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Apply environment
	world_env.environment = env

	# Find and modify DirectionalLight3D
	var dir_light: DirectionalLight3D = scene.get_node_or_null("DirectionalLight3D")
	if dir_light:
		# Low horizon glow - faint moonlight/dusk effect
		dir_light.light_color = Color(0.6, 0.65, 0.75)  # Cool blue-gray light
		dir_light.light_energy = 0.375  # Low intensity (+50%)
		dir_light.light_indirect_energy = 0.2
		# Angle low for horizon glow effect
		dir_light.rotation_degrees = Vector3(-15, -45, 0)  # Low angle
		dir_light.shadow_enabled = true
		dir_light.shadow_opacity = 0.8
		print("  Modified DirectionalLight3D for dim horizon glow")

	# Save the modified scene
	var new_packed := PackedScene.new()
	new_packed.pack(scene)
	var err := ResourceSaver.save(new_packed, scene_path)
	if err == OK:
		print("Done! Applied foggy forest atmosphere:")
		print("  - Dark, cool ambient lighting (blue-gray tones)")
		print("  - Dense volumetric fog (25m visibility)")
		print("  - Low directional light (moonlight/dusk effect)")
		print("  - Desaturated color grading")
		print("  - SSAO for deep shadows")
		print("  - Subtle ethereal glow")
	else:
		push_error("Failed to save: " + str(err))

	scene.queue_free()
	quit()

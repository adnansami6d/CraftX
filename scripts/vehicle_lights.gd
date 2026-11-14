extends RefCounted
# v_002: real headlights (SpotLight3D). Switched on only while someone drives / flies AND it is dusk or night.
# Only 2 lights on the tractor and 1 on the helicopter, no shadows (cheap on a phone). Off = zero cost.
# Numbers are in config.gd (LIGHTS, LIGHT_ON_ELEV).


static func spot(parent: Node3D, pos: Vector3, pitch_deg: float, range_m: float, angle_deg: float, energy: float, color: Color) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.position = pos
	l.rotation_degrees = Vector3(pitch_deg, 0.0, 0.0)   # forward is -Z, negative pitch looks down
	l.spot_range = range_m
	l.spot_angle = angle_deg
	l.spot_angle_attenuation = 1.4   # soft edge, bright centre
	l.spot_attenuation = 1.0
	l.light_energy = energy
	l.light_color = color
	l.shadow_enabled = false
	l.light_specular = 0.4
	l.visible = false
	parent.add_child(l)
	return l


# visible light beam in the air (a soft cone, additive, fades along its length). Child of the spot light, so it follows it.
static var _beam_mat: ShaderMaterial


static func beam(light: Node3D, length: float, far_radius: float, strength: float) -> void:
	if _beam_mat == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 tint = vec3(1.0, 0.92, 0.75);
uniform float strength = 0.25;
uniform float len = 30.0;
varying float fade;
void vertex() {
	fade = clamp((VERTEX.y + len * 0.5) / len, 0.0, 1.0);
}
void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	ALBEDO = tint * strength * fade * fade * edge;
}
"""
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = sh
	var c := CylinderMesh.new()
	c.top_radius = 0.12
	c.bottom_radius = far_radius
	c.height = length
	c.radial_segments = 12
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	var m := _beam_mat.duplicate() as ShaderMaterial
	m.set_shader_parameter("len", length)
	m.set_shader_parameter("strength", strength)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)   # narrow end at the lamp, wide end far away (-Z)
	mi.position = Vector3(0.0, 0.0, -length * 0.5)
	light.add_child(mi)


# bright lens when on, dull glass when off (make a private copy of the material first: Util.glow() materials are shared)
static func lens_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.15
	return m


static func set_on(lights: Array, on: bool, lens: StandardMaterial3D = null) -> void:
	for l in lights:
		if is_instance_valid(l) and (l as Light3D).visible != on:
			(l as Light3D).visible = on
	if lens != null:
		lens.emission_energy_multiplier = 9.0 if on else 0.15

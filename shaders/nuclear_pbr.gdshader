shader_type spatial;
// Nuclear Rush surface shader.
//
// The project ships no imported art, so realism has to come from real physically
// based response plus procedural relief rather than photographic textures.  This
// replaces the illustrative `pulp_lit` look: standard Burley diffuse and
// Schlick-GGX specular are left switched on so the engine's own PBR lighting,
// sky reflections and shadows do the work, exactly as they would for an imported
// metal-roughness material.
//
// Surface relief is a sum of sine bands with an ANALYTIC gradient.  That matters
// on the mobile renderer at 120 Hz: perturbing the normal from a noise field
// would need three extra noise samples per fragment, while a sine sum gives the
// exact derivative for free.  One cheap value-noise octave on top supplies the
// non-repeating grime that sines alone cannot fake.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.42, 0.45, 0.48, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
// World-space frequency of the relief.  Small values read as poured concrete,
// large values as brushed or stamped panel work.
uniform float detail_scale : hint_range(0.05, 12.0) = 1.6;
// Deliberately small. Albedo variation is what the eye reads as "pattern", so
// anything above roughly 0.15 turns tactile surface into visible banding.
uniform float detail_strength : hint_range(0.0, 1.0) = 0.10;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.30;
// Upward faces collect dust and lose gloss; vertical faces stay cleaner.
uniform float edge_wear : hint_range(0.0, 1.0) = 0.25;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.50;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 24.0) = 0.0;

varying vec3 world_position;
varying vec3 world_normal;

// Four sine bands with deliberately non-harmonic directions so the pattern never
// resolves into a visible grid at any viewing distance.
const vec3 BAND_A = vec3(1.000, 0.370, 0.230);
const vec3 BAND_B = vec3(-0.310, 0.190, 1.170);
const vec3 BAND_C = vec3(0.730, 1.090, -0.470);
const vec3 BAND_D = vec3(2.170, -0.630, 1.910);

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 31.316;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Trilinear value noise - isotropic, so it never resolves into wavefronts the
// way a sine sum does. This is what drives everything the eye reads directly
// (albedo, roughness, AO); the sine sum below is used only to tilt the normal.
float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(cell + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(cell + vec3(1.0, 1.0, 1.0));
	float x00 = mix(n000, n100, f.x);
	float x10 = mix(n010, n110, f.x);
	float x01 = mix(n001, n101, f.x);
	float x11 = mix(n011, n111, f.x);
	return mix(mix(x00, x10, f.y), mix(x01, x11, f.y), f.z);
}

// Height of the relief, and its exact world-space gradient, in one pass.
float relief(vec3 p, out vec3 gradient) {
	vec3 ka = BAND_A * detail_scale;
	vec3 kb = BAND_B * detail_scale * 2.13;
	vec3 kc = BAND_C * detail_scale * 4.31;
	vec3 kd = BAND_D * detail_scale * 8.07;
	float aa = 0.50;
	float ab = 0.26;
	float ac = 0.15;
	float ad = 0.09;
	float sa = sin(dot(p, ka));
	float sb = sin(dot(p, kb));
	float sc = sin(dot(p, kc));
	float sd = sin(dot(p, kd));
	gradient = ka * (aa * cos(dot(p, ka)))
		+ kb * (ab * cos(dot(p, kb)))
		+ kc * (ac * cos(dot(p, kc)))
		+ kd * (ad * cos(dot(p, kd)));
	// Remap the signed sum into 0..1 so it can drive albedo and AO directly.
	return (sa * aa + sb * ab + sc * ac + sd * ad) * 0.5 + 0.5;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 shading_normal = normalize(world_normal);

	vec3 relief_gradient = vec3(0.0);
	float height = relief(world_position, relief_gradient);

	// Build a tangent frame from the world normal alone.  Mesh tangents are not
	// reliable here - the ramps are hand-built ArrayMeshes - so NORMAL_MAP is not
	// an option and the normal is perturbed directly instead.
	vec3 up_reference = mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), step(0.99, abs(shading_normal.y)));
	vec3 tangent = normalize(cross(shading_normal, up_reference));
	vec3 bitangent = cross(shading_normal, tangent);
	// Only the component of the gradient lying in the surface plane tilts the normal.
	vec2 slope = vec2(dot(relief_gradient, tangent), dot(relief_gradient, bitangent));
	vec3 perturbed = normalize(shading_normal - (tangent * slope.x + bitangent * slope.y) * normal_strength * 0.06);

	float up_facing = clamp(dot(shading_normal, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);

	// Grime pools in the recesses of the relief and on horizontal surfaces.
	float grime = value_noise(world_position * detail_scale * 0.65);
	float recess = 1.0 - height;
	float dirt = clamp(grime * 0.6 + recess * 0.4, 0.0, 1.0) * grime_strength;
	float dust = up_facing * edge_wear;

	vec3 surface_color = albedo.rgb;
	// Relief lightens proud areas and darkens recesses, the way real cast surfaces read.
	surface_color *= 1.0 + (height - 0.5) * detail_strength;
	// Dirt desaturates toward a neutral grey rather than simply darkening.
	surface_color = mix(surface_color, surface_color * vec3(0.62, 0.61, 0.58), dirt);
	// Settled dust raises value slightly and kills the sheen.
	surface_color = mix(surface_color, surface_color * 1.06 + vec3(0.035), dust * 0.5);

	ALBEDO = clamp(surface_color, vec3(0.0), vec3(1.0));
	METALLIC = clamp(metallic * (1.0 - dirt * 0.5), 0.0, 1.0);
	ROUGHNESS = clamp(roughness + dirt * 0.22 + dust * 0.18 - (height - 0.5) * 0.10, 0.04, 1.0);
	SPECULAR = 0.5;
	NORMAL = normalize((VIEW_MATRIX * vec4(perturbed, 0.0)).xyz);
	// Cheap contact darkening in the relief valleys - the mobile renderer has no
	// screen-space AO, so the material has to supply its own.
	AO = clamp(1.0 - recess * ao_strength, 0.0, 1.0);
	AO_LIGHT_AFFECT = 0.55;
	EMISSION = emission_color.rgb * emission_energy;
}

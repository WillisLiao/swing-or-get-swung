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
// Surface relief needs an ANALYTIC gradient.  That matters on the mobile
// renderer at 120 Hz: finite-differencing a height field costs three extra
// samples per fragment just to tilt the normal.  This used to be paid for with
// a sum of sine bands, whose derivative is free - but a periodic height field
// gives a periodic specular response, and once the engine's sky reflections hit
// it the bands read as diagonal candy-stripes that sweep across every surface as
// the view angle changes.  Worst on weapons and hands, which are close to the
// camera and in constant motion, but visible on all cover geometry too.
//
// Trilinear value noise solves it without giving up the free derivative: the
// eight corner hashes an octave already fetches determine the interpolant
// exactly, so its gradient is available in closed form for a handful of extra
// mul/adds and no extra taps.  Two octaves drive height AND normal from the same
// isotropic, non-repeating field, so proud areas are proud in both - and there is
// no preferred direction left for a stripe to form along.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.42, 0.45, 0.48, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.55;
// World-space frequency of the relief.  Small values read as poured concrete,
// large values as brushed or stamped panel work.
uniform float detail_scale : hint_range(0.05, 12.0) = 1.6;
// Deliberately small. Albedo variation is what the eye reads as "pattern", so
// large values turn tactile surface into visible mottling.  It is safer than it
// used to be now the field is isotropic noise rather than sine bands - there is
// no direction for it to streak along - but it still wants to stay subtle.
uniform float detail_strength : hint_range(0.0, 1.0) = 0.10;
uniform float normal_strength : hint_range(0.0, 3.0) = 1.0;
uniform float grime_strength : hint_range(0.0, 1.0) = 0.30;
// Upward faces collect dust and lose gloss; vertical faces stay cleaner.
uniform float edge_wear : hint_range(0.0, 1.0) = 0.25;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.50;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy : hint_range(0.0, 24.0) = 0.0;
// Imported map shells use authored geometry for their manufactured detail.
// Keep this branch before every noise helper call so clean surfaces also cut
// the fragment cost of the procedural fallback path.
uniform bool clean_surface = false;

varying vec3 world_position;
varying vec3 world_normal;

// The noise lattice is sampled through this rotation so its cell boundaries
// never align with the world-axis-aligned cover boxes and floor slabs, which
// would otherwise let the trilinear cells read as a faint cubic grid.
const mat3 NOISE_BASIS = mat3(
	vec3(0.8138, 0.4702, -0.3410),
	vec3(-0.4702, 0.8757, 0.1057),
	vec3(0.3410, 0.1057, 0.9341));

// Relief octaves, as multiples of `detail_scale`.  The low octave is the broad
// cast-surface swell (and doubles as the grime field); the high octave is the
// fine tooth that catches specular.
const float OCTAVE_LO = 0.65;
const float OCTAVE_HI = 3.10;
const float WEIGHT_LO = 0.62;
const float WEIGHT_HI = 0.38;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 31.316;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Trilinear value noise - isotropic, so it never resolves into wavefronts the
// way a sine sum does - returning its value AND its exact gradient.
//
// The trilinear interpolant is a polynomial in the smoothstepped coordinates
// whose eight coefficients k0..k7 fall straight out of the eight corner hashes
// this function already fetches.  Differentiating that polynomial and applying
// the chain rule through the smoothstep gives the gradient in closed form, so
// the derivative costs only mul/adds - no second, third or fourth tap.  That is
// what makes a noise-driven normal affordable at 120 Hz.
float value_noise_d(vec3 p, out vec3 gradient) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	vec3 du = 6.0 * f * (1.0 - f);
	float n000 = hash13(cell + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(cell + vec3(1.0, 1.0, 1.0));
	float k0 = n000;
	float k1 = n100 - n000;
	float k2 = n010 - n000;
	float k3 = n001 - n000;
	float k4 = n000 - n100 - n010 + n110;
	float k5 = n000 - n010 - n001 + n011;
	float k6 = n000 - n100 - n001 + n101;
	float k7 = -n000 + n100 + n010 - n110 + n001 - n101 - n011 + n111;
	gradient = du * vec3(
		k1 + k4 * u.y + k6 * u.z + k7 * u.y * u.z,
		k2 + k4 * u.x + k5 * u.z + k7 * u.z * u.x,
		k3 + k5 * u.y + k6 * u.x + k7 * u.x * u.y);
	return k0 + k1 * u.x + k2 * u.y + k3 * u.z
		+ k4 * u.x * u.y + k5 * u.y * u.z + k6 * u.z * u.x
		+ k7 * u.x * u.y * u.z;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 shading_normal = normalize(world_normal);
	if (clean_surface) {
		ALBEDO = clamp(albedo.rgb, vec3(0.0), vec3(1.0));
		METALLIC = clamp(metallic, 0.0, 1.0);
		ROUGHNESS = clamp(roughness, 0.04, 1.0);
		SPECULAR = 0.5;
		NORMAL = normalize((VIEW_MATRIX * vec4(shading_normal, 0.0)).xyz);
		AO = 1.0;
		AO_LIGHT_AFFECT = 0.0;
		EMISSION = emission_color.rgb * emission_energy;
	} else {

	// Two octaves of the same isotropic field drive height and normal together,
	// so a proud area shades proud and reads proud.  Sampling through
	// NOISE_BASIS keeps the lattice off the world axes.
	float freq_lo = detail_scale * OCTAVE_LO;
	float freq_hi = detail_scale * OCTAVE_HI;
	vec3 sample_point = NOISE_BASIS * world_position;
	vec3 grad_lo;
	float noise_lo = value_noise_d(sample_point * freq_lo, grad_lo);
	// The high octave (freq_hi = detail_scale * 3.10) is sub-pixel - pure
	// aliasing, not signal - past a few metres, so its 8 extra hash13 calls
	// are wasted work on most of a scene this size (the map floor alone is
	// a 120m disc). VERTEX is camera-space here, so its length is exactly
	// distance-to-camera; that varies smoothly across a surface, so this
	// branch has near-zero divergence within a quad on tile-based mobile
	// GPUs. detail_fade still ramps the octave's contribution to zero
	// continuously before the branch skips computing it, so there is no pop
	// at the cutoff. See handoffs/HANDOFF.md's "Performance discipline".
	float detail_fade = 1.0 - smoothstep(12.0, 30.0, length(VERTEX));
	float noise_hi = 0.0;
	vec3 grad_hi = vec3(0.0);
	if (detail_fade > 0.004) {
		noise_hi = value_noise_d(sample_point * freq_hi, grad_hi);
	}
	float height = noise_lo * WEIGHT_LO + noise_hi * WEIGHT_HI * detail_fade;
	// Chain rule back to world space: scale each octave's gradient by its own
	// frequency, then undo the basis rotation (v * M == transpose(M) * v).
	vec3 relief_gradient = (grad_lo * (freq_lo * WEIGHT_LO)
		+ grad_hi * (freq_hi * WEIGHT_HI * detail_fade)) * NOISE_BASIS;

	// Build a tangent frame from the world normal alone.  Mesh tangents are not
	// reliable here - the ramps are hand-built ArrayMeshes - so NORMAL_MAP is not
	// an option and the normal is perturbed directly instead.
	vec3 up_reference = mix(vec3(0.0, 1.0, 0.0), vec3(1.0, 0.0, 0.0), step(0.99, abs(shading_normal.y)));
	vec3 tangent = normalize(cross(shading_normal, up_reference));
	vec3 bitangent = cross(shading_normal, tangent);
	// Only the component of the gradient lying in the surface plane tilts the normal.
	vec2 slope = vec2(dot(relief_gradient, tangent), dot(relief_gradient, bitangent));
	// 0.07 rather than the sine era's 0.06: the noise gradient runs a little
	// hotter per unit of `normal_strength`, and this was tuned by eye against the
	// live render until the surface reads as sandblasted casting rather than
	// either flat plastic (too low) or camouflage blotching (too high).
	vec3 perturbed = normalize(shading_normal - (tangent * slope.x + bitangent * slope.y) * normal_strength * 0.07);

	float up_facing = clamp(dot(shading_normal, vec3(0.0, 1.0, 0.0)), 0.0, 1.0);

	// Grime pools in the recesses of the relief and on horizontal surfaces.  It
	// wants exactly the broad octave already computed above, so it reuses that
	// value rather than paying for a third set of eight hashes.
	float grime = noise_lo;
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
}

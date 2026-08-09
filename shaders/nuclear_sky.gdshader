shader_type sky;
// Night sky over the Concourse.
//
// A plain two-colour gradient reads as an empty void rather than as sky - there
// is nothing in it to give the eye scale or distance.  This adds the three cues
// that actually sell a sky, and nothing else: stars, one soft galactic band, and
// a warm lift where the facility's own lighting spills up past the wall line.
//
// Everything here is analytic.  There is no texture, no cubemap fetch and no
// per-frame CPU work, and `Sky.process_mode` stays on QUALITY so the radiance
// map for ambient and reflection is baked once rather than re-rendered.  The
// only recurring cost is a handful of hashes on the screen pixels that are sky,
// which on this map is the band above a 7.2 m perimeter wall.
//
// Two deliberate restraints:
//   - No green anywhere.  Nuclear-lime is reserved for the objective, and the
//     lighting sheet is explicit that it must never become ambient fill.  A
//     green sky would put the objective's own colour behind the whole map.
//   - Stars stay below the environment's glow threshold, so the objective
//     remains the only surface in the scene that blooms.

uniform vec3 zenith_color : source_color = vec3(0.031, 0.043, 0.086);
uniform vec3 midsky_color : source_color = vec3(0.055, 0.082, 0.125);
uniform vec3 horizon_color : source_color = vec3(0.110, 0.125, 0.157);
// Warm, low and tight to the horizon: light thrown up by the amber service
// fixtures rather than a sunset.
uniform vec3 horizon_glow : source_color = vec3(0.290, 0.200, 0.110);
uniform vec3 ground_color : source_color = vec3(0.027, 0.031, 0.035);
uniform vec3 star_cool : source_color = vec3(0.839, 0.898, 1.000);
uniform vec3 star_warm : source_color = vec3(1.000, 0.898, 0.780);
uniform float star_brightness : hint_range(0.0, 1.0) = 0.70;
uniform float band_strength : hint_range(0.0, 1.0) = 0.40;

float hash13(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 31.316;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// One octave of star field.  Each lattice cell either holds a star or does not,
// and `threshold` sets how sparse the layer is, so two calls at different scales
// give a dense faint layer under a sparse bright one without sorting anything.
float star_layer(vec3 direction, float scale, float threshold, float size, out float warmth) {
	vec3 point = direction * scale;
	vec3 cell = floor(point);
	vec3 local = fract(point) - 0.5;
	float present = hash13(cell);
	warmth = hash13(cell + 5.13);
	if (present < threshold) {
		return 0.0;
	}
	vec3 jitter = vec3(
		hash13(cell + 1.7), hash13(cell + 3.1), hash13(cell + 9.4)) - 0.5;
	float distance_to_star = length(local - jitter * 0.62);
	// Brightness varies per star so the field does not read as a uniform stipple.
	float magnitude = 0.35 + 0.65 * hash13(cell + 7.7);
	return smoothstep(size, 0.0, distance_to_star) * magnitude;
}

void sky() {
	vec3 direction = normalize(EYEDIR);
	float height = direction.y;
	float above = clamp(height, 0.0, 1.0);

	// Gradient: horizon into mid sky into zenith, weighted low so most of the
	// visible band above the wall line carries the darker values.
	vec3 color = mix(horizon_color, midsky_color, smoothstep(0.0, 0.28, above));
	color = mix(color, zenith_color, smoothstep(0.22, 0.85, above));

	// Facility light spilling upward - tight to the horizon so it never becomes
	// a general wash.
	float glow = pow(1.0 - above, 14.0);
	color += horizon_glow * glow * 0.55;

	// A single soft band of galactic haze, tilted off the vertical so it does
	// not sit parallel to the wall line.
	vec3 band_axis = normalize(vec3(0.42, 0.78, -0.46));
	float band = exp(-pow(dot(direction, band_axis) * 2.35, 2.0));
	color += vec3(0.086, 0.094, 0.133) * band * band_strength * above;

	// Stars fade out toward the horizon, where haze and the facility glow would
	// wash them out in reality.
	float star_fade = smoothstep(0.02, 0.30, above);
	float warm_a;
	float warm_b;
	float faint = star_layer(direction, 150.0, 0.900, 0.105, warm_a);
	float bright = star_layer(direction, 52.0, 0.945, 0.185, warm_b);
	// The band holds more stars, which is what makes it read as a galaxy rather
	// than as a smear of fog.
	faint *= 0.55 + band * 0.9;
	vec3 star_color = mix(star_cool, star_warm, warm_a * 0.85);
	color += star_color * faint * star_brightness * 0.80 * star_fade;
	color += mix(star_cool, star_warm, warm_b * 0.85) * bright * star_brightness * star_fade;

	// Below the horizon the map's own floor covers everything, so this only has
	// to stay dark and neutral.
	color = mix(ground_color, color, smoothstep(-0.06, 0.01, height));

	COLOR = color;
}

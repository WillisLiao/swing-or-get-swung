shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;

uniform vec4 base_tint : source_color = vec4(0.26, 0.40, 0.70, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.07, 0.12, 0.25, 1.0);
uniform vec4 rim_tint : source_color = vec4(0.80, 0.90, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.18;
uniform float glow_strength : hint_range(0.0, 8.0) = 0.0;
uniform float brush_scale : hint_range(0.1, 8.0) = 1.8;
uniform float noise_scale : hint_range(0.1, 8.0) = 2.4;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	// Broad irregular variation keeps large surfaces tactile without a repeated checker field.
	float broad_x = sin(world_position.x * brush_scale * 0.16 + world_position.z * 0.045);
	float broad_z = cos(world_position.z * brush_scale * 0.11 - world_position.x * 0.035);
	float brush = (broad_x * 0.65 + broad_z * 0.35) * 0.035;
	// Fine-grained noise breakup adds micro-variation without importing textures.
	float fine_a = sin(world_position.x * noise_scale * 1.7 + world_position.y * 0.9);
	float fine_b = cos(world_position.z * noise_scale * 1.3 - world_position.y * 1.1);
	float fine_noise = (fine_a * 0.5 + fine_b * 0.5) * 0.018;
	// Edge wear darkens horizontal-facing surfaces subtly, simulating dust/settling.
	float up_facing = clamp(dot(normalize(world_normal), vec3(0.0, 1.0, 0.0)), 0.0, 1.0);
	float wear_darken = up_facing * edge_wear * 0.15;
	ALBEDO = clamp(base_tint.rgb + vec3(brush + fine_noise - wear_darken), vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.82 + up_facing * edge_wear * 0.08;
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.4);
	EMISSION = base_tint.rgb * glow_strength + rim_tint.rgb * rim * rim_strength;
}

void light() {
	// Wrapped diffuse and a cool shadow tint make targets legible without photographic lighting.
	float wrapped = clamp((dot(NORMAL, LIGHT) + 0.28) / 1.28, 0.0, 1.0);
	float shaped = smoothstep(0.08, 0.9, wrapped);
	vec3 illustration_color = mix(shadow_tint.rgb, base_tint.rgb, shaped);
	DIFFUSE_LIGHT += illustration_color * LIGHT_COLOR * ATTENUATION * 0.58;
}

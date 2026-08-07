class_name RiftWeapons
extends RefCounted

## Data-driven table for the five Nuclear Rush weapons.
##
## This is a `const Dictionary`, not a `Resource` - the values are read inside
## the authoritative, replayable simulation path on every peer and must stay
## byte-identical between the host and every client.  A `.tres` on disk can
## drift between machines and a preloaded `Resource` is a shared mutable
## object; a `const` table in a script is version-locked with the code itself.
##
## Accuracy fields are half-angle cone radians, additive, and composed as:
##   hip = hip_base + hip_move*speed_t + hip_air*(airborne) - hip_crouch*(crouched) + hip_bloom_step*bloom
##   ads = ads_base + ads_move*speed_t + ads_air*(airborne) - ads_crouch*(crouched) + ads_bloom_step*bloom
##   cone = max(0, lerp(hip, ads, ads_progress))
## See Duelist.cone_for_weapon(). The sniper's ads_* fields are all zero, so
## a fully-scoped sniper shot is always perfectly on the reticle - the
## explicit "no ADS drift" requirement falls out of the formula rather than a
## special case.

const RIFLE := 0
const SMG := 1
const SHOTGUN := 2
const PISTOL := 3
const SNIPER := 4

const TABLE := {
	RIFLE: {
		"name": "Rift Carbine", "class_tag": "ar",
		"projectile_speed": 800.0, "damage_near": 23.0, "damage_far": 14.0,
		"falloff_start": 22.0, "falloff_end": 70.0, "max_range": 95.0,
		"pellets": 1, "pattern": "disc",
		"fire_interval": 0.086, "magazine_size": 30, "reserve_ammo": 90, "reload_seconds": 2.0,
		"ads_seconds": 0.22, "zoom_steps": [1.5],
		"optic_tip_local": Vector3(0.0, 0.295, -1.06), "ads_anchor": Vector3(0.0, -0.1121, -0.96),
		"hip_forward": 1.0, "hip_strafe": 0.76, "ads_move_scale": 0.82,
		"hip_base": 0.021, "hip_move": 0.020, "hip_air": 0.045, "hip_crouch": 0.006, "hip_bloom_step": 0.0055,
		"ads_base": 0.0026, "ads_move": 0.013, "ads_air": 0.055, "ads_crouch": 0.0012, "ads_bloom_step": 0.0022,
		"bloom_max": 5.0, "bloom_decay": 9.0,
		"melee_damage": 45.0, "melee_range": 2.0, "melee_cooldown": 0.85, "melee_anim": "rifle_butt",
	},
	SMG: {
		"name": "Riftline SMG", "class_tag": "smg",
		"projectile_speed": 620.0, "damage_near": 18.0, "damage_far": 9.0,
		"falloff_start": 12.0, "falloff_end": 34.0, "max_range": 60.0,
		"pellets": 1, "pattern": "disc",
		"fire_interval": 0.063, "magazine_size": 32, "reserve_ammo": 128, "reload_seconds": 1.7,
		"ads_seconds": 0.16, "zoom_steps": [1.25],
		"optic_tip_local": Vector3(0.0, 0.26, -0.82), "ads_anchor": Vector3(0.0, -0.108, -0.78),
		"hip_forward": 1.08, "hip_strafe": 0.88, "ads_move_scale": 0.88,
		"hip_base": 0.016, "hip_move": 0.008, "hip_air": 0.040, "hip_crouch": 0.004, "hip_bloom_step": 0.0075,
		"ads_base": 0.0055, "ads_move": 0.010, "ads_air": 0.048, "ads_crouch": 0.0020, "ads_bloom_step": 0.0055,
		"bloom_max": 8.0, "bloom_decay": 11.0,
		"melee_damage": 40.0, "melee_range": 1.9, "melee_cooldown": 0.70, "melee_anim": "smg_bash",
	},
	SHOTGUN: {
		"name": "S1897 Pump", "class_tag": "shotgun",
		"projectile_speed": 480.0, "damage_near": 12.0, "damage_far": 4.0,
		"falloff_start": 8.0, "falloff_end": 22.0, "max_range": 40.0,
		"pellets": 9, "pattern": "rosette",
		"fire_interval": 0.85, "magazine_size": 6, "reserve_ammo": 24, "reload_seconds": 2.6,
		"ads_seconds": 0.24, "zoom_steps": [1.15],
		"optic_tip_local": Vector3(0.0, 0.24, -0.88), "ads_anchor": Vector3(0.0, -0.115, -0.88),
		"hip_forward": 0.94, "hip_strafe": 0.72, "ads_move_scale": 0.78,
		"hip_base": 0.055, "hip_move": 0.012, "hip_air": 0.030, "hip_crouch": 0.006, "hip_bloom_step": 0.0060,
		"ads_base": 0.032, "ads_move": 0.010, "ads_air": 0.030, "ads_crouch": 0.0060, "ads_bloom_step": 0.0050,
		"bloom_max": 2.0, "bloom_decay": 4.0,
		"melee_damage": 55.0, "melee_range": 2.1, "melee_cooldown": 0.95, "melee_anim": "stock_smash",
	},
	PISTOL: {
		"name": "Sidearm 9", "class_tag": "pistol",
		"projectile_speed": 560.0, "damage_near": 26.0, "damage_far": 16.0,
		"falloff_start": 15.0, "falloff_end": 40.0, "max_range": 70.0,
		"pellets": 1, "pattern": "disc",
		"fire_interval": 0.14, "magazine_size": 12, "reserve_ammo": 60, "reload_seconds": 1.45,
		"ads_seconds": 0.14, "zoom_steps": [1.1],
		"optic_tip_local": Vector3(0.0, 0.20, -0.58), "ads_anchor": Vector3(0.0, -0.09, -0.62),
		"hip_forward": 1.12, "hip_strafe": 0.92, "ads_move_scale": 0.90,
		"hip_base": 0.012, "hip_move": 0.016, "hip_air": 0.038, "hip_crouch": 0.004, "hip_bloom_step": 0.0100,
		"ads_base": 0.0022, "ads_move": 0.010, "ads_air": 0.044, "ads_crouch": 0.0010, "ads_bloom_step": 0.0070,
		"bloom_max": 5.0, "bloom_decay": 12.0,
		"melee_damage": 35.0, "melee_range": 1.7, "melee_cooldown": 0.60, "melee_anim": "pistol_whip",
	},
	SNIPER: {
		"name": "Longview Mk1", "class_tag": "sniper",
		"projectile_speed": 1400.0, "damage_near": 90.0, "damage_far": 70.0,
		"falloff_start": 90.0, "falloff_end": 140.0, "max_range": 200.0,
		"pellets": 1, "pattern": "disc",
		"fire_interval": 1.30, "magazine_size": 4, "reserve_ammo": 12, "reload_seconds": 2.6,
		# Halo Infinite's S7 sniper is the named reference: a two-stage scope
		# (roughly 3x then a further zoom on a second press) and a deliberate,
		# felt ADS time rather than an instant snap. These are tuned to that
		# feel, not a literal citation of Halo's own numbers.
		"ads_seconds": 0.38, "zoom_steps": [3.0, 6.0],
		"optic_tip_local": Vector3(0.0, 0.30, -1.3), "ads_anchor": Vector3(0.0, -0.12, -1.05),
		"hip_forward": 0.88, "hip_strafe": 0.66, "ads_move_scale": 0.55,
		"hip_base": 0.085, "hip_move": 0.030, "hip_air": 0.050, "hip_crouch": 0.010, "hip_bloom_step": 0.0200,
		# Explicit design requirement: no ADS drift/sway. Every ads_* term is
		# zero so a fully scoped shot (ads_progress == 1.0) is always exactly
		# on the reticle, regardless of movement, stance, or follow-up shots.
		"ads_base": 0.0, "ads_move": 0.0, "ads_air": 0.0, "ads_crouch": 0.0, "ads_bloom_step": 0.0,
		"bloom_max": 2.0, "bloom_decay": 1.5,
		"melee_damage": 60.0, "melee_range": 2.2, "melee_cooldown": 1.05, "melee_anim": "scope_slam",
	},
}

const ORDER := [RIFLE, SMG, SHOTGUN, PISTOL, SNIPER]

static func row(weapon: int) -> Dictionary:
	return TABLE[weapon] if TABLE.has(weapon) else TABLE[RIFLE]

static func clamp_weapon(value: int) -> int:
	return value if TABLE.has(value) else RIFLE

## Cone half-angle in radians for a shot fired under the given kinematic
## state. Pure function of the weapon row and four already-networked/
## snapshotted inputs - no wall-clock time, no RNG, no physics-server query -
## so it produces the same answer on every peer replaying the same frame.
## `speed_t` is the caller's horizontal speed already normalized to [0, 1].
static func cone_for(weapon: int, speed_t: float, crouched: bool, airborne: bool, ads_progress: float, bloom: float) -> float:
	var facts := row(weapon)
	var bloom_c := minf(bloom, float(facts.bloom_max))
	var hip := float(facts.hip_base) + float(facts.hip_move) * speed_t \
		+ float(facts.hip_air) * (1.0 if airborne else 0.0) \
		- float(facts.hip_crouch) * (1.0 if crouched else 0.0) \
		+ float(facts.hip_bloom_step) * bloom_c
	var ads := float(facts.ads_base) + float(facts.ads_move) * speed_t \
		+ float(facts.ads_air) * (1.0 if airborne else 0.0) \
		- float(facts.ads_crouch) * (1.0 if crouched else 0.0) \
		+ float(facts.ads_bloom_step) * bloom_c
	return maxf(0.0, lerpf(hip, ads, clampf(ads_progress, 0.0, 1.0)))

## Stateless integer hash so pellet/shot dispersion is a pure function of
## (actor, shot index, pellet index) and never depends on an RNG object's
## internal state, which is not part of the networked snapshot.
static func _mix(a: int, b: int, c: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7FFFFFFF

static func _unit(h: int) -> float:
	return float(h & 0xFFFFFF) / 16777216.0

## Deterministic pellet directions for one shot. Always returns at least one
## entry. Non-shotgun weapons return a single "disc" sample; the shotgun
## returns a fixed, rotated rosette (a center pellet plus eight around it)
## rather than independent draws, so the spread pattern is one the player can
## learn instead of being pure per-shot variance.
static func pellet_offsets(weapon: int, actor_hash: int, shot_index: int, cone: float) -> Array[Vector2]:
	var facts := row(weapon)
	var pellets := int(facts.pellets)
	var offsets: Array[Vector2] = []
	if cone <= 0.0000001 or pellets <= 0:
		for _i in maxi(1, pellets):
			offsets.append(Vector2.ZERO)
		return offsets
	if String(facts.pattern) == "rosette" and pellets > 1:
		offsets.append(Vector2.ZERO)
		var phase := TAU * _unit(_mix(actor_hash, shot_index, 0))
		for i in range(1, pellets):
			var jitter := (_unit(_mix(actor_hash, shot_index, i)) * 2.0 - 1.0) * cone * 0.09
			var radius := cone * 0.66 + jitter
			var theta := phase + float(i - 1) * TAU / float(pellets - 1)
			offsets.append(Vector2(cos(theta), sin(theta)) * radius)
		return offsets
	for i in pellets:
		var u0 := _unit(_mix(actor_hash, shot_index, i * 2))
		var u1 := _unit(_mix(actor_hash, shot_index, i * 2 + 1))
		var radius := cone * sqrt(u0)
		var theta := TAU * u1
		offsets.append(Vector2(cos(theta), sin(theta)) * radius)
	return offsets

## Horizontal-FOV-preserving magnification: derived from the base horizontal
## FOV so the sniper's two scope steps and every other weapon's optic sit on
## the same representation instead of a hand-tuned FOV ratio per weapon.
static func ads_horizontal_fov(base_horizontal_fov: float, weapon: int, zoom_index: int) -> float:
	var facts := row(weapon)
	var steps: Array = facts.zoom_steps
	var magnification: float = float(steps[clampi(zoom_index, 0, steps.size() - 1)]) if not steps.is_empty() else 1.0
	if magnification <= 0.0001:
		return base_horizontal_fov
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_horizontal_fov) * 0.5) / magnification))

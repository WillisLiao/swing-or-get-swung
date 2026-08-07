extends SceneTree

func _initialize() -> void:
	assert(Duelist.Weapon.SMG == 1 and Duelist.Weapon.SHOTGUN == 2 and Duelist.Weapon.PISTOL == 3 and Duelist.Weapon.SNIPER == 4)
	var rifle_hip := Duelist.standing_speed_profile(Duelist.Weapon.RIFLE, false)
	var rifle_ads := Duelist.standing_speed_profile(Duelist.Weapon.RIFLE, true)
	var smg_hip := Duelist.standing_speed_profile(Duelist.Weapon.SMG, false)
	var sniper_ads := Duelist.standing_speed_profile(Duelist.Weapon.SNIPER, true)
	assert(is_equal_approx(float(rifle_hip.forward), 7.2))
	assert(is_equal_approx(float(rifle_hip.lateral), 5.472))
	assert(is_equal_approx(float(rifle_ads.forward), 5.904))
	assert(is_equal_approx(float(rifle_ads.lateral), 4.48704))
	# The SMG is quicker on its feet hip-fire than the carbine - the MP7
	# reference is a run-and-gun weapon, not a marksman rifle.
	assert(float(smg_hip.forward) > float(rifle_hip.forward))
	# The sniper is explicitly the slowest weapon to move while aiming - its
	# ads_move_scale (0.55) is well below every other weapon's.
	assert(float(sniper_ads.forward) < float(rifle_ads.forward) * 0.8)
	# An out-of-range weapon id falls back to the rifle's mobility profile
	# rather than crashing or defaulting to zero.
	assert(is_equal_approx(float(Duelist.mobility_facts(99 as Duelist.Weapon).get("hip_strafe", 0.0)), 0.76))

	# Every weapon now ADS's through an optic (no iron sights): the shot
	# origin under ADS sits at that weapon's calibrated optic tip, offset
	# from the raw eye position, and every weapon has a distinct tip.
	var eye := Vector3(1.0, 2.0, 3.0)
	var rifle_ads_origin := Duelist.shot_origin_for(eye, Basis.IDENTITY, true, Duelist.Weapon.RIFLE)
	assert(rifle_ads_origin.distance_to(eye + Duelist.optic_tip_head_offset(int(Duelist.Weapon.RIFLE))) < 0.001)
	assert(rifle_ads_origin.distance_to(eye) > 0.01)
	var sniper_ads_origin := Duelist.shot_origin_for(eye, Basis.IDENTITY, true, Duelist.Weapon.SNIPER)
	assert(sniper_ads_origin.distance_to(rifle_ads_origin) > 0.01)
	# Hipfire always leaves the raw eye position - there is no optic offset
	# unless actually aiming.
	var hip_origin := Duelist.shot_origin_for(eye, Basis.IDENTITY, false, Duelist.Weapon.RIFLE)
	assert(hip_origin.distance_to(eye) < 0.001)

	# The accuracy cone: sniper ADS is exactly zero (no drift) regardless of
	# movement/stance/bloom, while every other weapon's ADS cone is nonzero
	# stationary-crouched-and-still and hip cone is worse than ADS cone.
	assert(is_zero_approx(RiftWeapons.cone_for(RiftWeapons.SNIPER, 1.0, false, true, 1.0, 5.0)))
	assert(is_zero_approx(RiftWeapons.cone_for(RiftWeapons.SNIPER, 0.0, false, false, 1.0, 0.0)))
	var rifle_hip_cone := RiftWeapons.cone_for(RiftWeapons.RIFLE, 0.0, false, false, 0.0, 0.0)
	var rifle_ads_cone := RiftWeapons.cone_for(RiftWeapons.RIFLE, 0.0, false, false, 1.0, 0.0)
	assert(rifle_ads_cone < rifle_hip_cone)
	assert(rifle_ads_cone > 0.0)
	# Moving, airborne, and sustained-fire bloom all widen the cone.
	var rifle_moving_cone := RiftWeapons.cone_for(RiftWeapons.RIFLE, 1.0, false, false, 0.0, 0.0)
	assert(rifle_moving_cone > rifle_hip_cone)
	var rifle_air_cone := RiftWeapons.cone_for(RiftWeapons.RIFLE, 0.0, false, true, 0.0, 0.0)
	assert(rifle_air_cone > rifle_hip_cone)
	var rifle_bloom_cone := RiftWeapons.cone_for(RiftWeapons.RIFLE, 0.0, false, false, 0.0, 5.0)
	assert(rifle_bloom_cone > rifle_hip_cone)
	# Crouching tightens the hip cone relative to standing still.
	var rifle_crouch_cone := RiftWeapons.cone_for(RiftWeapons.RIFLE, 0.0, true, false, 0.0, 0.0)
	assert(rifle_crouch_cone < rifle_hip_cone)

	# Shotgun pellets: a fixed, rotated rosette, deterministic per (actor,
	# shot), not independent draws - firing the same shot index twice with
	# the same actor hash reproduces the identical pattern.
	var facts := RiftWeapons.row(RiftWeapons.SHOTGUN)
	assert(int(facts.pellets) > 1)
	var pattern_a := RiftWeapons.pellet_offsets(RiftWeapons.SHOTGUN, 12345, 0, 0.05)
	var pattern_b := RiftWeapons.pellet_offsets(RiftWeapons.SHOTGUN, 12345, 0, 0.05)
	assert(pattern_a.size() == int(facts.pellets))
	for index in pattern_a.size():
		assert((pattern_a[index] as Vector2).distance_to(pattern_b[index] as Vector2) < 0.0001)
	# A different shot index reshuffles the pattern - it is not a static prop.
	var pattern_c := RiftWeapons.pellet_offsets(RiftWeapons.SHOTGUN, 12345, 1, 0.05)
	assert(not (pattern_a[1] as Vector2).is_equal_approx(pattern_c[1] as Vector2))
	# Every non-shotgun weapon fires exactly one pellet.
	for weapon_id in [RiftWeapons.RIFLE, RiftWeapons.SMG, RiftWeapons.PISTOL, RiftWeapons.SNIPER]:
		assert(RiftWeapons.pellet_offsets(weapon_id, 1, 0, 0.05).size() == 1)

	print("Riftline weapon mobility exercise: PASS")
	quit()

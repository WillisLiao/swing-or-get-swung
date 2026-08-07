extends SceneTree

func _initialize() -> void:
	var narrow_vertical := Duelist.vertical_fov_for_horizontal(Duelist.DEFAULT_HORIZONTAL_FOV, 4.0 / 3.0)
	var wide_vertical := Duelist.vertical_fov_for_horizontal(Duelist.DEFAULT_HORIZONTAL_FOV, 16.0 / 9.0)
	assert(narrow_vertical > wide_vertical)
	assert(is_equal_approx(Duelist.vertical_fov_for_horizontal(80.0, 1.0), 80.0))
	assert(absf(Duelist.vertical_fov_for_horizontal(80.0, 2622.0 / 1206.0) - 42.2) < 0.2)
	# Iron sights are gone - ADS magnification is expressed per weapon as real
	# zoom steps, not one global FOV ratio. Every weapon narrows its FOV while
	# aimed, and the sniper's two zoom steps narrow it progressively further.
	var rifle_ads_fov := RiftWeapons.ads_horizontal_fov(Duelist.DEFAULT_HORIZONTAL_FOV, RiftWeapons.RIFLE, 0)
	assert(rifle_ads_fov < Duelist.DEFAULT_HORIZONTAL_FOV)
	var sniper_zoom0_fov := RiftWeapons.ads_horizontal_fov(Duelist.DEFAULT_HORIZONTAL_FOV, RiftWeapons.SNIPER, 0)
	var sniper_zoom1_fov := RiftWeapons.ads_horizontal_fov(Duelist.DEFAULT_HORIZONTAL_FOV, RiftWeapons.SNIPER, 1)
	assert(sniper_zoom1_fov < sniper_zoom0_fov)
	assert(sniper_zoom0_fov < rifle_ads_fov)

	var rifle_reload_seconds := float(RiftWeapons.row(RiftWeapons.RIFLE).reload_seconds)
	assert(is_equal_approx(DuelHud.reload_progress_for(rifle_reload_seconds, rifle_reload_seconds), 0.0))
	assert(is_equal_approx(DuelHud.reload_progress_for(0.0, rifle_reload_seconds), 1.0))
	assert(DuelHud.reload_progress_for(-4.0, rifle_reload_seconds) == 1.0)

	# There is no dedicated melee weapon - every weapon carries its own melee
	# range/damage/cooldown in the RiftWeapons table instead of one universal
	# knife constant, and they are not all identical (a shotgun butt-stroke
	# hits harder than a pistol whip).
	var rifle_melee := float(RiftWeapons.row(RiftWeapons.RIFLE).melee_damage)
	var pistol_melee := float(RiftWeapons.row(RiftWeapons.PISTOL).melee_damage)
	var shotgun_melee := float(RiftWeapons.row(RiftWeapons.SHOTGUN).melee_damage)
	assert(rifle_melee > 0.0 and pistol_melee > 0.0 and shotgun_melee > 0.0)
	assert(shotgun_melee > pistol_melee)

	print("Riftline view and feedback exercise: PASS")
	quit()

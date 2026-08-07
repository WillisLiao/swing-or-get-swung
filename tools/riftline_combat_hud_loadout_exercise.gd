extends SceneTree

func _initialize() -> void:
	var hud := DuelHud.new()
	get_root().add_child(hud)
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(1334.0, 750.0)
	await process_frame
	hud.set_weapon(Duelist.Weapon.RIFLE)
	assert(hud._weapon == Duelist.Weapon.RIFLE)
	var rifle_reload_seconds := float(RiftWeapons.row(int(Duelist.Weapon.RIFLE)).reload_seconds)
	hud.show_ammo(12, 48, rifle_reload_seconds)
	assert(is_equal_approx(DuelHud.reload_progress_for(hud.reload_remaining, rifle_reload_seconds), 0.0))
	# Ammo caps to the weapon actually equipped, not a fixed carbine constant.
	hud.set_weapon(Duelist.Weapon.SNIPER)
	assert(hud._weapon == Duelist.Weapon.SNIPER)
	var sniper_capacity := int(RiftWeapons.row(int(Duelist.Weapon.SNIPER)).magazine_size)
	hud.show_ammo(sniper_capacity + 50, 0, 0.0)
	assert(hud.magazine_rounds == sniper_capacity)
	# The two-slot loadout indicator reflects the actual loadout, not a fixed
	# rifle/knife pair.
	hud.set_loadout_slots([Duelist.Weapon.SHOTGUN, Duelist.Weapon.PISTOL])
	assert(hud._loadout_slots.size() == 2)
	hud.show_ammo(0, 0, 0.0)
	assert(hud.reload_remaining == 0.0)
	assert(not hud._settings_open)
	hud.free()
	print("Riftline combat HUD loadout exercise: PASS")
	quit()

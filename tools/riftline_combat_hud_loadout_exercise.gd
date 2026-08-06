extends SceneTree

func _initialize() -> void:
	var hud := DuelHud.new()
	get_root().add_child(hud)
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = Vector2(1334.0, 750.0)
	await process_frame
	hud.set_weapon(Duelist.Weapon.PULSE)
	assert(hud._weapon == Duelist.Weapon.PULSE)
	hud.show_ammo(12, 48, Duelist.M4_RELOAD_SECONDS)
	assert(is_equal_approx(DuelHud.reload_progress_for(hud.reload_remaining), 0.0))
	hud.set_weapon(Duelist.Weapon.KNIFE)
	assert(hud._weapon == Duelist.Weapon.KNIFE)
	hud.show_ammo(0, 0, 0.0)
	assert(hud.reload_remaining == 0.0)
	assert(not hud._settings_open)
	hud.free()
	print("Riftline combat HUD loadout exercise: PASS")
	quit()

extends RefCounted

## Presentation-only layout seam for landscape iPhone and iPad surfaces.
## DisplayServer can report safe-area pixels in a different coordinate space
## from a Control, so the accepted rectangle is explicitly reprojected into
## the Control's local space instead of silently falling back to 24 pixels.

static func safe_rect(control: Control, fallback_inset: float = 24.0) -> Rect2:
	var fallback := Rect2(
		fallback_inset,
		fallback_inset,
		maxf(1.0, control.size.x - fallback_inset * 2.0),
		maxf(1.0, control.size.y - fallback_inset * 2.0))
	if control.size.x <= 0.0 or control.size.y <= 0.0:
		return fallback
	var display_safe := DisplayServer.get_display_safe_area()
	if display_safe.size.x <= 0 or display_safe.size.y <= 0:
		return fallback
	var source_size := Vector2(DisplayServer.window_get_size())
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		source_size = control.size
	var scale := Vector2(control.size.x / source_size.x, control.size.y / source_size.y)
	var candidate := Rect2(Vector2(display_safe.position) * scale, Vector2(display_safe.size) * scale)
	var clipped := candidate.intersection(Rect2(Vector2.ZERO, control.size))
	if clipped.size.x < 1.0 or clipped.size.y < 1.0:
		return fallback
	return clipped

static func metrics(control: Control) -> Dictionary:
	var scale := clampf(minf(control.size.x / 1280.0, control.size.y / 588.0), 0.78, 1.35)
	return {
		"scale": scale,
		"inset": clampf(24.0 * scale, 18.0, 42.0),
		"touch_target": maxf(44.0, 44.0 * scale),
		"gap": clampf(8.0 * scale, 8.0, 14.0),
		"stroke": clampf(1.5 * scale, 1.2, 2.4),
		"font_small": clampi(int(round(13.0 * scale)), 12, 18),
		"font_body": clampi(int(round(15.0 * scale)), 14, 21),
		"font_title": clampi(int(round(28.0 * scale)), 24, 38),
	}

static func normalized_center(point: Vector2, safe: Rect2) -> Vector2:
	return Vector2(
		clampf((point.x - safe.position.x) / maxf(1.0, safe.size.x), 0.0, 1.0),
		clampf((point.y - safe.position.y) / maxf(1.0, safe.size.y), 0.0, 1.0))

static func project_center(normalized: Vector2, safe: Rect2) -> Vector2:
	return safe.position + normalized * safe.size

class_name Icons
extends RefCounted
## Векторные иконки ресурсов, рисуются на любом CanvasItem.

static func draw(ci: CanvasItem, res: String, c: Vector2, s: float, col: Color) -> void:
	var art := Art.icon(res)
	if art:
		ci.draw_texture_rect(art, Rect2(c - Vector2(s, s) * 1.2, Vector2(s, s) * 2.4), false)
		return
	match res:
		"energy":
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.25, -1.0) * s, c + Vector2(-0.55, 0.15) * s, c + Vector2(-0.05, 0.15) * s,
				c + Vector2(-0.25, 1.0) * s, c + Vector2(0.55, -0.15) * s, c + Vector2(0.05, -0.15) * s]), col)
		"oxygen":
			ci.draw_arc(c + Vector2(-0.25, 0.25) * s, 0.55 * s, 0, TAU, 20, col, maxf(2.0, s * 0.18))
			ci.draw_arc(c + Vector2(0.5, -0.5) * s, 0.32 * s, 0, TAU, 16, col, maxf(1.5, s * 0.14))
			ci.draw_circle(c + Vector2(-0.45, 0.05) * s, 0.12 * s, Color(1, 1, 1, 0.8))
		"food":
			ci.draw_line(c + Vector2(0, 1.0) * s, c + Vector2(0, -0.1) * s, col.darkened(0.2), maxf(2.0, s * 0.18))
			ci.draw_colored_polygon(_leaf(c + Vector2(0, -0.1) * s, Vector2(-0.8, -0.6) * s), col)
			ci.draw_colored_polygon(_leaf(c + Vector2(0, 0.3) * s, Vector2(0.8, -0.5) * s), col)
		"pearls":
			ci.draw_circle(c, 0.75 * s, col)
			ci.draw_circle(c + Vector2(0.1, 0.1) * s, 0.55 * s, col.lightened(0.3))
			ci.draw_circle(c + Vector2(-0.28, -0.28) * s, 0.2 * s, Color(1, 1, 1, 0.95))
		"crystals":
			var g := PackedVector2Array([c + Vector2(0, -1.0) * s, c + Vector2(0.7, -0.3) * s,
				c + Vector2(0, 1.0) * s, c + Vector2(-0.7, -0.3) * s])
			ci.draw_colored_polygon(g, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -1.0) * s, c + Vector2(0.7, -0.3) * s,
				c + Vector2(0, -0.1) * s, c + Vector2(-0.7, -0.3) * s]), col.lightened(0.45))
			ci.draw_polyline(PackedVector2Array([g[0], g[1], g[2], g[3], g[0]]), col.darkened(0.4), maxf(1.0, s * 0.1))
		"people":
			ci.draw_circle(c + Vector2(0, -0.45) * s, 0.35 * s, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.65, 0.95) * s,
				c + Vector2(-0.5, 0.1) * s, c + Vector2(0.5, 0.1) * s, c + Vector2(0.65, 0.95) * s]), col)

static func _leaf(base: Vector2, tip: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := Vector2(-tip.y, tip.x) * 0.35
	for i in 9:
		var k := i / 8.0
		pts.append(base + tip * k + n * sin(k * PI))
	for i in range(8, -1, -1):
		var k := i / 8.0
		pts.append(base + tip * k - n * sin(k * PI))
	return pts

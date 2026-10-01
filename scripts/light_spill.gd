extends Node2D
## Свет из отсеков на скале вокруг: мягкие ореолы цвета отсека (аддитивно),
## тёплый свет от купола у шлюза. Рисуется позади отсеков, поверх породы.

var view: Node2D
var glow: Texture2D

func _ready() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	glow = gt
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat

func _process(_delta: float) -> void:
	visible = Audio.hq_graphics
	if visible:
		queue_redraw()

func _draw() -> void:
	if view == null:
		return
	var t: float = view.t
	var powered: bool = Game.resources.energy > 0.0
	for r in Game.rooms:
		if r.type == "elevator":
			continue
		var rect: Rect2 = view.room_rect(r)
		var col: Color = Defs.ROOMS[r.type].color
		var light := 1.0 if (powered or r.type == "reactor") else 0.3
		var a := 0.6 * light
		if r.type == "reactor":
			a *= 1.0 + 0.35 * sin(t * 3.0)
		if r.get("incident", 0.0) > 0.0 and r.get("hazard", "") == "fire":
			col = Color(1.0, 0.45, 0.1)
			a = 1.0 + 0.2 * sin(t * 14.0)
		var size := Vector2(rect.size.x * 2.1, rect.size.y * 2.5)
		draw_texture_rect(glow, Rect2(rect.get_center() - size / 2.0, size), false, Color(col.lightened(0.25), a))
	# свет купола над шлюзом
	var al: Dictionary = Game.find_room_of_type("airlock")
	if not al.is_empty():
		var c: Vector2 = view.room_rect(al).get_center() + Vector2(0, -170)
		var s := Vector2(520, 360)
		draw_texture_rect(glow, Rect2(c - s / 2.0, s), false, Color(1.0, 0.8, 0.45, 0.16 + 0.04 * sin(t * 1.3)))

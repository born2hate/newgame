extends Node2D
## Вид колонии в разрезе: рисует скалу, отсеки, колонистов; обрабатывает касания.

signal room_selected(room_id: int)
signal build_finished
signal colonist_selected(colonist_id: int)

const CELL_W := 100.0
const CELL_H := 130.0
const WALL := 6.0
const SUIT_COLORS := [
	Color(1.0, 0.55, 0.2), Color(0.95, 0.85, 0.25), Color(0.4, 0.8, 1.0),
	Color(0.9, 0.4, 0.6), Color(0.55, 0.95, 0.5), Color(0.85, 0.85, 0.9),
]

var camera: Camera2D
var build_type := ""
var selected_room := -1
var t := 0.0

# состояние касаний
var touches := {}
var drag_colonist := -1
var drag_pos := Vector2.ZERO
var press_pos := Vector2.ZERO
var moved := false
var pinch_dist := 0.0

# анимация колонистов: id -> {x, target, wait, facing}
var walkers := {}
# всплывающие надписи: {pos, text, color, life}
var floaters: Array = []
var fish: Array = []
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in 7:
		fish.append({
			"p": Vector2(r.randf_range(-600, 1400), r.randf_range(-560, -80)),
			"v": r.randf_range(25, 70) * (1 if r.randf() > 0.5 else -1),
			"s": r.randf_range(0.6, 1.4), "ph": r.randf() * TAU,
		})
	Game.floating_text.connect(_on_floating_text)
	var rock := Polygon2D.new()
	rock.polygon = PackedVector2Array([Vector2(-1400, 0), Vector2(2200, 0), Vector2(2200, 4000), Vector2(-1400, 4000)])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rock.gdshader")
	rock.material = mat
	var rock_tex := Art.tex("res://art/backgrounds/rock.png")
	if rock_tex:
		mat.set_shader_parameter("rock_tex", rock_tex)
		mat.set_shader_parameter("use_tex", true)
	rock.show_behind_parent = true
	add_child(rock)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func _process(delta: float) -> void:
	t += delta
	_update_walkers(delta)
	for f in fish:
		f.p.x += f.v * delta
		if f.p.x > 1600: f.p.x = -800
		if f.p.x < -800: f.p.x = 1600
	for fl in floaters:
		fl.life -= delta
		fl.pos.y -= 40 * delta
	floaters = floaters.filter(func(fl): return fl.life > 0)
	queue_redraw()

# ---------------------------------------------------------------- геометрия

func room_rect(r: Dictionary) -> Rect2:
	return Rect2(r.col * CELL_W, r.row * CELL_H, Defs.room_width(r.type) * CELL_W, CELL_H)

func cell_at(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / CELL_W), floori(world.y / CELL_H))

func screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p

func colonist_world_pos(c: Dictionary) -> Vector2:
	var rid: int = c.help if c.get("help", -1) != -1 else c.room
	var room: Dictionary = Game.get_room(rid) if rid != -1 else Game.find_room_of_type("airlock")
	if room.is_empty():
		return Vector2.ZERO
	var rect := room_rect(room)
	var w: Dictionary = walkers.get(c.id, {})
	var x: float = w.get("x", 0.5)
	return Vector2(rect.position.x + 22 + x * (rect.size.x - 44), rect.end.y - WALL - 2)

func _update_walkers(delta: float) -> void:
	var alive := {}
	for c in Game.colonists:
		alive[c.id] = true
		if not walkers.has(c.id):
			walkers[c.id] = {"x": randf(), "target": randf(), "wait": randf() * 2.0, "facing": 1.0, "room": c.room}
		var w: Dictionary = walkers[c.id]
		var here: int = c.help if c.get("help", -1) != -1 else c.room
		if w.room != here:
			w.room = here
			w.x = randf()
		var danger := false
		if here >= 0:
			danger = Game.get_room(here).get("incident", 0.0) > 0.0
		w["panic"] = danger
		if danger:
			w.wait = 0.0
		if w.wait > 0.0:
			w.wait -= delta
			continue
		var d: float = w.target - w.x
		if absf(d) < 0.01:
			w.wait = randf_range(1.0, 4.0)
			w.target = randf()
		else:
			w.facing = signf(d)
			w.x += signf(d) * minf(absf(d), delta * (0.9 if w.get("panic", false) else 0.25))
	for id in walkers.keys():
		if not alive.has(id):
			walkers.erase(id)

func _on_floating_text(room_id: int, text: String, color: Color) -> void:
	var r := Game.get_room(room_id)
	if r.is_empty():
		return
	var rect := room_rect(r)
	floaters.append({"pos": rect.get_center() - Vector2(0, 30), "text": text, "color": color, "life": 1.6})

# ---------------------------------------------------------------- отрисовка

func _draw() -> void:
	var depth_rows := maxi(Game.max_row() + 4, 6)
	_draw_water_life()
	if Art.tex("res://art/backgrounds/seabed.png"):
		_draw_seabed_art()
	else:
		_draw_seabed_procedural()
	_draw_bubbles()
	# выдолбленная порода вокруг отсеков
	for r in Game.rooms:
		draw_rect(room_rect(r).grow(10), Color(0.02, 0.02, 0.03, 0.55))
	for r in Game.rooms:
		draw_rect(room_rect(r).grow(5), Color(0.05, 0.05, 0.07))
	_draw_rest(depth_rows)

func _draw_seabed_art() -> void:
	var tex := Art.tex("res://art/backgrounds/seabed.png")
	var h := 230.0
	var w := h * tex.get_width() / tex.get_height()
	var top := -185.0
	var i := 0
	var x := -1400.0
	while x < 2200.0:
		# каждую вторую полосу зеркалим, чтобы не было видно стыков
		if i % 2 == 1:
			draw_set_transform(Vector2(x + w, top), 0.0, Vector2(-1, 1))
		else:
			draw_set_transform(Vector2(x, top))
		draw_texture_rect(tex, Rect2(0, 0, w, h), false)
		x += w
		i += 1
	draw_set_transform(Vector2.ZERO)
	# вход в колонию — купол над шлюзом
	var dome := Art.tex("res://art/backgrounds/dome.png")
	var al := Game.find_room_of_type("airlock")
	if dome and not al.is_empty():
		var dw := 300.0
		var dh := dw * dome.get_height() / dome.get_width()
		var cx := room_rect(al).get_center().x
		draw_texture_rect(dome, Rect2(cx - dw / 2.0, 18.0 - dh, dw, dh), false)
		var blink := 0.5 + 0.5 * sin(t * 3.0)
		draw_circle(Vector2(cx - 2, 18.0 - dh + 12), 10, Color(1.0, 0.7, 0.2, 0.35 * blink))

func _draw_seabed_procedural() -> void:
	var sand := PackedVector2Array()
	for i in 57:
		var x := -1000.0 + i * 50.0
		sand.append(Vector2(x, -14 + sin(x * 0.013) * 8 + sin(x * 0.041) * 4))
	sand.append(Vector2(1800, 6))
	sand.append(Vector2(-1000, 6))
	draw_colored_polygon(sand, Color(0.55, 0.47, 0.34))
	var sand_top := PackedVector2Array()
	for i in 56:
		sand_top.append(sand[i])
	draw_polyline(sand_top, Color(0.75, 0.66, 0.48), 4.0)
	_draw_corals()

func _draw_rest(depth_rows: int) -> void:
	if build_type != "":
		_draw_build_slots(depth_rows)
	for r in Game.rooms:
		_draw_room(r)
	_draw_doors()
	for c in Game.colonists:
		if c.id != drag_colonist and c.room != Game.ON_EXPEDITION:
			_draw_colonist(colonist_world_pos(c), c, false)
	if drag_colonist != -1:
		var c := Game.get_colonist(drag_colonist)
		if not c.is_empty():
			var hover := Game.room_at(cell_at(drag_pos).x, cell_at(drag_pos).y)
			if not hover.is_empty():
				draw_rect(room_rect(hover).grow(-2), Color(1, 1, 1, 0.8), false, 4.0)
			_draw_colonist(drag_pos + Vector2(0, 30), c, true)
	_draw_pet()
	for fl in floaters:
		var a := clampf(fl.life, 0.0, 1.0)
		_text(fl.pos, fl.text, 30, Color(fl.color, a), true)

## Питомец плавает восьмёркой перед отсеками верхних уровней.
func _draw_pet() -> void:
	if Game.pet == "":
		return
	var tex := Art.tex("res://art/creatures/%s.png" % Game.pet)
	if tex == null:
		return
	var span := Defs.GRID_COLS * CELL_W
	var rows := maxf(1.0, Game.max_row() + 1.0)
	var px := span * 0.5 + sin(t * 0.25) * span * 0.42
	var py := CELL_H * rows * 0.5 + sin(t * 0.5) * CELL_H * rows * 0.35
	var dir := signf(cos(t * 0.25))
	var fw := 64.0
	var fh := fw * tex.get_height() / tex.get_width()
	draw_set_transform(Vector2(px, py + sin(t * 3.0) * 4.0), sin(t * 3.0) * 0.08, Vector2(-dir, 1))
	draw_texture_rect(tex, Rect2(-fw / 2.0, -fh / 2.0, fw, fh), false)
	draw_set_transform(Vector2.ZERO)
	# пузырьки за хвостом
	for i in 3:
		var ph := fmod(t * 0.8 + i * 0.33, 1.0)
		draw_arc(Vector2(px - dir * (fw * 0.5 + ph * 10), py - ph * 40), 2.5 + ph * 2, 0, TAU, 10, Color(0.8, 0.95, 1.0, 0.7 * (1.0 - ph)), 1.2)

func _draw_water_life() -> void:
	var fishy := Art.tex("res://art/creatures/anglerfish.png")
	if fishy:
		# редко проплывает вдалеке
		var cycle := fmod(t, 70.0)
		if cycle < 40.0:
			var fw := 170.0
			var fh := fw * fishy.get_height() / fishy.get_width()
			var fx := 1500.0 - cycle * 55.0
			draw_texture_rect(fishy, Rect2(fx, -620 + sin(t * 0.7) * 20, fw, fh), false, Color(0.55, 0.6, 0.8, 0.7))
	var sub := Art.tex("res://art/creatures/bathyscaphe.png")
	if sub:
		var sw := 150.0
		var sh := sw * sub.get_height() / sub.get_width()
		var sx := fmod(t * 35.0, 2600.0) - 900.0
		draw_texture_rect(sub, Rect2(sx, -470 + sin(t * 0.8) * 10, sw, sh), false, Color(0.85, 0.9, 1.0, 0.95))
	for f in fish:
		var p: Vector2 = f.p + Vector2(0, sin(t * 1.5 + f.ph) * 6)
		var s: float = f.s
		var dir := signf(f.v)
		var col := Color(0.55, 0.85, 1.0, 0.35)
		var body := PackedVector2Array()
		for i in 12:
			var a := i / 12.0 * TAU
			body.append(p + Vector2(cos(a) * 22 * s, sin(a) * 9 * s))
		draw_colored_polygon(body, col)
		var tail := p + Vector2(-dir * 20 * s, 0)
		draw_colored_polygon(PackedVector2Array([
			tail, tail + Vector2(-dir * 14 * s, -10 * s), tail + Vector2(-dir * 14 * s, 10 * s)]), col)

func _draw_corals() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for i in 26:
		var x := r.randf_range(-950, 1750)
		if x > -40 and x < Defs.GRID_COLS * CELL_W + 40 and r.randf() < 0.7:
			continue
		var h := r.randf_range(30, 90)
		var hue := r.randf_range(0.85, 1.1)
		var col := Color.from_hsv(fmod(hue, 1.0), 0.6, 0.9, 0.9)
		var sway := sin(t * 1.2 + i) * 6
		draw_line(Vector2(x, -8), Vector2(x + sway, -8 - h), col, 7.0)
		draw_line(Vector2(x + sway * 0.5, -8 - h * 0.5), Vector2(x + sway + 16, -8 - h * 0.8), col, 5.0)
		draw_line(Vector2(x + sway * 0.4, -8 - h * 0.4), Vector2(x + sway - 14, -8 - h * 0.65), col, 5.0)
	# ламинарии
	for i in 18:
		var x := r.randf_range(-950, 1750)
		if x > -60 and x < Defs.GRID_COLS * CELL_W + 60:
			continue
		var h := r.randf_range(120, 300)
		var pts := PackedVector2Array()
		for k in 12:
			var f := k / 11.0
			pts.append(Vector2(x + sin(t * 0.9 + i + f * 3.0) * 18.0 * f, -6 - h * f))
		draw_polyline(pts, Color(0.2, 0.55, 0.3, 0.75), 6.0)
		for k in range(2, 11, 2):
			var q := pts[k]
			draw_colored_polygon(Icons._leaf(q, Vector2(20 if k % 4 == 0 else -20, -14)), Color(0.25, 0.65, 0.35, 0.7))
	# шлюз-купол над входом
	var al := Game.find_room_of_type("airlock")
	if not al.is_empty():
		var rect := room_rect(al)
		var c := Vector2(rect.get_center().x, 0)
		draw_circle(c, 70, Color(0.4, 0.9, 1.0, 0.12))
		draw_arc(c, 70, PI, TAU, 32, Color(0.6, 0.95, 1.0, 0.6), 4.0)
		var blink := 0.5 + 0.5 * sin(t * 3.0)
		draw_circle(c + Vector2(0, -74), 6, Color(1.0, 0.3, 0.3, blink))

func _draw_bubbles() -> void:
	var al := Game.find_room_of_type("airlock")
	var origin := Vector2(400, -60)
	var has_dome := Art.tex("res://art/backgrounds/dome.png") != null
	if not al.is_empty():
		origin = Vector2(room_rect(al).get_center().x, -250.0 if has_dome else -70.0)
	for i in 14:
		var ph := fmod(t * 0.35 + i * 0.137, 1.0)
		var x := origin.x + sin(t * 1.3 + i * 2.1) * 14 + (i % 5 - 2) * 18 * ph
		var y := origin.y - ph * 520
		var rad := 3.0 + (i % 4) * 1.5 + ph * 3.0
		draw_arc(Vector2(x, y), rad, 0, TAU, 12, Color(0.8, 0.95, 1.0, 0.55 * (1.0 - ph)), 1.5)
		draw_circle(Vector2(x - rad * 0.3, y - rad * 0.3), rad * 0.25, Color(1, 1, 1, 0.5 * (1.0 - ph)))
	if has_dome:
		return
	# прожекторы у купола
	for dx in [-120.0, 120.0]:
		var lp := Vector2(origin.x + dx, -10)
		draw_circle(lp, 26, Color(1.0, 0.9, 0.6, 0.08))
		draw_circle(lp, 5, Color(1.0, 0.95, 0.75))

func _draw_doors() -> void:
	for r in Game.rooms:
		var rect := room_rect(r)
		var right := Game.room_at(r.col + Defs.room_width(r.type), r.row)
		if right.is_empty():
			continue
		var x := rect.end.x
		var door := Rect2(x - 7, rect.end.y - WALL - 58, 14, 58)
		draw_rect(door, Color(0.12, 0.14, 0.18))
		draw_rect(door, Color(0.5, 0.56, 0.66), false, 2.0)
		draw_circle(Vector2(x, door.position.y - 8), 3, Color(0.3, 1.0, 0.5, 0.6 + 0.4 * sin(t * 2.0 + r.id)))

func _draw_build_slots(depth_rows: int) -> void:
	var w := Defs.room_width(build_type)
	var pulse := 0.5 + 0.5 * sin(t * 4.0)
	for row in mini(depth_rows, Defs.MAX_DEPTH):
		for col in Defs.GRID_COLS:
			if Game.can_build_at(build_type, col, row):
				var rect := Rect2(col * CELL_W, row * CELL_H, w * CELL_W, CELL_H).grow(-6)
				draw_rect(rect, Color(0.3, 1.0, 0.6, 0.12 + 0.1 * pulse))
				draw_rect(rect, Color(0.3, 1.0, 0.6, 0.7), false, 3.0)
				_text(rect.get_center() + Vector2(0, 10), "+", 44, Color(0.6, 1.0, 0.8, 0.9), true)

func _draw_room(r: Dictionary) -> void:
	var def: Dictionary = Defs.ROOMS[r.type]
	var rect := room_rect(r)
	var col: Color = def.color
	var powered: bool = Game.resources.energy > 0.0 or r.type == "reactor"
	var light := 1.0 if powered else 0.35 + 0.1 * sin(t * 8.0)
	# корпус
	draw_rect(rect, Color(0.18, 0.2, 0.25))
	var inner := rect.grow(-WALL)
	var dark := Color(0.05, 0.08, 0.12)
	draw_rect(inner, dark.lerp(col.darkened(0.55), 0.55 * light))
	var art := Art.room(r.type)
	if art:
		draw_texture_rect(art, inner, false, Color(light, light, light))
		if r.type == "reactor" and powered:
			# пульсация ядра поверх картинки
			var core := inner.get_center() + Vector2(0, 4)
			var pulse := 0.5 + 0.5 * sin(t * 3.0)
			draw_circle(core, inner.size.y * 0.32, Color(1.0, 0.75, 0.3, 0.10 + 0.08 * pulse))
			draw_circle(core, inner.size.y * 0.16, Color(1.0, 0.9, 0.6, 0.08 + 0.08 * pulse))
		if def.has("produces"):
			var bar0 := Rect2(inner.position.x + 8, inner.end.y - 14, inner.size.x - 16, 7)
			draw_rect(bar0, Color(0, 0, 0, 0.55))
			draw_rect(Rect2(bar0.position, Vector2(bar0.size.x * r.progress, bar0.size.y)), Defs.RESOURCES[def.produces].color)
		if r.type != "elevator":
			var label_w := font.get_string_size(tr(def.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			draw_rect(Rect2(inner.position + Vector2(4, 4), Vector2(label_w + 12, 20)), Color(0, 0, 0, 0.45))
			_text(Vector2(inner.position.x + 10, inner.position.y + 19), tr(def.name), 15, Color(1, 1, 1, 0.9))
			for i in r.level:
				_star(Vector2(inner.end.x - 12 - i * 16, inner.position.y + 14), 6.0)
	elif r.type == "elevator":
		_draw_elevator(inner)
	else:
		# задняя стена: панели и окно
		for i in int(inner.size.x / 50):
			draw_line(Vector2(inner.position.x + 50 * (i + 1), inner.position.y),
				Vector2(inner.position.x + 50 * (i + 1), inner.end.y), Color(0, 0, 0, 0.15), 2.0)
		# трубы под потолком
		draw_line(Vector2(inner.position.x, inner.position.y + 10), Vector2(inner.end.x, inner.position.y + 10), Color(0.35, 0.38, 0.45), 4.0)
		draw_line(Vector2(inner.position.x, inner.position.y + 16), Vector2(inner.end.x, inner.position.y + 16), Color(0.25, 0.28, 0.33), 3.0)
		# лампа на потолке и световой конус
		var lamp := Vector2(inner.get_center().x, inner.position.y + 20)
		var cone := PackedVector2Array([lamp + Vector2(-12, 0), lamp + Vector2(12, 0),
			Vector2(inner.end.x - 10, inner.end.y), Vector2(inner.position.x + 10, inner.end.y)])
		draw_colored_polygon(cone, Color(col.lightened(0.5), 0.10 * light))
		draw_rect(Rect2(lamp - Vector2(16, 0), Vector2(32, 5)), Color(col.lightened(0.6), light))
		draw_circle(lamp + Vector2(0, 3), 18, Color(col.lightened(0.5), 0.12 * light))
		_draw_room_props(r, inner, col, light)
		# пол
		draw_rect(Rect2(inner.position.x, inner.end.y - 4, inner.size.x, 4), Color(0.3, 0.33, 0.4))
		# название и уровень
		_text(Vector2(inner.position.x + 8, inner.position.y + 40), tr(def.name), 16, Color(1, 1, 1, 0.8))
		for i in r.level:
			_star(Vector2(inner.end.x - 12 - i * 16, inner.position.y + 34), 6.0)
		# прогресс производства
		if def.has("produces"):
			var bar := Rect2(inner.position.x + 8, inner.end.y - 16, inner.size.x - 16, 7)
			draw_rect(bar, Color(0, 0, 0, 0.5))
			var rc: Color = Defs.RESOURCES[def.produces].color
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * r.progress, bar.size.y)), rc)
	# рамка
	draw_rect(rect, Color(0.45, 0.5, 0.6), false, 2.0)
	if r.id == selected_room:
		draw_rect(rect.grow(2), Color(0.5, 1.0, 1.0, 0.6 + 0.4 * sin(t * 5.0)), false, 4.0)
	# авария
	if r.incident > 0.0:
		_draw_hazard(r, inner)
	if r.type == "dock":
		_draw_dock_overlay(r, rect)
	# готово — пузырь с ресурсом
	if r.ready:
		var rc2: Color = Defs.RESOURCES[def.produces].color
		var bp := Vector2(rect.get_center().x, rect.position.y + 30 + sin(t * 3.0 + r.id) * 5)
		draw_circle(bp, 26, Color(rc2, 0.25))
		draw_circle(bp, 20, Color(0.05, 0.1, 0.15, 0.9))
		draw_arc(bp, 20, 0, TAU, 32, rc2, 3.0)
		Icons.draw(self, def.produces, bp, 11.0, rc2)

## Док: батискаф стоит в доке, либо уплыл (прогресс экспедиции), либо вернулся с добычей.
func _draw_dock_overlay(r: Dictionary, rect: Rect2) -> void:
	var inner := rect.grow(-WALL)
	var e := Game.expedition_at(r.id)
	var sub := Art.tex("res://art/creatures/bathyscaphe.png")
	var away := not e.is_empty() and not Game.expedition_done(e)
	if Art.room("dock") == null:
		# вода в доке
		var water := Rect2(inner.position.x + 6, inner.end.y - 40, inner.size.x - 12, 36)
		draw_rect(water, Color(0.1, 0.45, 0.65, 0.8))
		for i in 4:
			var wx := water.position.x + fmod(t * 20.0 + i * 50.0, water.size.x)
			draw_line(Vector2(wx, water.position.y + 4), Vector2(wx + 14, water.position.y + 4), Color(0.6, 0.9, 1.0, 0.5), 2.0)
	if sub and not away:
		var sw := inner.size.x * 0.62
		var sh := sw * sub.get_height() / sub.get_width()
		var bob := sin(t * 1.5 + r.id) * 3.0
		draw_texture_rect(sub, Rect2(inner.get_center().x - sw / 2.0, inner.end.y - sh - 6 + bob, sw, sh), false)
	if away:
		var p := Game.expedition_progress(e)
		var bar := Rect2(inner.position.x + 8, inner.end.y - 16, inner.size.x - 16, 8)
		draw_rect(bar, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * p, bar.size.y)), Color(1.0, 0.8, 0.3))
		var left := float(e.end) - Game.now()
		_text(inner.get_center() + Vector2(0, 8), tr("%s: %s") % [tr(Defs.ZONES[e.zone].name), _short_time(left)], 15, Color(1, 0.95, 0.8), true)
	elif not e.is_empty():
		var bp := Vector2(rect.get_center().x, rect.position.y + 30 + sin(t * 3.0 + r.id) * 5)
		draw_circle(bp, 28, Color(1.0, 0.8, 0.3, 0.3))
		draw_circle(bp, 21, Color(0.05, 0.1, 0.15, 0.9))
		draw_arc(bp, 21, 0, TAU, 32, Color(1.0, 0.8, 0.3), 3.0)
		Icons.draw(self, "pearls", bp, 11.0, Color(1.0, 0.85, 0.95))

func _draw_hazard(r: Dictionary, inner: Rect2) -> void:
	var hp: float = r.incident / 100.0
	match r.hazard:
		"fire":
			draw_rect(inner, Color(1.0, 0.35, 0.05, 0.18 + 0.08 * sin(t * 12.0)))
			var n := int(inner.size.x / 18)
			for i in n:
				var x := inner.position.x + (i + 0.5) * inner.size.x / n
				var h := (30.0 + 40.0 * hp) * (0.7 + 0.3 * sin(t * 9.0 + i * 1.7))
				var base := inner.end.y - 4
				var wob := sin(t * 7.0 + i) * 5.0
				draw_colored_polygon(PackedVector2Array([Vector2(x - 11, base), Vector2(x + wob, base - h), Vector2(x + 11, base)]), Color(1.0, 0.45, 0.05, 0.9))
				draw_colored_polygon(PackedVector2Array([Vector2(x - 6, base), Vector2(x + wob * 0.6, base - h * 0.6), Vector2(x + 6, base)]), Color(1.0, 0.9, 0.3, 0.95))
			for i in 5:
				var ph := fmod(t * 0.5 + i * 0.2, 1.0)
				draw_circle(Vector2(inner.position.x + inner.size.x * (0.2 + 0.15 * i), inner.end.y - 40 - ph * (inner.size.y - 40)), 8 + ph * 14, Color(0.15, 0.15, 0.15, 0.45 * (1.0 - ph)))
		"flood":
			var level := inner.size.y * (0.15 + 0.6 * hp)
			var pts := PackedVector2Array()
			var steps := 16
			for i in steps + 1:
				var x := inner.position.x + inner.size.x * i / steps
				pts.append(Vector2(x, inner.end.y - level + sin(t * 3.0 + i * 0.8) * 4.0))
			pts.append(inner.end)
			pts.append(Vector2(inner.position.x, inner.end.y))
			draw_colored_polygon(pts, Color(0.1, 0.45, 0.75, 0.6))
			draw_polyline(pts.slice(0, steps + 1), Color(0.7, 0.95, 1.0, 0.8), 2.0)
			for i in 6:
				var ph := fmod(t * 0.7 + i * 0.17, 1.0)
				draw_arc(Vector2(inner.position.x + inner.size.x * (0.1 + 0.15 * i), inner.end.y - ph * level), 3.0, 0, TAU, 8, Color(0.85, 1.0, 1.0, 0.7), 1.2)
			# струя из пробоины
			var jet := Vector2(inner.position.x + inner.size.x * 0.7, inner.position.y + 10)
			draw_line(jet, jet + Vector2(-20, inner.size.y - level - 10), Color(0.6, 0.9, 1.0, 0.7), 5.0)
		"creature":
			draw_rect(inner, Color(0.6, 0.0, 0.2, 0.15 + 0.1 * sin(t * 6.0)))
			var fishy := Art.tex("res://art/creatures/anglerfish.png")
			if fishy:
				var fw := inner.size.x * 0.5
				var fh := fw * fishy.get_height() / fishy.get_width()
				var lunge := sin(t * 2.5) * inner.size.x * 0.2
				var fx := inner.get_center().x + lunge
				draw_set_transform(Vector2(fx, inner.get_center().y + sin(t * 5.0) * 4.0), sin(t * 5.0) * 0.1, Vector2(signf(cos(t * 2.5)) * -1.0, 1))
				draw_texture_rect(fishy, Rect2(-fw / 2.0, -fh / 2.0, fw, fh), false)
				draw_set_transform(Vector2.ZERO)
	# полоса угрозы и подпись
	var bar := Rect2(inner.position.x + 8, inner.position.y + 26, inner.size.x - 16, 10)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp, bar.size.y)), Color(1.0, 0.3, 0.2))
	var label: String = Game.HAZARDS[r.hazard].label
	_text(Vector2(inner.get_center().x, bar.end.y + 26), tr(label), 22, Color(1.0, 0.9, 0.8, 0.7 + 0.3 * sin(t * 8.0)), true)

static func _short_time(sec: float) -> String:
	var s := maxi(0, int(sec))
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]

func _star(c: Vector2, rad: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5
		var rr := rad if i % 2 == 0 else rad * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, Color(1.0, 0.85, 0.3))

func _draw_elevator(inner: Rect2) -> void:
	draw_rect(inner, Color(0.07, 0.09, 0.12))
	for x in [inner.position.x + 12, inner.end.x - 12]:
		draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(0.4, 0.45, 0.5), 3.0)
	for i in 6:
		var y := inner.position.y + fmod(i * 22.0 + t * 10.0, inner.size.y)
		draw_line(Vector2(inner.position.x + 12, y), Vector2(inner.end.x - 12, y), Color(0.3, 0.35, 0.4, 0.5), 2.0)

func _draw_room_props(r: Dictionary, inner: Rect2, col: Color, light: float) -> void:
	var base := Vector2(inner.get_center().x, inner.end.y - 4)
	match r.type:
		"reactor":
			var glow := 0.6 + 0.4 * sin(t * 4.0)
			draw_rect(Rect2(base + Vector2(-22, -70), Vector2(44, 70)), Color(0.25, 0.25, 0.3))
			draw_rect(Rect2(base + Vector2(-14, -62), Vector2(28, 54)), Color(1.0, 0.75, 0.2, glow * light))
			draw_circle(base + Vector2(0, -35), 30, Color(1.0, 0.7, 0.2, 0.12 * glow * light))
		"oxygen":
			for i in 3:
				var x := base.x - 40 + i * 40
				draw_rect(Rect2(x - 12, base.y - 60, 24, 60), Color(0.2, 0.5, 0.6, 0.8))
				var by := base.y - fmod(t * 30.0 + i * 20.0, 55.0)
				draw_arc(Vector2(x, by), 4, 0, TAU, 12, Color(0.8, 1.0, 1.0, 0.8 * light), 2.0)
		"farm":
			for i in 5:
				var x := inner.position.x + 20 + i * (inner.size.x - 40) / 4.0
				var sway := sin(t * 2.0 + i) * 4
				draw_rect(Rect2(x - 14, base.y - 14, 28, 14), Color(0.3, 0.2, 0.15))
				draw_line(Vector2(x, base.y - 14), Vector2(x + sway, base.y - 48), Color(0.3, 0.9, 0.4, light), 4.0)
				draw_line(Vector2(x, base.y - 24), Vector2(x - 9 + sway, base.y - 40), Color(0.3, 0.9, 0.4, light), 3.0)
		"living":
			for i in 2:
				var x := inner.position.x + 20 + i * (inner.size.x - 90)
				draw_rect(Rect2(x, base.y - 22, 50, 14), Color(0.55, 0.35, 0.65))
				draw_rect(Rect2(x, base.y - 30, 14, 10), Color(0.9, 0.9, 1.0))
			draw_rect(Rect2(base.x - 16, inner.position.y + 34, 32, 24), Color(0.1, 0.3, 0.5))
			draw_rect(Rect2(base.x - 16, inner.position.y + 34, 32, 24), Color(0.6, 0.8, 1.0), false, 2.0)
		"storage":
			for i in 4:
				var x := inner.position.x + 18 + i * 40
				var h := 26.0 + (i % 2) * 20.0
				draw_rect(Rect2(x, base.y - h, 30, h), Color(0.55, 0.45, 0.3))
				draw_rect(Rect2(x, base.y - h, 30, h), Color(0.3, 0.25, 0.15), false, 2.0)
		"pearl":
			for i in 3:
				var p := Vector2(base.x - 50 + i * 50, base.y - 16)
				draw_circle(p, 16, Color(0.4, 0.3, 0.45))
				draw_circle(p + Vector2(0, -4), 7, Color(1.0, 0.9, 1.0, (0.6 + 0.4 * sin(t * 2 + i)) * light))
		"medbay":
			draw_rect(Rect2(base.x - 40, base.y - 20, 80, 12), Color(0.9, 0.9, 0.95))
			var cross := base + Vector2(0, -60)
			draw_rect(Rect2(cross - Vector2(4, 12), Vector2(8, 24)), Color(1.0, 0.3, 0.35, light))
			draw_rect(Rect2(cross - Vector2(12, 4), Vector2(24, 8)), Color(1.0, 0.3, 0.35, light))
		"airlock":
			var door := Rect2(base.x - 24, base.y - 70, 48, 70)
			draw_rect(door, Color(0.3, 0.35, 0.42))
			draw_arc(door.get_center(), 14, 0, TAU, 24, Color(0.7, 0.8, 0.9), 3.0)
			var arrival := Game.seconds_until_arrival()
			if arrival >= 0.0:
				_text(Vector2(base.x, inner.position.y + 66), tr("new in %ds") % ceili(arrival), 15, Color(0.7, 0.95, 1.0, 0.8), true)

func _draw_colonist(feet: Vector2, c: Dictionary, lifted: bool) -> void:
	var sprite := Art.diver(c.suit)
	if sprite:
		_draw_colonist_sprite(feet, c, lifted, sprite)
		return
	var w: Dictionary = walkers.get(c.id, {})
	var walking: bool = w.get("wait", 1.0) <= 0.0 and not lifted
	var bob := sin(t * 10.0 + c.id) * 2.0 if walking else 0.0
	var suit: Color = SUIT_COLORS[c.suit % SUIT_COLORS.size()]
	if c.health < 50.0:
		suit = suit.lerp(Color(0.5, 0.5, 0.5), 0.5)
	var s := 1.15 if lifted else 1.0
	var p := feet + Vector2(0, bob)
	if lifted:
		draw_circle(feet + Vector2(0, 2), 14, Color(0, 0, 0, 0.3))
	# ноги
	var step := sin(t * 10.0 + c.id) * 5.0 if walking else 0.0
	draw_line(p + Vector2(-5, -16) * s, p + Vector2(-5 + step, 0) * s, suit.darkened(0.3), 5.0)
	draw_line(p + Vector2(5, -16) * s, p + Vector2(5 - step, 0) * s, suit.darkened(0.3), 5.0)
	# тело и баллон
	var facing: float = w.get("facing", 1.0)
	draw_rect(Rect2(p + Vector2(-7 - facing * 8, -34) * s, Vector2(7, 16) * s), Color(0.7, 0.7, 0.75))
	draw_rect(Rect2(p + Vector2(-9, -36) * s, Vector2(18, 22) * s), suit)
	# шлем
	var head := p + Vector2(0, -46) * s
	draw_circle(head, 11 * s, Color(0.75, 0.9, 1.0, 0.35))
	draw_circle(head + Vector2(facing * 2, 1) * s, 7 * s, Color(0.95, 0.8, 0.65))
	draw_arc(head, 11 * s, 0, TAU, 20, Color(0.85, 0.95, 1.0, 0.9), 2.0)
	draw_circle(head + Vector2(-4, -5) * s, 2.5 * s, Color(1, 1, 1, 0.8))
	# полоска здоровья, если ранен
	if c.health < 99.0:
		var hb := Rect2(p + Vector2(-12, -64) * s, Vector2(24, 4) * s)
		draw_rect(hb, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(hb.position, Vector2(hb.size.x * c.health / 100.0, hb.size.y)), Color(1.0, 0.3, 0.3).lerp(Color(0.4, 1.0, 0.4), c.health / 100.0))

func _draw_colonist_sprite(feet: Vector2, c: Dictionary, lifted: bool, sprite: Texture2D) -> void:
	var w: Dictionary = walkers.get(c.id, {})
	var walking: bool = w.get("wait", 1.0) <= 0.0 and not lifted
	var h := 72.0 * (1.15 if lifted else 1.0)
	var size := Vector2(h * sprite.get_width() / sprite.get_height(), h)
	var bob := absf(sin(t * 10.0 + c.id)) * -3.0 if walking else sin(t * 2.0 + c.id) * 0.8
	var facing: float = w.get("facing", 1.0)
	if lifted:
		draw_circle(feet + Vector2(0, 2), 16, Color(0, 0, 0, 0.3))
	var tint := Color.WHITE if c.health >= 50.0 else Color(0.75, 0.75, 0.75)
	if walking:
		var frame := Art.walk_frame(c.suit, t * 11.0 + c.id)
		if frame:
			sprite = frame
			size = Vector2(h * 0.95 * sprite.get_width() / sprite.get_height(), h * 0.95)
			bob = 0.0
	draw_set_transform(feet + Vector2(0, bob), 0.0, Vector2(facing, 1.0))
	draw_texture_rect(sprite, Rect2(Vector2(-size.x / 2.0, -size.y), size), false, tint)
	draw_set_transform(Vector2.ZERO)
	if w.get("panic", false):
		var ex := feet + Vector2(0, -h - 22 + sin(t * 10.0 + c.id) * 3.0)
		draw_circle(ex, 11, Color(1.0, 0.85, 0.2))
		_text(ex + Vector2(0, 7), "!", 20, Color(0.2, 0.05, 0.0), true)
	if c.health < 99.0:
		var hb := Rect2(feet + Vector2(-12, -h - 8), Vector2(24, 4))
		draw_rect(hb, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(hb.position, Vector2(hb.size.x * c.health / 100.0, hb.size.y)), Color(1.0, 0.3, 0.3).lerp(Color(0.4, 1.0, 0.4), c.health / 100.0))

func _text(pos: Vector2, text: String, size: int, col: Color, centered := false) -> void:
	var p := pos
	if centered:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		p.x -= w / 2.0
	draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, col.a * 0.7))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

# ---------------------------------------------------------------- ввод

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
			if touches.size() == 1:
				_on_press(event.position)
			elif touches.size() == 2:
				drag_colonist = -1
				moved = true
				pinch_dist = touches.values()[0].distance_to(touches.values()[1])
		else:
			if touches.size() == 1 and touches.has(event.index):
				_on_release(event.position)
			touches.erase(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		if touches.size() >= 2:
			var d: float = touches.values()[0].distance_to(touches.values()[1])
			if pinch_dist > 0.0:
				_zoom_by(d / pinch_dist)
			pinch_dist = d
		else:
			if event.position.distance_to(press_pos) > 12.0:
				moved = true
			if drag_colonist != -1:
				drag_pos = screen_to_world(event.position)
			elif moved:
				camera.position -= event.relative / camera.zoom
				_clamp_camera()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(1.1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(1.0 / 1.1)

func _on_press(p: Vector2) -> void:
	press_pos = p
	moved = false
	drag_colonist = -1
	if build_type != "":
		return
	var world := screen_to_world(p)
	for c in Game.colonists:
		if c.room == Game.ON_EXPEDITION:
			continue
		var cp := colonist_world_pos(c)
		if world.distance_to(cp + Vector2(0, -28)) < 30.0:
			drag_colonist = c.id
			drag_pos = world
			return

func _on_release(p: Vector2) -> void:
	var world := screen_to_world(p)
	var cell := cell_at(world)
	if drag_colonist != -1:
		var c := Game.get_colonist(drag_colonist)
		drag_colonist = -1
		if moved:
			var room := Game.room_at(cell.x, cell.y)
			if not room.is_empty():
				if room.incident > 0.0 and c.room != room.id:
					Game.send_help(c, room)
				else:
					Game.assign(c, room)
			return
		colonist_selected.emit(c.id)
		return
	if moved:
		return
	if build_type != "":
		var w := Defs.room_width(build_type)
		# пробуем поставить так, чтобы касание попало внутрь комнаты
		for dc in range(0, -w, -1):
			if Game.can_build_at(build_type, cell.x + dc, cell.y):
				if Game.build(build_type, cell.x + dc, cell.y):
					build_type = ""
					build_finished.emit()
				return
		return
	var room := Game.room_at(cell.x, cell.y)
	if room.is_empty():
		selected_room = -1
		room_selected.emit(-1)
		return
	if room.ready:
		Game.collect(room)
		return
	if room.type == "dock":
		var e := Game.expedition_at(room.id)
		if not e.is_empty() and Game.expedition_done(e):
			Game.claim_expedition(e)
			return
	selected_room = room.id
	room_selected.emit(room.id)

func _zoom_by(f: float) -> void:
	var z := clampf(camera.zoom.x * f, 0.45, 2.2)
	camera.zoom = Vector2(z, z)
	_clamp_camera()

func _clamp_camera() -> void:
	var bottom := (maxi(Game.max_row() + 3, 5)) * CELL_H
	camera.position.x = clampf(camera.position.x, -200, Defs.GRID_COLS * CELL_W + 200)
	camera.position.y = clampf(camera.position.y, -500, bottom)

func focus_room(r: Dictionary) -> void:
	var target := room_rect(r).get_center() + Vector2(0, 120)
	var tw := create_tween()
	tw.tween_property(camera, "position", target, 0.35).set_trans(Tween.TRANS_SINE)

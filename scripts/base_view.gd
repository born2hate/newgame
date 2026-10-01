extends Node2D
## Вид колонии в разрезе: рисует скалу, отсеки, колонистов; обрабатывает касания.

signal room_selected(room_id: int)
signal build_finished
signal colonist_selected(colonist_id: int)
signal trader_tapped
signal locked_zone_tapped(research_id: String)
signal fallen_tapped(index: int)
signal outside_tapped

const CELL_W := 100.0
const CELL_H := 130.0
const WORLD_PAD := 4000.0
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
const FISH_W := {"fish_school": 90.0, "fish_grouper": 78.0, "fish_parrot": 66.0, "fish_lion": 62.0,
	"fish_sardine": 46.0, "fish_clown2": 48.0, "fish_puffer": 46.0, "fish_striped": 50.0}
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var kinds := ["fish_yellow_tang", "fish_blue_tang", "fish_clown2", "fish_angel2", "fish_school", "fish_sardine",
		"fish_idol", "fish_lion", "fish_parrot", "fish_grouper", "fish_snapper", "fish_striped", "fish_puffer", "fish_school"]
	for i in kinds.size():
		fish.append({
			"p": Vector2(r.randf_range(-600, 1400), r.randf_range(-560, -120)),
			"v": r.randf_range(25, 60) * (1 if r.randf() > 0.5 else -1),
			"s": r.randf_range(0.7, 1.2), "ph": r.randf() * TAU, "kind": kinds[i],
		})
	Game.floating_text.connect(_on_floating_text)
	var rock := Polygon2D.new()
	# порода и дно с большим запасом по бокам, чтобы при отдалении и в горизонтальном
	# положении не было видно обрыва картинки
	rock.polygon = PackedVector2Array([Vector2(-WORLD_PAD, 0), Vector2(Defs.GRID_COLS * CELL_W + WORLD_PAD, 0),
		Vector2(Defs.GRID_COLS * CELL_W + WORLD_PAD, 5000), Vector2(-WORLD_PAD, 5000)])
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
	if camera:
		if shake > 0.05:
			camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
			shake = move_toward(shake, 0.0, delta * 30.0)
		elif camera.offset != Vector2.ZERO:
			camera.offset = Vector2.ZERO
	_update_walkers(delta)
	_update_treasure(delta)
	for f in fish:
		# естественнее: скорость «рывками», плавный дрейф по высоте, иногда разворот
		var burst := 0.6 + 0.4 * (0.5 + 0.5 * sin(t * 0.9 + f.ph * 3.0))
		f.p.x += f.v * burst * delta
		f.p.y += sin(t * 0.35 + f.ph) * 6.0 * delta
		f.p.y = clampf(f.p.y, -600.0, -90.0)
		f["turn"] = f.get("turn", randf_range(8.0, 25.0)) - delta
		if f.turn <= 0.0:
			f.turn = randf_range(10.0, 30.0)
			if randf() < 0.4:
				f.v = -f.v
		if f.p.x > 1700: f.p.x = -800
		if f.p.x < -800: f.p.x = 1700
	for fl in floaters:
		fl.life -= delta
		fl.pos.y -= 40 * delta
	floaters = floaters.filter(func(fl): return fl.life > 0)
	queue_redraw()

# ---------------------------------------------------------------- геометрия

func room_rect(r: Dictionary) -> Rect2:
	return Rect2(r.col * CELL_W, r.row * CELL_H, Game.room_w(r) * CELL_W, CELL_H)

func cell_at(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x / CELL_W), floori(world.y / CELL_H))

func screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p

func colonist_world_pos(c: Dictionary) -> Vector2:
	var rid: int = c.help if c.get("help", -1) != -1 else c.room
	var room: Dictionary = Game.get_room(rid) if rid >= 0 else Game.find_room_of_type("airlock")
	if room.is_empty():
		room = Game.find_room_of_type("airlock")
	if room.is_empty():
		return Vector2.ZERO
	var rect := room_rect(room)
	var w: Dictionary = walkers.get(c.id, {})
	var x: float = w.get("x", 0.5)
	# глубина: 0 — у передней стены, 1 — у задней (выше по экрану)
	var z: float = w.get("z", 0.5)
	return Vector2(rect.position.x + 22 + x * (rect.size.x - 44), rect.end.y - WALL - 4 - z * 16.0)

## Масштаб по глубине: дальние меньше, ближние крупнее.
func depth_scale(c: Dictionary) -> float:
	var z: float = walkers.get(c.id, {}).get("z", 0.5)
	return lerpf(1.08, 0.8, z)

func _update_walkers(delta: float) -> void:
	var alive := {}
	for c in Game.colonists:
		alive[c.id] = true
		if not walkers.has(c.id):
			walkers[c.id] = {"x": randf(), "target": randf(), "wait": randf() * 2.0, "facing": 1.0, "room": c.room,
				"z": randf(), "zt": randf()}
		var wz: Dictionary = walkers[c.id]
		# плавно меняют глубину, когда ходят; у рабочих мест — чередуются ближе/дальше
		if wz.has("station"):
			wz.zt = 0.2 if int(wz.station * 10.0) % 2 == 0 else 0.8
		wz.z = move_toward(wz.z, wz.zt, delta * 0.4)
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
			w["working"] = false
			if w.wait > 0.0:
				w.wait -= delta
				continue
			var goal := _hazard_target_x(Game.get_room(here), c.id)
			var dd: float = goal - w.x
			if absf(dd) < 0.03:
				w["fighting"] = true
				w.wait = randf_range(1.2, 2.4)
				w.facing = signf(_hazard_focus_x(Game.get_room(here)) - w.x)
				if w.facing == 0.0:
					w.facing = 1.0
			else:
				w["fighting"] = false
				w.facing = signf(dd)
				w.x += signf(dd) * minf(absf(dd), delta * 0.9)
			continue
		w["fighting"] = false
		# работник: стоит у своего рабочего места и трудится, изредка переходит к другому
		var room: Dictionary = Game.get_room(here) if here >= 0 else {}
		var job: bool = not danger and c.get("help", -1) == -1 and not room.is_empty() and Game.slots(room) > 0 and not c.get("child", false)
		if job and not w.has("station"):
			var mates := Game.workers_in(room)
			var idx := mates.find(c)
			var n := maxi(1, Game.slots(room))
			w["station"] = (maxi(idx, 0) + 0.5) / n
			w.target = w.station
			w.wait = 0.0
		elif not job and w.has("station"):
			w.erase("station")
			w["working"] = false
		if w.wait > 0.0:
			w.wait -= delta
			continue
		var d: float = w.target - w.x
		if absf(d) < 0.01:
			w["zt"] = randf()
			if job:
				# пришёл к месту — работает 8–16 с, потом может сходить к соседнему месту
				w["working"] = not room.ready and Game.room_power(room) > 0.0
				w.facing = 1.0 if fmod(w.station * 7.0, 2.0) < 1.0 else -1.0
				w.wait = randf_range(8.0, 16.0)
				w.target = w.station if randf() < 0.75 else clampf(w.station + randf_range(-0.25, 0.25), 0.05, 0.95)
			else:
				w.wait = randf_range(1.0, 4.0)
				w.target = randf()
		else:
			w["working"] = false
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
	var m := Art.split_marker(text)
	floaters.append({"pos": rect.get_center() - Vector2(0, 30), "text": m[1], "icon": m[0], "color": color, "life": 1.6})

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
	var x := -WORLD_PAD
	while x < Defs.GRID_COLS * CELL_W + WORLD_PAD:
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
	_draw_depth_zones(depth_rows)
	_draw_bounds()
	if build_type != "":
		_draw_build_slots(Defs.MAX_DEPTH)
	for r in Game.rooms:
		_draw_room(r)
	_draw_doors()
	_draw_fallen()
	_draw_raider_bodies()
	# дальние рисуем первыми, ближние — поверх
	var order := Game.colonists.filter(func(c): return c.id != drag_colonist and c.room != Game.ON_EXPEDITION)
	order.sort_custom(func(a, b): return walkers.get(a.id, {}).get("z", 0.5) > walkers.get(b.id, {}).get("z", 0.5))
	for c in order:
		_draw_colonist(colonist_world_pos(c), c, false)
	if drag_colonist != -1:
		var c := Game.get_colonist(drag_colonist)
		if not c.is_empty():
			var hover := Game.room_at(cell_at(drag_pos).x, cell_at(drag_pos).y)
			var pulse := 0.5 + 0.5 * sin(t * 6.0)
			# все отсеки: зелёные — есть место, красные — занято / нельзя работать
			for r in Game.rooms:
				if r.type in ["elevator", "airlock"]:
					continue
				var ok: bool = Game.slots(r) > 0 and (Game.workers_in(r).size() < Game.slots(r) or c.room == r.id)
				if r.incident > 0.0:
					ok = true
				var col := Color(0.35, 1.0, 0.5) if ok else Color(1.0, 0.35, 0.35)
				var rr := room_rect(r).grow(-3)
				var strong: bool = not hover.is_empty() and hover.id == r.id
				draw_rect(rr, Color(col, 0.28 if strong else 0.1))
				draw_rect(rr, Color(col, 0.95 if strong else 0.5 + 0.2 * pulse), false, 6.0 if strong else 3.0)
			# ореол и подпись над схваченным
			var feet := drag_pos + Vector2(0, 30)
			draw_circle(feet + Vector2(0, -40), 52 + 6 * pulse, Color(1.0, 0.9, 0.4, 0.22))
			draw_arc(feet + Vector2(0, -40), 52 + 6 * pulse, 0, TAU, 40, Color(1.0, 0.9, 0.4, 0.9), 4.0)
			_draw_colonist(feet, c, true)
			var best: String = Defs.STATS[Game.best_stat(c)]
			var tag: String = "%s · %s %d" % [c.name.split(" ")[0], tr(best), Game.stat(c, Game.best_stat(c))]
			var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
			var tp := feet + Vector2(-tw / 2.0 - 10, -130)
			draw_rect(Rect2(tp, Vector2(tw + 20, 32)), Color(0.05, 0.1, 0.18, 0.92))
			draw_rect(Rect2(tp, Vector2(tw + 20, 32)), Color(1.0, 0.85, 0.35), false, 2.0)
			_text(tp + Vector2(10, 24), tag, 22, Color(1.0, 0.92, 0.6))
	_draw_treasure()
	_draw_trader()
	_draw_pirate_sub()
	_draw_boss()
	for fl in floaters:
		var a := clampf(fl.life, 0.0, 1.0)
		var ic: Texture2D = Art.marker_icon(fl.get("icon", "")) if fl.get("icon", "") != "" else null
		if ic:
			var tw := font.get_string_size(fl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
			var x0: float = fl.pos.x - (tw + 40) / 2.0
			draw_texture_rect(ic, Rect2(Vector2(x0, fl.pos.y - 30), Vector2(36, 36)), false, Color(1, 1, 1, a))
			_text(Vector2(x0 + 40, fl.pos.y), fl.text, 32, Color(fl.color, a))
		else:
			_text(fl.pos, fl.text, 30, Color(fl.color, a), true)

## Питомец плавает в воде над дном, позади купола — не заслоняя отсеки.
func _draw_pet() -> void:
	if Game.pet == "":
		return
	var tex := Art.pet(Game.pet)
	if tex == null:
		return
	var span := Defs.GRID_COLS * CELL_W
	var px := span * 0.5 + sin(t * 0.25) * span * 0.42
	var py := -330.0 + sin(t * 0.5) * 60.0
	var dir := signf(cos(t * 0.25))
	var fw := 64.0
	var fh := fw * tex.get_height() / tex.get_width()
	draw_set_transform(Vector2(px, py + sin(t * 3.0) * 4.0), sin(t * 3.0) * 0.08, Vector2(dir, 1))
	draw_texture_rect(tex, Rect2(-fw / 2.0, -fh / 2.0, fw, fh), false)
	draw_set_transform(Vector2.ZERO)
	# пузырьки за хвостом
	for i in 3:
		var ph := fmod(t * 0.8 + i * 0.33, 1.0)
		draw_arc(Vector2(px - dir * (fw * 0.5 + ph * 10), py - ph * 40), 2.5 + ph * 2, 0, TAU, 10, Color(0.8, 0.95, 1.0, 0.7 * (1.0 - ph)), 1.2)

func _draw_water_life() -> void:
	_draw_pet()
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
		var spr := Art.tex("res://art/creatures/fish/%s.png" % f.kind)
		if spr:
			var fw: float = FISH_W.get(f.kind, 58.0) * s
			var fh := fw * spr.get_height() / spr.get_width()
			# спрайты смотрят вправо; лёгкое покачивание хвостом
			# хвост: лёгкое сжатие по длине вместо раскачивания всей рыбы
			var wag := sin(t * 6.0 + f.ph)
			draw_set_transform(p, wag * 0.025, Vector2(dir * (1.0 + 0.03 * wag), 1.0 - 0.02 * wag))
			draw_texture_rect(spr, Rect2(-fw / 2.0, -fh / 2.0, fw, fh), false)
			draw_set_transform(Vector2.ZERO)
			continue
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

## Порода за пределами участка колонии затемнена: там строить нельзя.
## В режиме стройки граница видна сильнее.
func _draw_bounds() -> void:
	var gw := Defs.GRID_COLS * CELL_W
	var gh := Defs.MAX_DEPTH * CELL_H
	var a := 0.62 if build_type != "" else 0.4
	var shade := Color(0.0, 0.0, 0.02, a)
	draw_rect(Rect2(-WORLD_PAD, 0, WORLD_PAD, 5000), shade)
	draw_rect(Rect2(gw, 0, WORLD_PAD, 5000), shade)
	draw_rect(Rect2(0, gh, gw, 5000), shade)
	var line := Color(1.0, 0.85, 0.35, 0.55 if build_type != "" else 0.18)
	for x in [0.0, gw]:
		var y := 0.0
		while y < gh:
			draw_line(Vector2(x, y), Vector2(x, minf(gh, y + 24.0)), line, 3.0)
			y += 40.0
	var y2 := 0.0
	while y2 < gw:
		draw_line(Vector2(y2, gh), Vector2(minf(gw, y2 + 24.0), gh), line, 3.0)
		y2 += 40.0

## Границы зон глубины и замок, если зона не исследована.
func _draw_depth_zones(depth_rows: int) -> void:
	for z in Defs.DEPTH_ZONES:
		if z.from == 0 or z.from > depth_rows + 1:
			continue
		var y: float = z.from * CELL_H - 3
		var open := Game.zone_unlocked_row(z.from)
		var col: Color = z.color
		for i in int((Defs.GRID_COLS * CELL_W + 400) / 30.0):
			var x := -200.0 + i * 30.0
			draw_line(Vector2(x, y), Vector2(x + 18, y), Color(col, 0.7), 3.0)
		var label := tr(z.name)
		if not open:
			label = "🔒 " + label + " · " + tr(Game.research_def(z.research).name)
		_text(Vector2(Defs.GRID_COLS * CELL_W * 0.5, y + 34), label, 22, Color(col.lightened(0.3), 0.9), true)
		if not open:
			draw_rect(Rect2(-200, y + 3, Defs.GRID_COLS * CELL_W + 400, CELL_H * 5), Color(0, 0, 0, 0.35))

# пузыри с сокровищами: всплывают со дна, нажми — получишь награду
var treasure: Array = []
var treasure_timer := 25.0

func _update_treasure(delta: float) -> void:
	treasure_timer -= delta
	if treasure_timer <= 0.0:
		treasure_timer = randf_range(35.0, 80.0)
		var rows := maxf(2.0, Game.max_row() + 1.0)
		treasure.append({"p": Vector2(randf_range(40, Defs.GRID_COLS * CELL_W - 40), rows * CELL_H + 60),
			"rich": randf() < 0.12, "ph": randf() * TAU})
	for b in treasure:
		b.p.y -= 38.0 * delta
		b.p.x += sin(t * 1.5 + b.ph) * 20.0 * delta
	treasure = treasure.filter(func(b): return b.p.y > -700)

func _draw_treasure() -> void:
	for b in treasure:
		var col := Defs.RESOURCES.crystals.color if b.rich else Color(1.0, 0.8, 0.95)
		var pulse := 1.0 + 0.08 * sin(t * 5.0 + b.ph)
		var bt := Art.tex("res://art/creatures/treasure_bubble.png")
		if bt:
			var bs := 70.0 * pulse
			draw_circle(b.p, 38 * pulse, Color(col, 0.15))
			draw_texture_rect(bt, Rect2(b.p - Vector2(bs, bs) / 2.0, Vector2(bs, bs)), false)
			if b.rich:
				Icons.draw(self, "crystals", b.p + Vector2(18, 18), 11.0, col)
			continue
		draw_circle(b.p, 34 * pulse, Color(col, 0.18))
		draw_circle(b.p, 26 * pulse, Color(0.85, 0.97, 1.0, 0.22))
		draw_arc(b.p, 26 * pulse, 0, TAU, 32, Color(0.9, 1.0, 1.0, 0.85), 2.5)
		draw_arc(b.p + Vector2(-9, -9), 8, PI, PI * 1.5, 10, Color(1, 1, 1, 0.9), 3.0)
		Icons.draw(self, "crystals" if b.rich else "pearls", b.p, 12.0, col)

func _try_pop_treasure(world: Vector2) -> bool:
	for b in treasure:
		if world.distance_to(b.p) < 44.0:
			var r := Game.pop_bubble(b.rich)
			var m := Art.split_marker(r.text)
			floaters.append({"pos": b.p, "text": m[1], "icon": m[0], "color": r.color, "life": 1.4})
			treasure.erase(b)
			return true
	return false

func _trader_rect() -> Rect2:
	var al := Game.find_room_of_type("airlock")
	var cx := room_rect(al).get_center().x + 230 if not al.is_empty() else 600.0
	return Rect2(cx - 110, -150 + sin(t * 1.2) * 6, 230, 70)

func _draw_trader() -> void:
	if Game.trader.is_empty():
		return
	var r := _trader_rect()
	var ship := Art.tex("res://art/creatures/trader_sub.png")
	if ship:
		# корабль торговца смотрит влево — к шлюзу
		var h := r.size.x * ship.get_height() / ship.get_width()
		draw_texture_rect(ship, Rect2(r.position.x, r.get_center().y - h / 2.0, r.size.x, h), false)
	else:
		var sub := Art.tex("res://art/creatures/bathyscaphe.png")
		if sub:
			draw_set_transform(r.position + Vector2(r.size.x, 0), 0.0, Vector2(-1, 1))
			draw_texture_rect(sub, Rect2(Vector2.ZERO, r.size), false, Color(0.75, 1.0, 0.8))
			draw_set_transform(Vector2.ZERO)
	var bp := r.position + Vector2(r.size.x * 0.5, -22 + sin(t * 3.0) * 4)
	draw_circle(bp, 22, Color(0.1, 0.25, 0.15, 0.9))
	draw_arc(bp, 22, 0, TAU, 24, Color(0.5, 1.0, 0.6), 3.0)
	_text(bp + Vector2(0, 8), "$", 24, Color(0.6, 1.0, 0.7), true)
	_text(r.position + Vector2(r.size.x * 0.5, r.size.y + 18), _short_time(float(Game.trader.until) - Game.now()), 16, Color(0.8, 1.0, 0.85), true)

## Пираты в отсеке (пока нет их картинок — водолазы в тёмных костюмах с красной банданой).
func _draw_raiders(r: Dictionary, inner: Rect2) -> void:
	var alive := Game.raid_alive()
	if Game.raid.get("door", 0.0) > 0.0:
		# ещё ломают дверь: стоят у правого края шлюза, полоска двери
		var db := Rect2(inner.position.x + 8, inner.end.y - 22, inner.size.x - 16, 8)
		var al := Game.find_room_of_type("airlock")
		var full: float = 15.0 + 20.0 * al.get("level", 1)
		draw_rect(db, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(db.position, Vector2(db.size.x * Game.raid.door / full, db.size.y)), Color(0.7, 0.75, 0.85))
		_text(Vector2(inner.get_center().x, db.position.y - 6), tr("DOOR"), 16, Color(0.85, 0.9, 1.0), true)
	var n := alive.size()
	for i in n:
		var rd: Dictionary = alive[i]
		var fx := inner.position.x + inner.size.x * (0.55 + 0.35 * (i + 0.5) / maxf(1.0, n)) + sin(t * 2.0 + i) * 4.0
		var feet := Vector2(fx, inner.end.y - 6)
		var h := 64.0
		var spr := Art.tex("res://art/creatures/raider_%d.png" % int(rd.kind))
		var tint := Color.WHITE
		if spr == null:
			spr = Art.diver(3 + int(rd.kind))
			tint = Color(0.5, 0.32, 0.32)
		if spr:
			var sz := Vector2(h * spr.get_width() / spr.get_height(), h)
			var lean := 0.1 * maxf(0.0, sin(t * 9.0 + i * 1.7))
			draw_set_transform(feet, -lean, Vector2(-1, 1))
			draw_texture_rect(spr, Rect2(Vector2(-sz.x / 2.0, -sz.y), sz), false, tint)
			draw_set_transform(Vector2.ZERO)
			if tint != Color.WHITE:
				# бандана
				draw_rect(Rect2(feet + Vector2(-sz.x * 0.28, -h * 0.86), Vector2(sz.x * 0.56, 5)), Color(0.9, 0.12, 0.1))
		var hb := Rect2(feet + Vector2(-16, -h - 12), Vector2(32, 5))
		draw_rect(hb, Color(0, 0, 0, 0.7))
		draw_rect(Rect2(hb.position, Vector2(hb.size.x * rd.hp / rd.max, hb.size.y)), Color(1.0, 0.25, 0.2))

## Левиафан у купола: огромный удильщик, полоска здоровья и таймер.
func boss_rect() -> Rect2:
	var span := Defs.GRID_COLS * CELL_W
	var cx := span * 0.5 + sin(t * 0.6) * span * 0.25
	return Rect2(cx - 260, -560 + sin(t * 1.3) * 25, 520, 340)

var boss_hit := 0.0

func _draw_boss() -> void:
	if Game.boss.is_empty():
		return
	boss_hit = maxf(0.0, boss_hit - 0.05)
	var r := boss_rect()
	var kind: int = int(Game.boss.get("kind", 0))
	var tex := Art.tex("res://art/creatures/boss_%s.png" % Game.BOSSES[kind].id)
	var fallback := tex == null
	if fallback:
		tex = Art.tex("res://art/creatures/anglerfish.png")
	var dir := -signf(cos(t * 0.6))
	if tex:
		var h := r.size.x * tex.get_height() / tex.get_width()
		var tint := Color(1.0, 1.0 - boss_hit * 0.6, 1.0 - boss_hit * 0.6)
		if fallback and kind > 0:
			# пока нет своих картинок — разный оттенок
			tint *= [Color.WHITE, Color(1.0, 0.6, 0.8), Color(0.6, 1.0, 0.7), Color(1.0, 0.7, 0.5)][kind]
		draw_set_transform(r.get_center(), sin(t * 2.0) * 0.05, Vector2(dir, 1) * (1.0 + boss_hit * 0.06))
		draw_texture_rect(tex, Rect2(-r.size.x / 2.0, -h / 2.0, r.size.x, h), false, tint)
		draw_set_transform(Vector2.ZERO)
	var hb := Rect2(r.position.x + 60, r.position.y - 30, r.size.x - 120, 18)
	# полоска здоровья всегда на экране, даже когда босс уплыл за край
	var vis := get_canvas_transform().affine_inverse() * get_viewport_rect()
	var pad := vis.size.x * 0.04
	hb.position.x = clampf(hb.position.x, vis.position.x + pad, maxf(vis.position.x + pad, vis.end.x - hb.size.x - pad))
	draw_rect(hb, Color(0, 0, 0, 0.7))
	draw_rect(Rect2(hb.position, Vector2(hb.size.x * Game.boss.hp / Game.boss.max, hb.size.y)), Color(1.0, 0.2, 0.25))
	draw_rect(hb, Color(1.0, 0.85, 0.4), false, 2.0)
	_text(Vector2(hb.get_center().x, hb.position.y - 8), "%s · %s" % [tr(Game.BOSSES[kind].name).to_upper(), _short_time(float(Game.boss.until) - Game.now())], 22, Color(1.0, 0.9, 0.7), true)

## Подлодка пиратов у шлюза, пока идёт налёт.
func _draw_pirate_sub() -> void:
	if Game.raid.is_empty():
		return
	var al := Game.find_room_of_type("airlock")
	if al.is_empty():
		return
	var cx := room_rect(al).get_center().x - 250
	var rect := Rect2(cx - 115, -150 + sin(t * 1.4) * 5, 230, 70)
	var ship := Art.tex("res://art/creatures/pirate_sub.png")
	if ship:
		var hh := rect.size.x * ship.get_height() / ship.get_width()
		draw_texture_rect(ship, Rect2(rect.position.x, rect.get_center().y - hh / 2.0, rect.size.x, hh), false)
	else:
		var sub := Art.tex("res://art/creatures/bathyscaphe.png")
		if sub:
			draw_texture_rect(sub, rect, false, Color(0.45, 0.3, 0.3))
	var bp := rect.position + Vector2(rect.size.x * 0.5, -20 + sin(t * 3.0) * 3)
	draw_circle(bp, 18, Color(0.3, 0.02, 0.02, 0.9))
	draw_arc(bp, 18, 0, TAU, 24, Color(1.0, 0.3, 0.25), 3.0)
	_text(bp + Vector2(0, 8), "!", 24, Color(1.0, 0.85, 0.8), true)

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
		var right := Game.room_at(r.col + Game.room_w(r), r.row)
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
	var art := Art.room_of(r)
	if art:
		# эффект диорамы: задняя стена смещается от камеры, между ней и рамкой — стены в перспективе
		var back := _diorama_back(inner)
		_draw_diorama_walls(inner, back, col, light)
		var n: int = r.get("size", 1)
		var seg_w := back.size.x / n
		for i in n:
			var seg := Rect2(back.position.x + seg_w * i, back.position.y, seg_w, back.size.y)
			if i % 2 == 1:
				draw_set_transform(Vector2(seg.end.x, seg.position.y), 0.0, Vector2(-1, 1))
				draw_texture_rect(art, Rect2(Vector2.ZERO, seg.size), false, Color(light, light, light))
				draw_set_transform(Vector2.ZERO)
			else:
				draw_texture_rect(art, seg, false, Color(light, light, light))
		if r.type == "airlock" and r.level >= 2:
			# улучшенная дверь шлюза поверх нарисованной
			var door := Art.tex("res://art/ui/airlock_door_%d.png" % mini(3, r.level))
			if door:
				var dh := back.size.y * 0.78
				var dw := dh * door.get_width() / door.get_height()
				draw_texture_rect(door, Rect2(back.get_center() - Vector2(dw / 2.0, dh / 2.0 - back.size.y * 0.04), Vector2(dw, dh)), false)
		if powered and r.incident <= 0.0 and not r.get("damaged", false):
			_draw_room_ambient(r, back)
		if r.get("damaged", false) and r.incident <= 0.0:
			_draw_damage(r, inner)
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
		if def.get("breeds", false) and Game.workers_in(r).size() >= 2 and r.incident <= 0.0:
			# пара в жилом отсеке: розовая полоска и сердечки
			var bar1 := Rect2(inner.position.x + 8, inner.end.y - 14, inner.size.x - 16, 7)
			draw_rect(bar1, Color(0, 0, 0, 0.55))
			draw_rect(Rect2(bar1.position, Vector2(bar1.size.x * r.progress, bar1.size.y)), Color(1.0, 0.45, 0.7))
			for i in 3:
				var ph := fmod(t * 0.4 + i * 0.33 + r.id * 0.1, 1.0)
				var hp := Vector2(inner.get_center().x + (i - 1) * 18 + sin(t * 2.0 + i) * 4, inner.end.y - 40 - ph * 50)
				_heart(hp, 6.0 * (1.0 - ph * 0.4), Color(1.0, 0.4, 0.6, 0.8 * sin(ph * PI)))
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
		"fire" when Art.tex("res://art/fx/fire_0.png") != null:
			draw_rect(inner, Color(1.0, 0.35, 0.05, 0.16 + 0.06 * sin(t * 12.0)))
			# дым поднимается к потолку
			for i in 3:
				var ph := fmod(t * 0.35 + i / 3.0, 1.0)
				var sm := Art.tex("res://art/fx/smoke_%d.png" % i)
				var sw := inner.size.y * (0.5 + 0.4 * ph)
				var sp := Vector2(inner.position.x + inner.size.x * (0.25 + 0.25 * i), inner.end.y - inner.size.y * (0.3 + 0.6 * ph))
				draw_texture_rect(sm, Rect2(sp - Vector2(sw, sw) / 2.0, Vector2(sw, sw * sm.get_height() / sm.get_width())), false, Color(1, 1, 1, 0.8 * (1.0 - ph) * minf(1.0, ph * 5.0)))
			var n := maxi(3, int(inner.size.x / 45))
			for i in n:
				# кадры 2..5 туда-обратно, у каждого языка своя фаза
				var seq := [2, 3, 4, 5, 4, 3]
				var fr: int = seq[int(t * 12.0 + i * 2.7) % seq.size()]
				var ft := Art.tex("res://art/fx/fire_%d.png" % fr)
				var fh := inner.size.y * (0.45 + 0.45 * hp) * (0.8 + 0.2 * sin(t * 3.0 + i * 1.9))
				var fw := fh * ft.get_width() / ft.get_height()
				var fx := inner.position.x + (i + 0.5) * inner.size.x / n + sin(t * 1.3 + i) * 6.0
				draw_texture_rect(ft, Rect2(fx - fw / 2.0, inner.end.y - fh + 2, fw, fh), false)
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
		"flood" when Art.tex("res://art/fx/water.png") != null:
			var level := inner.size.y * (0.15 + 0.6 * hp)
			var wt := Art.tex("res://art/fx/water.png")
			# полоса воды: высота волны пропорциональна картинке, плывёт вбок
			var wh := level + 26.0
			var tile_w := wh * wt.get_width() / wt.get_height() * 0.5
			var off := fmod(t * 30.0, tile_w)
			var x := inner.position.x - off
			var top := inner.end.y - wh + sin(t * 2.0) * 3.0
			while x < inner.end.x:
				var x0 := maxf(x, inner.position.x)
				var x1 := minf(x + tile_w, inner.end.x)
				var u0 := (x0 - x) / tile_w * wt.get_width() * 0.5
				var u1 := (x1 - x) / tile_w * wt.get_width() * 0.5
				draw_texture_rect_region(wt, Rect2(x0, top, x1 - x0, inner.end.y - top), Rect2(u0, 0, u1 - u0, wt.get_height()), Color(1, 1, 1, 0.9))
				x += tile_w
			# пока люди борются с потопом — в углу работает помпа
			var pump := Art.tex("res://art/fx/pump.png")
			if pump and not Game.responders(r).is_empty():
				var pw := inner.size.y * 0.5
				var ph2 := pw * pump.get_height() / pump.get_width()
				var shake := sin(t * 30.0) * 1.2
				draw_texture_rect(pump, Rect2(inner.position.x + 8 + shake, inner.end.y - ph2 - 2, pw, ph2), false)
			# струя из пробоины и брызги там, где она бьёт в воду
			var jet := Vector2(inner.position.x + inner.size.x * 0.7, inner.position.y + 10)
			var hit := Vector2(jet.x - 20, inner.end.y - level)
			draw_line(jet, hit, Color(0.6, 0.9, 1.0, 0.75), 6.0)
			draw_line(jet, hit, Color(1, 1, 1, 0.5), 2.0)
			var spl := Art.tex("res://art/fx/splash_%d.png" % (int(t * 6.0) % 3))
			var sw := 70.0
			draw_texture_rect(spl, Rect2(hit - Vector2(sw / 2.0, sw * 0.6), Vector2(sw, sw * spl.get_height() / spl.get_width())), false, Color(1, 1, 1, 0.9))
			var bub := Art.tex("res://art/fx/splash_3.png")
			for i in 3:
				var ph := fmod(t * 0.5 + i / 3.0, 1.0)
				var bp := Vector2(inner.position.x + inner.size.x * (0.15 + 0.2 * i), inner.end.y - ph * level)
				draw_texture_rect(bub, Rect2(bp - Vector2(12, 12), Vector2(24, 24)), false, Color(1, 1, 1, 0.8 * (1.0 - ph)))
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
		"raid":
			draw_rect(inner, Color(0.5, 0.0, 0.0, 0.12 + 0.06 * sin(t * 5.0)))
			_draw_raiders(r, inner)
		"creature":
			draw_rect(inner, Color(0.6, 0.0, 0.2, 0.12 + 0.08 * sin(t * 6.0)))
			var cid: String = r.get("creature", "angler")
			var fishy := Art.tex("res://art/creatures/boss_%s.png" % cid)
			if fishy == null:
				fishy = Art.tex("res://art/creatures/anglerfish.png")
			if fishy:
				var fh := inner.size.y * 0.72
				var fw := minf(inner.size.x * 0.55, fh * fishy.get_width() / fishy.get_height())
				fh = fw * fishy.get_height() / fishy.get_width()
				var lunge := sin(t * 2.5) * inner.size.x * 0.18
				var fc := Vector2(inner.get_center().x + lunge, inner.end.y - fh / 2.0 - 4 + sin(t * 5.0) * 3.0)
				var face := -signf(cos(t * 2.5))
				# красное свечение, чтобы монстр читался издалека
				draw_circle(fc, fh * 0.55, Color(1.0, 0.15, 0.1, 0.18 + 0.08 * sin(t * 8.0)))
				draw_set_transform(fc, sin(t * 5.0) * 0.08, Vector2(face, 1))
				draw_texture_rect(fishy, Rect2(-fw / 2.0, -fh / 2.0, fw, fh), false)
				draw_set_transform(Vector2.ZERO)
	# полоса угрозы и подпись
	var bar := Rect2(inner.position.x + 8, inner.position.y + 26, inner.size.x - 16, 10)
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * hp, bar.size.y)), Color(1.0, 0.3, 0.2))
	var label: String = tr(Game.HAZARDS[r.hazard].label)
	if r.hazard == "creature":
		# кто напал — имя монстра вместо общего «НАПАДЕНИЕ»
		label = tr(Game.CREATURE_NAMES.get(r.get("creature", "angler"), "Anglerfish")).to_upper()
	# подпись над полосой, чтобы не закрывать то, что происходит в отсеке; не шире отсека
	var fs := 17
	while fs > 11 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > inner.size.x - 20:
		fs -= 1
	var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_rect(Rect2(Vector2(inner.get_center().x - lw / 2.0 - 8, bar.end.y + 3), Vector2(lw + 16, 22)), Color(0.35, 0.0, 0.0, 0.75))
	_text(Vector2(inner.get_center().x, bar.end.y + 20), label, fs, Color(1.0, 0.9, 0.8, 0.75 + 0.25 * sin(t * 8.0)), true)
	# издалека (камера отдалена) — большой мигающий значок над отсеком
	if camera and camera.zoom.x < 0.95:
		var ip := Vector2(inner.get_center().x, inner.position.y - 34)
		var s := 30.0 / camera.zoom.x * 0.6
		draw_circle(ip, s, Color(0.85, 0.1, 0.1, 0.75 + 0.25 * sin(t * 6.0)))
		draw_arc(ip, s, 0, TAU, 24, Color(1, 1, 1, 0.9), 3.0)
		var icon_tex: Texture2D = null
		match r.hazard:
			"creature": icon_tex = Art.tex("res://art/creatures/boss_%s.png" % r.get("creature", "angler"))
			"fire": icon_tex = Art.tex("res://art/fx/fire_4.png")
			"flood": icon_tex = Art.tex("res://art/fx/splash_0.png")
			"raid": icon_tex = Art.tex("res://art/creatures/raider_1.png")
		if icon_tex:
			var iw := s * 1.5
			var ih := iw * icon_tex.get_height() / icon_tex.get_width()
			if ih > iw:
				ih = iw
				iw = ih * icon_tex.get_width() / icon_tex.get_height()
			draw_texture_rect(icon_tex, Rect2(ip - Vector2(iw, ih) / 2.0, Vector2(iw, ih)), false)

static func _short_time(sec: float) -> String:
	var s := maxi(0, int(sec))
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]

## Задняя стена отсека: чуть меньше рамки и сдвинута в сторону от центра экрана.
const DEPTH := 0.16          # глубина комнаты: видны пол, потолок и стены
const DEPTH_SHIFT := 0.05    # перспектива как в Fallout: задняя стена смещается к центру экрана

## Задняя стена отсека. Камера выше отсека — стена уезжает вверх: потолка не видно, пола больше;
## камера левее — видна правая стена, и наоборот.
func _diorama_back(inner: Rect2) -> Rect2:
	var m := Vector2(inner.size.x * DEPTH * 0.5, inner.size.y * DEPTH * 0.7)
	var cam := camera.get_screen_center_position() if camera else inner.get_center()
	var off := (cam - inner.get_center()) * DEPTH_SHIFT
	off.x = clampf(off.x, -m.x, m.x)
	off.y = clampf(off.y, -m.y, m.y)
	return Rect2(inner.position + m + off, inner.size - m * 2.0)

func _draw_diorama_walls(inner: Rect2, back: Rect2, col: Color, light: float) -> void:
	var a := inner.position
	var b := Vector2(inner.end.x, inner.position.y)
	var c := inner.end
	var d := Vector2(inner.position.x, inner.end.y)
	var ba := back.position
	var bb := Vector2(back.end.x, back.position.y)
	var bc := back.end
	var bd := Vector2(back.position.x, back.end.y)
	var base := Color(0.16, 0.18, 0.22).lerp(col.darkened(0.6), 0.35)
	var l := light
	# потолок, пол, стены — разная освещённость даёт объём
	draw_colored_polygon(PackedVector2Array([a, b, bb, ba]), Color(base.darkened(0.45), 1.0) * Color(l, l, l))
	draw_colored_polygon(PackedVector2Array([d, bd, bc, c]), Color(base.lightened(0.12), 1.0) * Color(l, l, l))
	draw_colored_polygon(PackedVector2Array([a, ba, bd, d]), Color(base.darkened(0.2), 1.0) * Color(l, l, l))
	draw_colored_polygon(PackedVector2Array([b, c, bc, bb]), Color(base.darkened(0.3), 1.0) * Color(l, l, l))
	# металлические панели пола и рёбра
	for i in 1:
		pass
	var lines := Color(0, 0, 0, 0.35)
	draw_line(a, ba, lines, 2.0)
	draw_line(b, bb, lines, 2.0)
	draw_line(c, bc, lines, 2.0)
	draw_line(d, bd, lines, 2.0)
	for k in range(1, 4):
		var f := k / 4.0
		draw_line(d.lerp(c, f), bd.lerp(bc, f), Color(0, 0, 0, 0.18), 1.5)
	# свет от лампы на полу
	draw_colored_polygon(PackedVector2Array([d.lerp(c, 0.25), d.lerp(c, 0.75), bd.lerp(bc, 0.7), bd.lerp(bc, 0.3)]), Color(col.lightened(0.4), 0.08 * l))

func _star(c: Vector2, rad: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + i * PI / 5
		var rr := rad if i % 2 == 0 else rad * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, Color(1.0, 0.85, 0.3))

## «Жизнь» поверх картинки отсека: мерцание ламп, пылинки и свой эффект у каждого типа.
## Всё полупрозрачное и неторопливое, чтобы не отвлекать.
func _draw_room_ambient(r: Dictionary, a: Rect2) -> void:
	var seed_f := float(r.id) * 1.37
	var x := func(f: float) -> float: return a.position.x + a.size.x * f
	var y := func(f: float) -> float: return a.position.y + a.size.y * f
	# лампы под потолком дышат
	var lamp := 0.05 + 0.03 * sin(t * 1.7 + seed_f)
	if fmod(t + seed_f * 3.0, 11.0) < 0.12:
		lamp = 0.0  # редкое моргание
	draw_rect(Rect2(a.position, Vector2(a.size.x, a.size.y * 0.18)), Color(1.0, 0.85, 0.55, lamp))
	# пылинки в свете
	for i in 5:
		var ph := fmod(t * 0.05 + i * 0.21 + seed_f, 1.0)
		var px: float = x.call(fmod(0.1 + i * 0.19 + sin(t * 0.3 + i) * 0.03, 1.0))
		var py: float = y.call(0.2 + 0.7 * ph)
		draw_circle(Vector2(px, py), 1.4, Color(1, 0.95, 0.85, 0.35 * sin(ph * PI)))
	match r.type:
		"oxygen", "aquarium", "observatory", "turbine":
			# пузырьки в баках и аквариумах
			for i in 8:
				var ph := fmod(t * (0.25 + 0.05 * (i % 3)) + i * 0.13 + seed_f, 1.0)
				var bx: float = x.call(0.15 + 0.7 * fmod(i * 0.37 + seed_f, 1.0)) + sin(t * 2.0 + i) * 3.0
				var by: float = y.call(0.85 - 0.6 * ph)
				draw_arc(Vector2(bx, by), 2.0 + ph * 2.0, 0, TAU, 10, Color(0.85, 1.0, 1.0, 0.55 * (1.0 - ph)), 1.2)
			if r.type != "oxygen":
				# блики воды
				var cs := 0.04 + 0.03 * sin(t * 2.3 + seed_f)
				draw_rect(Rect2(a.position + Vector2(0, a.size.y * 0.15), Vector2(a.size.x, a.size.y * 0.55)), Color(0.4, 0.85, 1.0, cs))
		"farm", "pearl":
			# споры / искорки над грядками
			var col := Color(0.6, 1.0, 0.5) if r.type == "farm" else Color(1.0, 0.85, 1.0)
			for i in 7:
				var ph := fmod(t * 0.12 + i * 0.143 + seed_f, 1.0)
				var sx: float = x.call(0.1 + 0.8 * fmod(i * 0.29 + seed_f, 1.0)) + sin(t + i) * 6.0
				draw_circle(Vector2(sx, y.call(0.8 - 0.5 * ph)), 1.8, Color(col, 0.6 * sin(ph * PI)))
		"kitchen":
			# пар над кастрюлями
			for i in 4:
				var ph := fmod(t * 0.3 + i * 0.25, 1.0)
				var sx: float = x.call(0.32 + 0.1 * (i % 2)) + sin(t * 1.5 + i) * 5.0
				draw_circle(Vector2(sx, y.call(0.5 - 0.3 * ph)), 4.0 + ph * 8.0, Color(1, 1, 1, 0.16 * (1.0 - ph)))
		"lab", "school", "radio", "medbay":
			# огоньки на пультах и мерцание экранов
			for i in 6:
				var on := fmod(t * (0.7 + i * 0.13) + i * 0.5 + seed_f, 1.0) < 0.5
				if on:
					var lc := [Color(0.3, 1.0, 0.4), Color(1.0, 0.3, 0.3), Color(0.3, 0.8, 1.0)][i % 3] as Color
					draw_circle(Vector2(x.call(0.12 + 0.15 * i), y.call(0.58 + 0.05 * (i % 2))), 2.2, Color(lc, 0.85))
			draw_rect(Rect2(Vector2(x.call(0.25), y.call(0.25)), Vector2(a.size.x * 0.4, a.size.y * 0.3)), Color(0.4, 1.0, 0.8, 0.03 + 0.03 * absf(sin(t * 6.0 + seed_f))))
		"lounge":
			# неон переливается
			var hue := fmod(t * 0.05 + seed_f, 1.0)
			draw_rect(a, Color.from_hsv(hue, 0.7, 1.0, 0.06))
		"workshop", "armory", "dock":
			# редкие вспышки сварки
			var cyc := fmod(t + seed_f * 5.0, 6.0)
			if cyc < 0.8 and r.type == "workshop":
				var sp := Art.tex("res://art/fx/spark_%d.png" % (int(t * 14.0) % 3))
				if sp:
					var ss := a.size.y * 0.25
					draw_texture_rect(sp, Rect2(Vector2(x.call(0.38), y.call(0.52)) - Vector2(ss, ss) / 2.0, Vector2(ss, ss)), false, Color(0.7, 0.85, 1.0, 0.9))
			# сигнальная лампа
			draw_circle(Vector2(x.call(0.9), y.call(0.15)), 3.0, Color(1.0, 0.3, 0.2, 0.4 + 0.4 * sin(t * 4.0 + seed_f)))
		"gym":
			# груша покачивается — тень маятника
			var sw := sin(t * 2.0 + seed_f) * a.size.x * 0.01
			draw_rect(Rect2(Vector2(x.call(0.24) + sw, y.call(0.3)), Vector2(a.size.x * 0.04, a.size.y * 0.3)), Color(0, 0, 0, 0.08))
		"living":
			# тёплый свет торшера
			draw_circle(Vector2(x.call(0.3), y.call(0.7)), a.size.y * 0.25, Color(1.0, 0.75, 0.4, 0.05 + 0.02 * sin(t * 1.3 + seed_f)))

## Сломанный отсек: копоть, трещины, искрящий провод и значок ремонта.
func _draw_damage(r: Dictionary, a: Rect2) -> void:
	draw_rect(a, Color(0.05, 0.03, 0.02, 0.35))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(r.id) * 7 + 3
	for i in 3:
		var p := Vector2(a.position.x + a.size.x * rng.randf_range(0.15, 0.85), a.position.y + a.size.y * rng.randf_range(0.2, 0.6))
		var pts := PackedVector2Array([p])
		for k in 4:
			p += Vector2(rng.randf_range(-14, 14), rng.randf_range(6, 14))
			pts.append(p)
		draw_polyline(pts, Color(0.05, 0.05, 0.05, 0.8), 2.0)
	# искрит
	if fmod(t + r.id, 1.6) < 0.25:
		var sp := Art.tex("res://art/fx/spark_%d.png" % (int(t * 12.0) % 3))
		if sp:
			var s := a.size.y * 0.3
			draw_texture_rect(sp, Rect2(Vector2(a.position.x + a.size.x * 0.7, a.position.y + 6) - Vector2(s, 0) / 2.0, Vector2(s, s)), false)
	var wp := Vector2(a.end.x - 22, a.position.y + 40)
	draw_circle(wp, 15, Color(0.25, 0.12, 0.02, 0.9))
	draw_arc(wp, 15, 0, TAU, 20, Color(1.0, 0.65, 0.3, 0.6 + 0.4 * sin(t * 4.0)), 2.5)
	draw_line(wp + Vector2(-6, 6), wp + Vector2(5, -5), Color(1.0, 0.85, 0.6), 3.0)
	draw_circle(wp + Vector2(6, -6), 3.5, Color(1.0, 0.85, 0.6))

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

## Колонист отдыхает: в жилом отсеке, баре или на палубе, и там спокойно — шлем можно снять.
func is_resting(c: Dictionary) -> bool:
	if c.get("help", -1) != -1 or c.room < 0:
		return false
	var r := Game.get_room(c.room)
	return not r.is_empty() and r.type in ["living", "lounge", "observatory"] and r.incident <= 0.0

func _draw_colonist(feet: Vector2, c: Dictionary, lifted: bool) -> void:
	var sprite := Art.colonist(c, is_resting(c) and not lifted)
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
	var working: bool = w.get("working", false) and not walking and not lifted
	var fighting: bool = w.get("fighting", false) and w.get("panic", false) and not lifted
	if fighting:
		walking = false
	var h := 62.0 * (1.15 if lifted else depth_scale(c)) * (0.6 if c.get("child", false) else 1.0)
	var size := Vector2(h * sprite.get_width() / sprite.get_height(), h)
	var bob := absf(sin(t * 10.0 + c.id)) * -3.0 if walking else sin(t * 2.0 + c.id) * 0.8
	var facing: float = w.get("facing", 1.0)
	if lifted:
		draw_circle(feet + Vector2(0, 2), 16, Color(0, 0, 0, 0.3))
	var tint := Color.WHITE if c.health >= 50.0 else Color(0.75, 0.75, 0.75)
	var rest_art: bool = is_resting(c) and not lifted and Art.rest(int(c.suit)) != null
	if walking and not c.get("child", false) and not rest_art:
		var frame := Art.walk_frame(c.suit, t * 11.0 + c.id)
		if frame:
			sprite = frame
			size = Vector2(h * 0.95 * sprite.get_width() / sprite.get_height(), h * 0.95)
			bob = 0.0
	var squash := 1.0
	var lean := 0.0
	if fighting:
		# резкие удары / отдача от выстрела
		var hit := sin(t * 12.0 + c.id * 2.3)
		lean = 0.12 * maxf(0.0, hit) * facing
		squash = 1.0 - 0.04 * absf(hit)
		bob = 0.0
	elif working:
		# ритмичные движения: наклон и «работа руками»
		var beat := sin(t * 7.0 + c.id * 1.7)
		squash = 1.0 - 0.05 * maxf(0.0, beat)
		lean = 0.07 * beat * facing
		bob = 0.0
	draw_set_transform(feet + Vector2(0, bob), lean, Vector2(facing, squash))
	draw_texture_rect(sprite, Rect2(Vector2(-size.x / 2.0, -size.y), size), false, tint)
	draw_set_transform(Vector2.ZERO)
	if working:
		_draw_work_fx(feet, c, facing, h)
	if fighting:
		_draw_fight_fx(feet, c, facing, h)
	if c.room == -1 and c.get("help", -1) == -1 and not lifted:
		# свободен — просит работу
		var bp := feet + Vector2(0, -h - 20 + sin(t * 3.0 + c.id) * 3.0)
		draw_circle(bp, 13, Color(1.0, 1.0, 1.0, 0.92))
		draw_colored_polygon(PackedVector2Array([bp + Vector2(-5, 10), bp + Vector2(5, 10), bp + Vector2(0, 17)]), Color(1, 1, 1, 0.92))
		_text(bp + Vector2(0, 7), "?", 20, Color(0.1, 0.3, 0.6), true)
	if w.get("panic", false) and not fighting:
		var ex := feet + Vector2(0, -h - 22 + sin(t * 10.0 + c.id) * 3.0)
		draw_circle(ex, 11, Color(1.0, 0.85, 0.2))
		_text(ex + Vector2(0, 7), "!", 20, Color(0.2, 0.05, 0.0), true)
	if c.health < 99.0:
		var hb := Rect2(feet + Vector2(-12, -h - 8), Vector2(24, 4))
		draw_rect(hb, Color(0, 0, 0, 0.6))
		draw_rect(Rect2(hb.position, Vector2(hb.size.x * c.health / 100.0, hb.size.y)), Color(1.0, 0.3, 0.3).lerp(Color(0.4, 1.0, 0.4), c.health / 100.0))

## Где стоять во время беды: у чудовища / огня, чуть в стороне, у каждого своё место.
func _hazard_focus_x(room: Dictionary) -> float:
	if room.get("hazard", "") == "creature":
		return 0.5 + sin(t * 2.5) * 0.2
	if room.get("hazard", "") == "raid":
		return 0.6 + sin(t * 1.5) * 0.06
	return 0.5

func _hazard_target_x(room: Dictionary, cid: int) -> float:
	var side := -1.0 if cid % 2 == 0 else 1.0
	return clampf(_hazard_focus_x(room) + side * (0.22 + 0.06 * (cid % 3)), 0.05, 0.95)

## Бой: гарпун стреляет, горелка жжёт, инструменты бьют, без оружия — кулаки.
## Пожар — огнетушитель, потоп — насос с брызгами.
func _draw_fight_fx(feet: Vector2, c: Dictionary, facing: float, h: float) -> void:
	var room := Game.get_room(c.help if c.get("help", -1) != -1 else c.room)
	if room.is_empty():
		return
	var rect := room_rect(room)
	var hand := feet + Vector2(facing * 22.0, -h * 0.5)
	var focus := Vector2(rect.position.x + 22 + _hazard_focus_x(room) * (rect.size.x - 44), hand.y)
	var k := fmod(t * 2.2 + c.id * 0.41, 1.0)
	match room.hazard:
		"creature", "raid":
			var tool_id := ""
			var uid: int = c.get("tool_item", -1)
			if uid != -1:
				tool_id = Game.get_item(uid).get("base", "")
			# оружие важнее инструмента: своя анимация и картинка в руке
			var wuid: int = c.get("weapon_item", -1)
			if wuid != -1:
				var wit := Game.get_item(wuid)
				if not wit.is_empty():
					tool_id = str(Game.item_base(wit).get("anim", "melee"))
					var wtex := Art.tex("res://art/items/%s.png" % wit.base)
					if wtex:
						var ws := h * 0.42
						draw_set_transform(hand, -0.4 * facing + sin(t * 9.0 + c.id) * 0.25 * facing, Vector2(facing, 1))
						draw_texture_rect(wtex, Rect2(-ws * 0.3, -ws * 0.5, ws, ws), false)
						draw_set_transform(Vector2.ZERO)
			match tool_id:
				"shock":
					# электрические дуги к цели
					if k < 0.6:
						var pts := PackedVector2Array([hand])
						for i in 6:
							var q := (i + 1) / 6.0
							pts.append(hand.lerp(focus, q * 0.6) + Vector2(0, randf_range(-8, 8)))
						draw_polyline(pts, Color(0.6, 0.85, 1.0, 1.0 - k), 3.0)
						draw_polyline(pts, Color(1, 1, 1, 0.8 - k), 1.2)
				"sonic":
					for i in 3:
						var q := fmod(k + i / 3.0, 1.0)
						var cpos := hand.lerp(focus, q * 0.7)
						draw_arc(cpos, 6.0 + 14.0 * q, -0.9, 0.9, 10, Color(0.75, 0.6, 1.0, 1.0 - q), 3.0) if facing > 0 else draw_arc(cpos, 6.0 + 14.0 * q, PI - 0.9, PI + 0.9, 10, Color(0.75, 0.6, 1.0, 1.0 - q), 3.0)
				"harpoon":
					# гарпун летит к чудовищу
					var p := hand.lerp(focus, k)
					draw_line(hand, p, Color(0.8, 0.8, 0.75, 0.7), 1.5)
					draw_line(p - Vector2(facing * 14, 0), p, Color(0.85, 0.85, 0.9), 4.0)
					draw_colored_polygon(PackedVector2Array([p, p - Vector2(facing * 8, -5), p - Vector2(facing * 8, 5)]), Color(0.95, 0.95, 1.0))
				"torch":
					for i in 6:
						var q := fmod(k + i / 6.0, 1.0)
						var p := hand + Vector2(facing * q * 60.0, sin(t * 20.0 + i) * 4.0 * q)
						draw_circle(p, 3.0 + 6.0 * q, Color(1.0, 0.8 - 0.5 * q, 0.2, 0.9 * (1.0 - q)))
				"":
					# кулаки: «бах» у руки
					if k < 0.4:
						var pp := hand + Vector2(facing * 10.0, 0)
						_star_burst(pp, 10.0 + 14.0 * k, Color(1.0, 0.95, 0.5, 1.0 - k * 2.0))
				_:
					# удар инструментом — дуга
					var a0 := -PI * 0.8 if facing > 0 else -PI * 0.2
					draw_arc(hand, 26.0, a0, a0 + PI * 0.6 * facing, 12, Color(1, 1, 1, 0.8 * (1.0 - k)), 3.0)
					if k < 0.3:
						_star_burst(hand + Vector2(facing * 24, -6), 9.0, Color(1.0, 0.9, 0.5, 1.0 - k * 3.0))
		"fire":
			# огнетушитель: белая пена конусом к огню
			var ext := Art.tex("res://art/fx/extinguisher.png")
			if ext:
				# на картинке баллон слева, пена справа — берём левую часть, пену рисуем частицами
				var ew := h * 0.42
				var eh := ew * ext.get_height() / (ext.get_width() * 0.5)
				draw_set_transform(hand + Vector2(-facing * 4, 0), 0.0, Vector2(facing, 1))
				draw_texture_rect_region(ext, Rect2(-ew * 0.5, -eh * 0.6, ew, eh), Rect2(0, 0, ext.get_width() * 0.5, ext.get_height()))
				draw_set_transform(Vector2.ZERO)
			else:
				draw_rect(Rect2(hand - Vector2(5, 10), Vector2(10, 20)), Color(0.85, 0.15, 0.15))
			for i in 9:
				var q := fmod(k + i / 9.0, 1.0)
				var spread := (i % 3 - 1) * 10.0 * q
				var p := hand + Vector2(facing * (10.0 + q * 70.0), spread + q * 8.0)
				draw_circle(p, 3.0 + 7.0 * q, Color(0.95, 0.98, 1.0, 0.85 * (1.0 - q)))
		"flood":
			# откачивают воду: брызги из ведра
			var bucket := Art.tex("res://art/fx/bucket.png")
			if bucket:
				var bw := h * 0.38
				var bh := bw * bucket.get_height() / bucket.get_width()
				draw_texture_rect(bucket, Rect2(hand - Vector2(bw * 0.5, bh * 0.55), Vector2(bw, bh)), false)
			else:
				draw_rect(Rect2(hand - Vector2(7, 6), Vector2(14, 12)), Color(0.55, 0.6, 0.7))
			for i in 5:
				var q := fmod(k + i / 5.0, 1.0)
				var p := hand + Vector2(facing * (6.0 + q * 30.0) + (i - 2) * 3.0, -q * 36.0 + q * q * 40.0)
				draw_circle(p, 3.0, Color(0.6, 0.9, 1.0, 1.0 - q))

func _heart(c: Vector2, s: float, col: Color) -> void:
	draw_circle(c + Vector2(-s * 0.5, 0), s * 0.6, col)
	draw_circle(c + Vector2(s * 0.5, 0), s * 0.6, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 1.05, s * 0.2), c + Vector2(s * 1.05, s * 0.2), c + Vector2(0, s * 1.4)]), col)

## Лёгкая тряска камеры (сбор, удары).
var shake := 0.0

func add_shake(v: float) -> void:
	shake = minf(10.0, shake + v)

func _star_burst(c: Vector2, r: float, col: Color) -> void:
	var sp := Art.tex("res://art/fx/spark_%d.png" % (int(t * 14.0 + c.x) % 3))
	if sp:
		var s := r * 3.2
		draw_texture_rect(sp, Rect2(c - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, col.a))
		return
	var pts := PackedVector2Array()
	for i in 16:
		var a := i * TAU / 16.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, col)

## Эффект работы у рук колониста — по типу отсека.
func _draw_work_fx(feet: Vector2, c: Dictionary, facing: float, h: float) -> void:
	var room := Game.get_room(c.room)
	if room.is_empty():
		return
	var hand := feet + Vector2(facing * 20.0, -h * 0.5)
	var k := fmod(t * 1.8 + c.id * 0.37, 1.0)
	match room.type:
		"reactor", "dock", "storage", "workshop", "armory", "gym":
			# искры от инструмента
			for i in 4:
				var a: float = (i * 1.7 + c.id) + t * 9.0
				var r := 8.0 + 24.0 * fmod(k + i * 0.25, 1.0)
				var p := hand + Vector2(cos(a) * r * facing, sin(a) * r * 0.6 - r * 0.3)
				draw_circle(p, 3.4, Color(1.0, 0.85 - 0.3 * fmod(k + i * 0.25, 1.0), 0.3, 1.0 - fmod(k + i * 0.25, 1.0)))
		"oxygen":
			for i in 3:
				var q := fmod(k + i * 0.33, 1.0)
				draw_arc(hand + Vector2(sin(t * 3.0 + i) * 4.0, -q * 48.0), 4.5 + q * 3.0, 0, TAU, 10, Color(0.8, 1.0, 1.0, 0.95 * (1.0 - q)), 2.5)
		"farm", "pearl", "medbay", "kitchen":
			for i in 3:
				var q := fmod(k + i * 0.33, 1.0)
				var col: Color = {"farm": Color(0.5, 1.0, 0.5), "pearl": Color(1.0, 0.8, 0.95), "kitchen": Color(1.0, 0.9, 0.7)}.get(room.type, Color(1.0, 0.5, 0.5))
				var p := hand + Vector2((i - 1) * 10.0, -q * 38.0)
				draw_circle(p, 5.0 * (1.0 - q) + 1.5, Color(col, 1.0 - q))
		"lab", "school", "radio", "lounge":
			for i in 4:
				var q := fmod(k + i * 0.25, 1.0)
				var a := i * TAU / 4.0 + t * 2.0
				var lc: Color = Defs.ROOMS[room.type].color.lightened(0.2)
				draw_circle(hand + Vector2(cos(a), sin(a)) * (6.0 + 16.0 * q), 3.2, Color(lc, 1.0 - q))

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

## Где лежит тело павшего колониста (в отсеке, где он погиб).
func fallen_pos(i: int) -> Vector2:
	var f: Dictionary = Game.fallen[i]
	var r := Game.get_room(int(f.room))
	if r.is_empty():
		r = Game.find_room_of_type("airlock")
	if r.is_empty():
		return Vector2(200, CELL_H - 12)
	var rect := room_rect(r)
	var k := fmod(float(f.c.id) * 0.37, 1.0)
	return Vector2(rect.position.x + rect.size.x * (0.25 + 0.5 * k), rect.end.y - 14)

func _draw_fallen() -> void:
	for i in Game.fallen.size():
		var f: Dictionary = Game.fallen[i]
		var p := fallen_pos(i)
		var sprite := Art.diver(int(f.c.suit))
		if sprite:
			var h := 58.0
			var sz := Vector2(h * sprite.get_width() / sprite.get_height(), h)
			# лежит на боку, серый
			draw_set_transform(p + Vector2(0, -sz.x * 0.5 + 4), -PI / 2.0, Vector2.ONE)
			draw_texture_rect(sprite, Rect2(Vector2(-sz.x / 2.0, -sz.y / 2.0), sz), false, Color(0.55, 0.55, 0.6))
			draw_set_transform(Vector2.ZERO)
		var pulse := 0.5 + 0.5 * sin(t * 4.0 + i)
		var bp := p + Vector2(0, -52)
		draw_circle(bp, 17, Color(0.25, 0.02, 0.05, 0.85))
		draw_arc(bp, 17, 0, TAU, 24, Color(1.0, 0.35, 0.35, 0.6 + 0.4 * pulse), 3.0)
		draw_rect(Rect2(bp - Vector2(3, 10), Vector2(6, 20)), Color(1.0, 0.85, 0.85))
		draw_rect(Rect2(bp - Vector2(9, 4), Vector2(18, 6)), Color(1.0, 0.85, 0.85))
		_text(bp + Vector2(0, -24), _short_time(float(f.until) - Game.now()), 15, Color(1.0, 0.75, 0.75), true)

func raider_body_pos(b: Dictionary) -> Vector2:
	var r := Game.get_room(int(b.room))
	if r.is_empty():
		return Vector2(-9999, -9999)
	var rect := room_rect(r)
	return Vector2(rect.position.x + rect.size.x * float(b.x), rect.end.y - 12)

func _draw_raider_bodies() -> void:
	for b in Game.raider_bodies:
		var p := raider_body_pos(b)
		var spr := Art.tex("res://art/creatures/raider_%d.png" % int(b.kind))
		var tint := Color(0.7, 0.7, 0.7)
		if spr == null:
			spr = Art.diver(3 + int(b.kind))
			tint = Color(0.42, 0.28, 0.28)
		if spr:
			var h := 58.0
			var sz := Vector2(h * spr.get_width() / spr.get_height(), h)
			draw_set_transform(p + Vector2(0, -sz.x * 0.5 + 4), PI / 2.0, Vector2.ONE)
			draw_texture_rect(spr, Rect2(Vector2(-sz.x / 2.0, -sz.y / 2.0), sz), false, tint)
			draw_set_transform(Vector2.ZERO)
		# блестит — можно обыскать
		var tw := 0.5 + 0.5 * sin(t * 5.0 + float(b.id))
		var sp := p + Vector2(10, -34)
		draw_circle(sp, 6 + 3 * tw, Color(1.0, 0.85, 0.3, 0.25 + 0.25 * tw))
		Icons.draw(self, "pearls", sp, 8.0, Defs.RESOURCES.pearls.color)

func _on_press(p: Vector2) -> void:
	press_pos = p
	moved = false
	drag_colonist = -1
	if build_type != "":
		return
	var world := screen_to_world(p)
	if not Game.boss.is_empty() and boss_rect().grow(30).has_point(world):
		moved = true
		var dmg := Game.hit_boss()
		boss_hit = 1.0
		add_shake(4.0)
		Audio.play("hit", randf_range(0.85, 1.15))
		floaters.append({"pos": world + Vector2(randf_range(-20, 20), -20), "text": "-%d" % dmg, "icon": "", "color": Color(1.0, 0.5, 0.4), "life": 0.9})
		return
	for b in Game.raider_bodies:
		var bp := raider_body_pos(b)
		if world.distance_to(bp + Vector2(0, -20)) < 40.0:
			moved = true
			var loot := Game.loot_raider(b)
			var parts := []
			for it in [["pearls", loot.get("pearls", 0)], ["crystals", loot.get("crystals", 0)], ["food", loot.get("resources", 0)]]:
				if it[1] > 0:
					parts.append(it)
			for k in parts.size():
				floaters.append({"pos": bp + Vector2(0, -40 - 34 * k), "text": "+%d" % parts[k][1], "icon": parts[k][0], "color": Color(1.0, 0.9, 0.6), "life": 1.6})
			if loot.has("item"):
				floaters.append({"pos": bp + Vector2(0, -40 - 34 * parts.size()), "text": tr("Gear!"), "icon": "item_" + str(loot.item_base), "color": Defs.ITEM_RARITY[loot.item].color, "life": 2.0})
			return
	for i in Game.fallen.size():
		if world.distance_to(fallen_pos(i) + Vector2(0, -30)) < 40.0:
			moved = true
			fallen_tapped.emit(i)
			return
	if _try_pop_treasure(world):
		moved = true
		return
	if not Game.trader.is_empty() and _trader_rect().grow(50).has_point(world):
		moved = true
		trader_tapped.emit()
		return
	for c in Game.colonists:
		if c.room == Game.ON_EXPEDITION:
			continue
		var cp := colonist_world_pos(c)
		if world.distance_to(cp + Vector2(0, -28)) < 30.0:
			drag_colonist = c.id
			drag_pos = world
			Input.vibrate_handheld(30)
			Audio.play("tap", 1.4)
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
		# короткое нажатие на колониста в готовом отсеке — это сбор, как в Fallout
		var here := Game.room_at(cell.x, cell.y)
		if not here.is_empty() and here.ready:
			Game.collect(here)
			return
		colonist_selected.emit(c.id)
		return
	if moved:
		return
	if build_type != "":
		# в режиме стройки можно собирать готовые ресурсы
		var tapped := Game.room_at(cell.x, cell.y)
		if not tapped.is_empty() and tapped.ready:
			Game.collect(tapped)
			return
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
	if room.is_empty() and cell.y >= 0 and cell.y < Defs.MAX_DEPTH and not Game.zone_unlocked_row(cell.y):
		locked_zone_tapped.emit(str(Game.depth_zone(cell.y).research))
		return
	var al := Game.find_room_of_type("airlock")
	if room.is_empty() and world.y < 0 and world.y > -260 and not al.is_empty() and absf(world.x - room_rect(al).get_center().x) < 170:
		outside_tapped.emit()
		return
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

func focus_cell(cell: Vector2i, w: int) -> void:
	var target := Vector2((cell.x + w / 2.0) * CELL_W, (cell.y + 0.5) * CELL_H + 80)
	target.x = clampf(target.x, 300, Defs.GRID_COLS * CELL_W - 300)
	var tw := create_tween()
	tw.tween_property(camera, "position", target, 0.4).set_trans(Tween.TRANS_SINE)

func focus_room(r: Dictionary) -> void:
	var target := room_rect(r).get_center() + Vector2(0, 120)
	var tw := create_tween()
	tw.tween_property(camera, "position", target, 0.35).set_trans(Tween.TRANS_SINE)

extends CanvasLayer
## Обучение новичка: затемнение, подсветка цели, указатель и реплики командира.
## Не блокирует ввод — игрок нажимает на подсвеченное место сам.

var hud
var view
var step := -1
var overlay: Control
var bubble: PanelContainer
var text_label: Label
var next_btn: Button
var t := 0.0

## target: "room:<type>" | "button:<index>" | "top" | "" ; wait: как понять, что шаг выполнен.
const STEPS := [
	{"text": "Welcome, Overseer! I'm Commander Reyes. This colony at the bottom of the ocean is our last home. Let me show you around.", "target": "", "wait": "next"},
	{"text": "The reactor has produced energy. Tap the reactor to collect it!", "target": "room:reactor", "wait": "event:collect_energy"},
	{"text": "Great! Keep an eye on energy, oxygen and food up here. If they run out, colonists get hurt.", "target": "top", "wait": "next"},
	{"text": "We need room for new survivors. Tap Build.", "target": "button:0", "wait": "sheet:build"},
	{"text": "Choose Living Quarters from the list.", "target": "", "wait": "build_mode"},
	{"text": "Tap a glowing green slot to build it there.", "target": "", "wait": "event:build"},
	{"text": "One colonist is idle in the airlock. Drag them with your finger into a room with free slots, like the Algae Farm.", "target": "drag", "wait": "event:assign"},
	{"text": "Tap any colonist to see their skills, level and gear.", "target": "", "wait": "sheet:colonist"},
	{"text": "Colonists level up while working. Put strong ones in the Reactor, techies in the O₂ Generator, biologists on the Farm.", "target": "", "wait": "next"},
	{"text": "Story missions, daily tasks, research and achievements are in Tasks. Follow my missions and the colony will grow.", "target": "button:2", "wait": "sheet:tasks"},
	{"text": "Watch out for fires, floods and sea creatures. Drag colonists into trouble to fix it. Good luck, Overseer!", "target": "", "wait": "next"},
]

func _ready() -> void:
	layer = 20
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	bubble = PanelContainer.new()
	bubble.theme = hud.theme_res
	bubble.add_theme_stylebox_override("panel", hud._box(Color(0.04, 0.1, 0.18, 0.97), Color(1.0, 0.82, 0.4), 20, 3))
	bubble.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bubble.offset_left = 16
	bubble.offset_right = -16
	add_child(bubble)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	bubble.add_child(hb)
	hb.add_child(hud.reyes_portrait(120))
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	vb.add_child(hud._label(tr("Commander Reyes"), 20, Color(1.0, 0.85, 0.45)))
	text_label = hud._label("", 20)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(text_label)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.add_theme_constant_override("separation", 10)
	var skip: Button = hud._button(tr("Skip tutorial"), finish, 52)
	skip.add_theme_font_size_override("font_size", 16)
	skip.modulate = Color(1, 1, 1, 0.7)
	btns.add_child(skip)
	next_btn = hud._button(tr("Next"), _advance, 52)
	next_btn.custom_minimum_size.x = 140
	btns.add_child(next_btn)
	vb.add_child(btns)
	Game.event.connect(_on_event)
	_show(0)

func _show(i: int) -> void:
	step = i
	if step >= STEPS.size():
		finish()
		return
	var s: Dictionary = STEPS[step]
	text_label.text = tr(s.text)
	next_btn.visible = s.wait == "next"
	bubble.modulate.a = 0.0
	create_tween().tween_property(bubble, "modulate:a", 1.0, 0.25)

func _advance() -> void:
	_show(step + 1)

func _on_event(ev: String) -> void:
	if step >= 0 and step < STEPS.size() and STEPS[step].wait == "event:" + ev:
		_advance.call_deferred()

func finish() -> void:
	Game.tutorial_done = true
	Game.save_game()
	queue_free()

func _process(delta: float) -> void:
	t += delta
	if step < 0 or step >= STEPS.size():
		return
	var w: String = STEPS[step].wait
	if w.begins_with("sheet:") and hud.sheet_kind == w.trim_prefix("sheet:"):
		_advance()
	elif w == "build_mode" and view.build_type != "":
		_advance()
	# если игрок открыл другое меню — подсказка не должна его закрывать
	var target: String = STEPS[step].target
	var expects_sheet: bool = w.begins_with("sheet:") or w == "build_mode"
	var paused: bool = hud.sheet.visible and not expects_sheet and target != ""
	paused = paused or (hud.popup_bg.visible)
	bubble.visible = not paused
	overlay.visible = not paused
	# пузырь ставим подальше от цели
	var r := _target_rect()
	var vp := overlay.size
	var target_low := r.size != Vector2.ZERO and r.get_center().y > vp.y * 0.5
	if hud.sheet.visible:
		bubble.offset_top = 150
	elif r.size == Vector2.ZERO or target_low:
		bubble.offset_top = 150
	else:
		bubble.offset_top = vp.y - 360
	bubble.offset_bottom = bubble.offset_top
	overlay.queue_redraw()

func _world_to_screen(p: Vector2) -> Vector2:
	return view.get_viewport().get_canvas_transform() * p

## Для шага «перетащи колониста»: откуда (свободный колонист) и куда (отсек со свободным местом).
func _drag_path() -> Array:
	var idle := {}
	for c in Game.colonists:
		if c.room == -1 and c.get("help", -1) == -1:
			idle = c
			break
	if idle.is_empty():
		return []
	var dest := {}
	for type in ["farm", "oxygen", "reactor"]:
		for rr in Game.rooms:
			if rr.type == type and Game.workers_in(rr).size() < Game.slots(rr):
				dest = rr
				break
		if not dest.is_empty():
			break
	if dest.is_empty():
		return []
	var from := _world_to_screen(view.colonist_world_pos(idle) + Vector2(0, -30))
	var to := _world_to_screen(view.room_rect(dest).get_center())
	var xf: Transform2D = view.get_viewport().get_canvas_transform()
	var rr2: Rect2 = view.room_rect(dest)
	return [from, to, Rect2(xf * rr2.position, xf.basis_xform(rr2.size))]

func _target_rect() -> Rect2:
	if step < 0 or step >= STEPS.size():
		return Rect2()
	var target: String = STEPS[step].target
	if target == "drag":
		var path := _drag_path()
		return path[2].grow(6) if not path.is_empty() else Rect2()
	if target.begins_with("room:"):
		var room := Game.find_room_of_type(target.trim_prefix("room:"))
		if room.is_empty():
			return Rect2()
		var xf: Transform2D = view.get_viewport().get_canvas_transform()
		var rr: Rect2 = view.room_rect(room)
		return Rect2(xf * rr.position, xf.basis_xform(rr.size)).grow(6)
	if target.begins_with("button:"):
		var b: Control = hud.bottom_bar.get_child(int(target.trim_prefix("button:")))
		return b.get_global_rect().grow(6) if b.is_visible_in_tree() else Rect2()
	if target == "top":
		return Rect2(12, 12, overlay.size.x - 24, 130)
	return Rect2()

func _draw_overlay() -> void:
	var r := _target_rect()
	var vp := overlay.size
	var dim := Color(0, 0, 0, 0.55)
	if r.size == Vector2.ZERO:
		if STEPS[step].wait == "next":
			overlay.draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.35))
		return
	overlay.draw_rect(Rect2(0, 0, vp.x, r.position.y), dim)
	overlay.draw_rect(Rect2(0, r.end.y, vp.x, vp.y - r.end.y), dim)
	overlay.draw_rect(Rect2(0, r.position.y, r.position.x, r.size.y), dim)
	overlay.draw_rect(Rect2(r.end.x, r.position.y, vp.x - r.end.x, r.size.y), dim)
	var pulse := 0.5 + 0.5 * sin(t * 5.0)
	overlay.draw_rect(r, Color(1.0, 0.85, 0.3, 0.6 + 0.4 * pulse), false, 4.0)
	overlay.draw_rect(r.grow(6 + 6 * pulse), Color(1.0, 0.85, 0.3, 0.3 * (1.0 - pulse)), false, 3.0)
	if STEPS[step].target == "drag":
		_draw_drag_hint()
		return
	# стрелка над целью, остриём вниз (если цель у самого верха — под целью, остриём вверх)
	var above := r.position.y > 110
	var dir := 1.0 if above else -1.0
	var tip := Vector2(r.get_center().x, r.position.y - 6 if above else r.end.y + 6)
	var bounce := Vector2(0, -dir * 12.0 * (0.5 + 0.5 * sin(t * 6.0)))
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(-22, -28 * dir), Vector2(-9, -28 * dir),
		Vector2(-9, -64 * dir), Vector2(9, -64 * dir), Vector2(9, -28 * dir), Vector2(22, -28 * dir)])
	for i in pts.size():
		pts[i] += tip + bounce
	overlay.draw_colored_polygon(pts, Color(1.0, 0.85, 0.3))
	var outline := pts.duplicate()
	outline.append(pts[0])
	overlay.draw_polyline(outline, Color(0.3, 0.15, 0.0), 3.0)
	# «нажми сюда» — пульсирующий круг в центре цели
	var c := r.get_center()
	overlay.draw_arc(c, 18 + 14 * pulse, 0, TAU, 32, Color(1, 1, 1, 0.8 * (1.0 - pulse)), 4.0)
	overlay.draw_circle(c, 10, Color(1.0, 0.9, 0.4, 0.9))

## Анимированный «палец» тащит колониста из шлюза в отсек.
func _draw_drag_hint() -> void:
	var path := _drag_path()
	if path.is_empty():
		return
	var from: Vector2 = path[0]
	var to: Vector2 = path[1]
	var k := fmod(t * 0.6, 1.3)
	var f := clampf(k, 0.0, 1.0)
	f = f * f * (3.0 - 2.0 * f)
	var p := from.lerp(to, f) + Vector2(0, -sin(f * PI) * 60.0)
	# пунктир траектории
	for i in 20:
		var q := float(i) / 20.0
		var pt := from.lerp(to, q) + Vector2(0, -sin(q * PI) * 60.0)
		overlay.draw_circle(pt, 3, Color(1.0, 0.9, 0.5, 0.6))
	overlay.draw_arc(from, 30, 0, TAU, 32, Color(1.0, 0.9, 0.4, 0.9), 4.0)
	overlay.draw_circle(p, 22, Color(1, 1, 1, 0.35))
	overlay.draw_circle(p, 14, Color(1.0, 0.85, 0.3))
	overlay.draw_arc(p, 14, 0, TAU, 24, Color(0.3, 0.15, 0.0), 3.0)

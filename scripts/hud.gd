extends CanvasLayer
## Интерфейс: ресурсы, строительство, карточка отсека, список колонистов, сообщения.

const ACCENT := Color(0.35, 0.92, 1.0)
const PANEL_BG := Color(0.03, 0.09, 0.16, 0.92)

var view: Node2D
var root: Control
var theme_res: Theme
var res_bars := {}
var pearls_label: Label
var pop_label: Label
var bottom_bar: HBoxContainer
var sheet: PanelContainer          # нижняя выдвижная панель
var sheet_body: VBoxContainer
var sheet_kind := ""               # "", "build", "room", "colonists", "pick"
var sheet_room := -1
var build_hint: PanelContainer
var build_hint_label: Label
var toast: Label
var toast_time := 0.0
var refresh_timer := 0.0

func _ready() -> void:
	theme_res = _make_theme()
	root = Control.new()
	root.theme = theme_res
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top_bar()
	_build_bottom_bar()
	_build_sheet()
	_build_build_hint()
	_build_toast()
	Game.changed.connect(_on_changed)
	Game.message.connect(show_toast)
	view.room_selected.connect(_on_room_selected)
	view.build_finished.connect(_on_build_finished)
	_refresh_top()

func _process(delta: float) -> void:
	refresh_timer += delta
	if refresh_timer > 0.2:
		refresh_timer = 0.0
		_refresh_top()
		if sheet_kind == "room":
			_refresh_room_live()
	if toast_time > 0.0:
		toast_time -= delta
		toast.modulate.a = clampf(toast_time * 2.0, 0.0, 1.0)

# ---------------------------------------------------------------- тема

func _box(bg: Color, border: Color, radius := 18, bw := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(14)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	return s

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 24
	th.set_stylebox("panel", "PanelContainer", _box(PANEL_BG, Color(ACCENT, 0.45)))
	var normal := _box(Color(0.07, 0.25, 0.36), Color(ACCENT, 0.7), 14)
	normal.set_content_margin_all(12)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.1, 0.33, 0.46)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.05, 0.18, 0.26)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.1, 0.12, 0.15)
	disabled.border_color = Color(0.3, 0.3, 0.35)
	th.set_stylebox("normal", "Button", normal)
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", pressed)
	th.set_stylebox("disabled", "Button", disabled)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(0.9, 0.98, 1.0))
	th.set_color("font_disabled_color", "Button", Color(0.5, 0.55, 0.6))
	th.set_font_size("font_size", "Button", 24)
	th.set_color("font_color", "Label", Color(0.88, 0.96, 1.0))
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	th.set_constant("outline_size", "Label", 4)
	return th

func _label(text: String, size := 24, color := Color(0.88, 0.96, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, cb: Callable, min_h := 72) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.pressed.connect(cb)
	return b

# ---------------------------------------------------------------- верхняя панель

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 12
	panel.offset_right = -12
	panel.offset_top = 12
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	var row := HBoxContainer.new()
	vb.add_child(row)
	pearls_label = _label("", 28, Defs.RESOURCES.pearls.color)
	pearls_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pearls_label)
	pop_label = _label("", 26)
	row.add_child(pop_label)
	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 10)
	vb.add_child(bars)
	for k in ["energy", "oxygen", "food"]:
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(0, 40)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.draw.connect(_draw_res_bar.bind(bar, k))
		bars.add_child(bar)
		res_bars[k] = bar

func _draw_res_bar(bar: Control, k: String) -> void:
	var col: Color = Defs.RESOURCES[k].color
	var r := Rect2(Vector2.ZERO, bar.size)
	var frac: float = Game.resources[k] / Game.storage_cap()
	var low := frac < 0.2
	var bg := _box(Color(0, 0, 0, 0.45), Color(col, 0.6), 12, 2)
	bg.shadow_size = 0
	bar.draw_style_box(bg, r)
	var fill := _box(col.darkened(0.25), Color(0, 0, 0, 0), 10, 0)
	fill.shadow_size = 0
	var fw := maxf(20.0, (r.size.x - 6) * frac)
	var fr := Rect2(Vector2(3, 3), Vector2(fw, r.size.y - 6))
	if frac > 0.0:
		bar.draw_style_box(fill, fr)
		bar.draw_rect(Rect2(fr.position + Vector2(6, 2), Vector2(fr.size.x - 12, 5)), Color(1, 1, 1, 0.25))
	var font := ThemeDB.fallback_font
	var ic := Vector2(22, r.size.y / 2.0)
	bar.draw_circle(ic, 15, Color(0.02, 0.06, 0.1, 0.85))
	Icons.draw(bar, k, ic, 10.0, col.lightened(0.2))
	var txt := "%d" % int(Game.resources[k])
	var tc := Color(1, 0.4, 0.4) if low and int(Time.get_ticks_msec() / 400) % 2 == 0 else Color(1, 1, 1)
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	var tp := Vector2(22 + (r.size.x - 22 - ts.x) / 2.0, r.size.y / 2.0 + 8)
	bar.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 5, Color(0, 0, 0, 0.8))
	bar.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, tc)

func _refresh_top() -> void:
	pearls_label.text = tr("◉ %d pearls") % Game.pearls
	pop_label.text = tr("Colonists %d/%d") % [Game.colonists.size(), Game.population_cap()]
	for k in res_bars:
		res_bars[k].queue_redraw()

# ---------------------------------------------------------------- нижняя панель

func _build_bottom_bar() -> void:
	bottom_bar = HBoxContainer.new()
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_left = 12
	bottom_bar.offset_right = -12
	bottom_bar.offset_top = -100
	bottom_bar.offset_bottom = -16
	bottom_bar.add_theme_constant_override("separation", 10)
	root.add_child(bottom_bar)
	for item in [["Build", _open_build], ["Colonists", _open_colonists], ["Collect all", _collect_all]]:
		var b := _button(item[0], item[1], 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 26)
		bottom_bar.add_child(b)

func _collect_all() -> void:
	var n := Game.collect_all()
	show_toast(tr("Collected from %d rooms") % n if n > 0 else tr("Nothing to collect yet"))

# ---------------------------------------------------------------- выдвижная панель

func _build_sheet() -> void:
	sheet = PanelContainer.new()
	sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_left = 8
	sheet.offset_right = -8
	sheet.offset_bottom = -8
	sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sheet.visible = false
	root.add_child(sheet)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 560)
	sheet.add_child(scroll)
	sheet_body = VBoxContainer.new()
	sheet_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_body.add_theme_constant_override("separation", 10)
	scroll.add_child(sheet_body)

func _open_sheet(kind: String, height := 560) -> void:
	sheet_kind = kind
	for ch in sheet_body.get_children():
		ch.queue_free()
	(sheet.get_child(0) as Control).custom_minimum_size.y = height
	sheet.visible = true
	bottom_bar.visible = false
	sheet.pivot_offset = Vector2(sheet.size.x / 2.0, sheet.size.y)
	sheet.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(sheet, "modulate:a", 1.0, 0.15)

func _close_sheet() -> void:
	sheet.visible = false
	sheet_kind = ""
	sheet_room = -1
	bottom_bar.visible = true
	view.selected_room = -1

func _header(title: String) -> void:
	var row := HBoxContainer.new()
	var l := _label(title, 32, ACCENT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var close := _button("✕", _close_sheet, 60)
	close.custom_minimum_size.x = 60
	row.add_child(close)
	sheet_body.add_child(row)

# ---------------------------------------------------------------- строительство

func _open_build() -> void:
	_open_sheet("build", 620)
	_header(tr("Build"))
	for type in Defs.ROOMS:
		var def: Dictionary = Defs.ROOMS[type]
		if not def.buildable:
			continue
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _box(Color(def.color.darkened(0.75), 0.9), Color(def.color, 0.6), 14))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		card.add_child(hb)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(64, 64)
		icon.draw.connect(func():
			icon.draw_circle(Vector2(32, 32), 30, Color(def.color, 0.25))
			icon.draw_arc(Vector2(32, 32), 30, 0, TAU, 32, def.color, 3.0)
			var f := ThemeDB.fallback_font
			var s := f.get_string_size(def.icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 34)
			icon.draw_string(f, Vector2(32 - s.x / 2, 44), def.icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, def.color))
		hb.add_child(icon)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label(def.name, 26))
		var d := _label(def.desc, 18, Color(0.7, 0.8, 0.9))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(d)
		hb.add_child(info)
		var cost := Game.build_cost(type)
		var b: Button
		if Game.is_unlocked(type):
			b = _button("◉ %d" % cost, _start_build.bind(type), 64)
			b.disabled = Game.pearls < cost
		else:
			b = _button(tr("Needs %d colonists") % def.unlock_pop, func(): pass, 64)
			b.disabled = true
		b.custom_minimum_size.x = 150
		hb.add_child(b)
		sheet_body.add_child(card)

func _start_build(type: String) -> void:
	_close_sheet()
	view.build_type = type
	build_hint_label.text = tr("Where to place %s?") % tr(Defs.ROOMS[type].name)
	build_hint.visible = true
	bottom_bar.visible = false

func _build_build_hint() -> void:
	build_hint = PanelContainer.new()
	build_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	build_hint.offset_left = 12
	build_hint.offset_right = -12
	build_hint.offset_top = -120
	build_hint.offset_bottom = -16
	build_hint.visible = false
	root.add_child(build_hint)
	var hb := HBoxContainer.new()
	build_hint.add_child(hb)
	build_hint_label = _label("", 24)
	build_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hb.add_child(build_hint_label)
	var cancel := _button("Cancel", _cancel_build, 64)
	cancel.custom_minimum_size.x = 150
	hb.add_child(cancel)

func _cancel_build() -> void:
	view.build_type = ""
	_on_build_finished()

func _on_build_finished() -> void:
	build_hint.visible = false
	bottom_bar.visible = true

# ---------------------------------------------------------------- карточка отсека

var room_live_labels := {}

func _on_room_selected(id: int) -> void:
	if id == -1:
		if sheet_kind == "room":
			_close_sheet()
		return
	_open_room(id)

func _open_room(id: int) -> void:
	var r := Game.get_room(id)
	if r.is_empty():
		return
	sheet_room = id
	view.selected_room = id
	var def: Dictionary = Defs.ROOMS[r.type]
	_open_sheet("room", 470)
	_header(tr("%s · lvl %d") % [tr(def.name), r.level])
	var d := _label(def.desc, 20, Color(0.7, 0.82, 0.92))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sheet_body.add_child(d)
	room_live_labels = {}
	if def.has("produces"):
		var st := _label("", 22)
		sheet_body.add_child(st)
		room_live_labels["status"] = st
	var slots := Defs.room_slots(r.type, r.level)
	if slots > 0:
		var stat_name: String = Defs.STATS[def.stat]
		sheet_body.add_child(_label(tr("Workers (%d/%d) · needs %s") % [Game.workers_in(r).size(), slots, tr(stat_name)], 22, ACCENT))
		for c in Game.workers_in(r):
			var row := HBoxContainer.new()
			var l := _label("%s  ·  %s %d  ·  ♥ %d" % [c.name, tr(stat_name), c[def.stat], int(c.health)], 21)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var out := _button("Remove", func():
				Game.assign(c, {})
				_open_room(id), 56)
			out.custom_minimum_size.x = 120
			row.add_child(out)
			sheet_body.add_child(row)
		if Game.workers_in(r).size() < slots:
			sheet_body.add_child(_button("+ Assign colonist", _open_pick.bind(id), 64))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	if r.level < Defs.MAX_LEVEL:
		var cost := Defs.upgrade_cost(r.type, r.level)
		var up := _button(tr("Upgrade ◉%d") % cost, func():
			Game.upgrade(r)
			_open_room(id), 72)
		up.disabled = Game.pearls < cost
		up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(up)
	if def.has("produces"):
		var rush := _button("", func():
			Game.rush(r)
			_open_room(id), 72)
		rush.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(rush)
		room_live_labels["rush"] = rush
	if actions.get_child_count() > 0:
		sheet_body.add_child(actions)
	_refresh_room_live()

func _refresh_room_live() -> void:
	var r := Game.get_room(sheet_room)
	if r.is_empty():
		return
	var def: Dictionary = Defs.ROOMS[r.type]
	if room_live_labels.has("status"):
		var res: String = def.produces
		var txt := ""
		if r.incident > 0.0:
			txt = tr("Hull breach! Repairs: %ds") % ceili(r.incident)
		elif r.ready:
			txt = tr("Ready: +%d %s. Tap the room!") % [int(Game.production_amount(r)), tr(Defs.RESOURCES[res].name).to_lower()]
		else:
			var ct := Game.cycle_time(r)
			if ct == INF:
				txt = tr("No workers, production stopped")
			else:
				txt = tr("Cycle: %d%% · %ds left · +%d per cycle") % [int(r.progress * 100), ceili((1.0 - r.progress) * ct), int(Game.production_amount(r))]
		room_live_labels.status.text = txt
	if room_live_labels.has("rush"):
		var b: Button = room_live_labels.rush
		b.text = tr("Rush (%d%%)") % int(Game.rush_chance(r) * 100)
		b.disabled = r.ready or r.incident > 0.0 or Game.workers_in(r).is_empty()

# ---------------------------------------------------------------- выбор колониста

func _open_pick(room_id: int) -> void:
	var r := Game.get_room(room_id)
	var def: Dictionary = Defs.ROOMS[r.type]
	var stat: String = def.stat
	_open_sheet("pick", 560)
	_header(tr("Who should work here?"))
	var list := Game.colonists.duplicate()
	list.sort_custom(func(a, b): return a[stat] > b[stat])
	for c in list:
		if c.room == room_id:
			continue
		var where: String = tr("idle") if c.room == -1 else tr(Defs.ROOMS[Game.get_room(c.room).type].name)
		var b := _button("%s: %s %d (%s)" % [c.name, tr(Defs.STATS[stat]), c[stat], where], func():
			if Game.assign(c, r):
				_open_room(room_id), 64)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		sheet_body.add_child(b)

# ---------------------------------------------------------------- колонисты

func _open_colonists() -> void:
	_open_sheet("colonists", 640)
	_header(tr("Colonists (%d/%d)") % [Game.colonists.size(), Game.population_cap()])
	sheet_body.add_child(_label("Drag a colonist into a room to assign them", 19, Color(0.7, 0.82, 0.92)))
	for c in Game.colonists:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _box(Color(0.06, 0.16, 0.24, 0.9), Color(ACCENT, 0.3), 14))
		var vb := VBoxContainer.new()
		card.add_child(vb)
		var top := HBoxContainer.new()
		var n := _label(tr("%s · lvl %d") % [c.name, c.level], 24)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(n)
		top.add_child(_label("♥ %d" % int(c.health), 22, Color(1.0, 0.5, 0.5)))
		vb.add_child(top)
		var where: String = tr("Idle (in airlock)") if c.room == -1 else tr(Defs.ROOMS[Game.get_room(c.room).type].name)
		vb.add_child(_label(tr("Strength %d · Tech %d · Biology %d · %s") % [c.str, c.tech, c.bio, where], 19, Color(0.75, 0.85, 0.95)))
		var xp := ProgressBar.new()
		xp.show_percentage = false
		xp.custom_minimum_size = Vector2(0, 8)
		xp.max_value = 90.0 * c.level
		xp.value = c.xp
		vb.add_child(xp)
		sheet_body.add_child(card)
	var reset := _button("Start over", func():
		Game.reset()
		_close_sheet(), 56)
	reset.modulate = Color(1, 0.7, 0.7)
	sheet_body.add_child(reset)

# ---------------------------------------------------------------- сообщения

func _build_toast() -> void:
	toast = _label("", 24)
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.offset_top = 150
	toast.offset_left = -330
	toast.offset_right = 330
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.add_theme_constant_override("outline_size", 8)
	toast.modulate.a = 0.0
	root.add_child(toast)

func show_toast(text: String) -> void:
	toast.text = text
	toast_time = 3.0

func _on_changed() -> void:
	_refresh_top()
	if sheet_kind == "room" and sheet_room != -1:
		pass

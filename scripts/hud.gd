extends CanvasLayer
## Интерфейс: ресурсы, строительство, карточка отсека, список колонистов, сообщения.

const ACCENT := Color(0.35, 0.92, 1.0)
const PANEL_BG := Color(0.03, 0.09, 0.16, 0.92)

var view: Node2D
var root: Control
var theme_res: Theme
var res_bars := {}
var pearls_label: Label
var crystals_label: Label
var boost_label: Label
var shop_badge: Control
var popup: PanelContainer
var popup_bg: ColorRect
var ad_overlay: ColorRect
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
	Game.rewards_granted.connect(_show_rewards)
	Store.ad_started.connect(_on_ad_started)
	Store.ad_finished.connect(func(): ad_overlay.visible = false)
	_build_popup()
	_build_ad_overlay()
	_refresh_top()
	if Game.daily_available():
		get_tree().create_timer(1.2).timeout.connect(_open_daily)

func _process(delta: float) -> void:
	refresh_timer += delta
	if refresh_timer > 0.2:
		refresh_timer = 0.0
		_refresh_top()
		if sheet_kind == "room":
			_refresh_room_live()
		elif sheet_kind == "shop":
			_refresh_shop_live()
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

func _icon(res: String, size := 32, col := Color.WHITE) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tint: Color = Defs.RESOURCES[res].color if Defs.RESOURCES.has(res) and col == Color.WHITE else col
	c.draw.connect(func(): Icons.draw(c, res, c.size / 2.0, size * 0.4, tint))
	return c

static func _clock(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]

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
	row.add_theme_constant_override("separation", 6)
	row.add_child(_icon("pearls", 30))
	pearls_label = _label("", 26, Defs.RESOURCES.pearls.color)
	row.add_child(pearls_label)
	var gap := Control.new()
	gap.custom_minimum_size.x = 14
	row.add_child(gap)
	row.add_child(_icon("crystals", 30))
	crystals_label = _label("", 26, Defs.RESOURCES.crystals.color)
	row.add_child(crystals_label)
	boost_label = _label("", 20, Color(1.0, 0.85, 0.3))
	boost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(boost_label)
	row.add_child(_icon("people", 26, Color(0.85, 0.95, 1.0)))
	pop_label = _label("", 24)
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
	pearls_label.text = str(Game.pearls)
	crystals_label.text = str(Game.crystals)
	pop_label.text = "%d/%d" % [Game.colonists.size(), Game.population_cap()]
	boost_label.text = tr("x2 %s") % _clock(Game.boost_left()) if Game.boost_active() else ""
	if shop_badge:
		shop_badge.visible = Game.daily_available() or Game.free_crate_ready()
		shop_badge.queue_redraw()
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
	for item in [["Build", _open_build], ["Colonists", _open_colonists], ["Shop", _open_shop], ["Collect", _collect_all]]:
		var b := _button(item[0], item[1], 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 23)
		bottom_bar.add_child(b)
		if item[0] == "Shop":
			b.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
			shop_badge = Control.new()
			shop_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			shop_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			shop_badge.position = Vector2(-18, 4)
			shop_badge.draw.connect(func():
				var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 150.0)
				shop_badge.draw_circle(Vector2.ZERO, 11 * pulse, Color(1.0, 0.25, 0.3))
				shop_badge.draw_arc(Vector2.ZERO, 11 * pulse, 0, TAU, 20, Color.WHITE, 2.0))
			b.add_child(shop_badge)

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
		var safe := _button("", func():
			Game.rush_safe(r)
			_open_room(id), 72)
		safe.add_theme_color_override("font_color", Defs.RESOURCES.crystals.color)
		room_live_labels["safe"] = safe
	if actions.get_child_count() > 0:
		sheet_body.add_child(actions)
	if room_live_labels.has("safe"):
		sheet_body.add_child(room_live_labels.safe)
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
	if room_live_labels.has("safe"):
		var sb: Button = room_live_labels.safe
		var cost := Game.safe_rush_cost(r)
		sb.text = tr("Finish now, no risk: ◆ %d") % maxi(cost, 0)
		sb.disabled = cost < 0 or r.ready or r.incident > 0.0

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

# ---------------------------------------------------------------- магазин

var shop_live := {}

func _section(title: String) -> void:
	var l := _label(title, 26, Color(1.0, 0.88, 0.5))
	l.add_theme_constant_override("outline_size", 6)
	sheet_body.add_child(l)

func _card(bg: Color, border: Color) -> HBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _box(bg, border, 16))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	card.add_child(hb)
	sheet_body.add_child(card)
	return hb

func _banner(key: String) -> Control:
	var tex := Art.tex("res://art/ui/shop/%s.png" % key)
	if tex == null:
		return null
	var tr_ := TextureRect.new()
	tr_.texture = tex
	tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr_.custom_minimum_size = Vector2(0, 220)
	return tr_

func _open_shop() -> void:
	_open_sheet("shop", 900)
	shop_live = {}
	_header(tr("Shop"))
	var wallet := HBoxContainer.new()
	wallet.add_child(_icon("pearls", 28))
	wallet.add_child(_label(str(Game.pearls), 22, Defs.RESOURCES.pearls.color))
	wallet.add_child(_icon("crystals", 28))
	wallet.add_child(_label(str(Game.crystals), 22, Defs.RESOURCES.crystals.color))
	sheet_body.add_child(wallet)

	_section(tr("Free"))
	var daily := _card(Color(0.2, 0.12, 0.05, 0.9), Color(1.0, 0.75, 0.3, 0.8))
	var dinfo := VBoxContainer.new()
	dinfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dinfo.add_child(_label(tr("Daily reward"), 24))
	dinfo.add_child(_label(tr("Day %d: %s") % [Game.daily_next_index() + 1, _reward_text(Defs.DAILY[Game.daily_next_index()])], 18, Color(0.9, 0.85, 0.7)))
	daily.add_child(dinfo)
	var db := _button(tr("Claim") if Game.daily_available() else tr("Tomorrow"), func():
		Game.claim_daily()
		_open_shop(), 64)
	db.disabled = not Game.daily_available()
	db.custom_minimum_size.x = 170
	daily.add_child(db)

	var free := _card(Color(0.05, 0.14, 0.22, 0.9), Color(0.5, 0.8, 1.0, 0.7))
	free.add_child(_crate_icon("common", 64))
	var finfo := VBoxContainer.new()
	finfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	finfo.add_child(_label(tr("Free Supply Crate"), 24))
	finfo.add_child(_label(tr("Watch a short video") if not Game.premium else tr("Premium: no ads needed"), 18, Color(0.75, 0.85, 0.95)))
	free.add_child(finfo)
	var fb := _button("", func(): Store.show_rewarded(func():
		Game.claim_free_crate()
		_open_shop()), 64)
	fb.custom_minimum_size.x = 170
	free.add_child(fb)
	shop_live["free"] = fb

	var boost := _card(Color(0.18, 0.15, 0.03, 0.9), Color(1.0, 0.85, 0.3, 0.7))
	var binfo := VBoxContainer.new()
	binfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	binfo.add_child(_label(tr("Double collection"), 24))
	binfo.add_child(_label(tr("x2 resources from rooms for 30 min"), 18, Color(0.9, 0.85, 0.7)))
	boost.add_child(binfo)
	var bb := _button(tr("▶ Watch"), func(): Store.show_rewarded(func():
		Game.start_boost()
		_open_shop()), 64)
	bb.custom_minimum_size.x = 170
	boost.add_child(bb)

	_section(tr("Your crates"))
	var any := false
	for type in Defs.CRATES:
		if Game.crates[type] <= 0:
			continue
		any = true
		var row := _card(Color(Defs.CRATES[type].color.darkened(0.8), 0.9), Color(Defs.CRATES[type].color, 0.7))
		row.add_child(_crate_icon(type, 64))
		var l := _label("%s ×%d" % [tr(Defs.CRATES[type].name), Game.crates[type]], 24)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var ob := _button(tr("Open"), func():
			Game.open_crate(type)
			_open_shop(), 64)
		ob.custom_minimum_size.x = 150
		row.add_child(ob)
	if not any:
		sheet_body.add_child(_label(tr("No crates yet. Get one for free above!"), 19, Color(0.7, 0.8, 0.9)))

	for id in ["starter_pack", "premium"]:
		if not Store.can_buy(id):
			continue
		var p := Store.product(id)
		_section(tr("Special offer") if id == "starter_pack" else tr("Premium"))
		var banner := _banner(p.banner)
		if banner:
			sheet_body.add_child(banner)
		var offer := _card(Color(0.25, 0.1, 0.3, 0.92) if id == "starter_pack" else Color(0.25, 0.2, 0.05, 0.92), Color(1.0, 0.8, 0.4, 0.9))
		var oinfo := VBoxContainer.new()
		oinfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		oinfo.add_child(_label(tr(p.title), 26, Color(1.0, 0.9, 0.6)))
		var d := _label(tr(p.desc), 18, Color(0.9, 0.9, 0.95))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		oinfo.add_child(d)
		offer.add_child(oinfo)
		var pb := _button(p.price, func():
			Store.purchase(id)
			_open_shop(), 72)
		pb.custom_minimum_size.x = 150
		offer.add_child(pb)

	_section(tr("Crystals"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sheet_body.add_child(grid)
	for p in Store.IAP:
		if not p.has("pack"):
			continue
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_stylebox_override("panel", _box(Color(0.05, 0.12, 0.25, 0.92), Color(0.55, 0.8, 1.0, 0.6), 14))
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		cell.add_child(vb)
		var art := Art.tex("res://art/ui/shop/crystals_%d.png" % p.pack)
		if art:
			var ti := TextureRect.new()
			ti.texture = art
			ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ti.custom_minimum_size = Vector2(0, 90)
			vb.add_child(ti)
		else:
			var ic := _icon("crystals", 60 + p.pack * 6)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			vb.add_child(ic)
		var amt := _label(str(p.reward.crystals), 24, Defs.RESOURCES.crystals.color)
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(amt)
		vb.add_child(_button(p.price, Store.purchase.bind(p.id), 56))
		grid.add_child(cell)

	_section(tr("Spend crystals"))
	for item in Store.CRYSTAL_ITEMS:
		var row := _card(Color(0.05, 0.12, 0.2, 0.9), Color(0.55, 0.8, 1.0, 0.4))
		if item.reward.has("crates"):
			row.add_child(_crate_icon(item.reward.crates.keys()[0], 56))
		else:
			row.add_child(_icon("pearls", 56))
		var l := _label(tr(item.title), 22)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var cb := _button("◆ %d" % item.cost, func():
			Store.buy_with_crystals(item.id)
			_open_shop(), 60)
		cb.add_theme_color_override("font_color", Defs.RESOURCES.crystals.color)
		cb.disabled = Game.crystals < item.cost
		cb.custom_minimum_size.x = 140
		row.add_child(cb)

	_section(tr("Crate odds"))
	for type in Defs.CRATES:
		var parts := []
		for o in Game.crate_odds(type):
			parts.append("%s %d%%" % [_kind_name(o[0]), roundi(o[1] * 100.0)])
		var l := _label("%s: %s" % [tr(Defs.CRATES[type].name), ", ".join(parts)], 16, Color(0.65, 0.75, 0.85))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sheet_body.add_child(l)
	if Store.DEV_MODE:
		sheet_body.add_child(_label(tr("Test mode: purchases are free and no money is charged."), 16, Color(1.0, 0.6, 0.6)))
	_refresh_shop_live()

func _refresh_shop_live() -> void:
	if shop_live.has("free"):
		var fb: Button = shop_live.free
		if Game.free_crate_ready():
			fb.text = tr("▶ Free") if not Game.premium else tr("Claim")
			fb.disabled = false
		else:
			fb.text = _clock(Game.free_crate_left())
			fb.disabled = true

func _kind_name(kind: String) -> String:
	match kind:
		"pearls": return tr("Pearls")
		"crystals": return tr("Crystals")
		"resources": return tr("Supplies")
		"colonist_rare": return tr("Rare colonist")
		"colonist_legendary": return tr("Legendary colonist")
	return kind

func _reward_text(r: Dictionary) -> String:
	var parts := []
	if r.has("pearls"): parts.append(tr("%d pearls") % r.pearls)
	if r.has("crystals"): parts.append(tr("%d crystals") % r.crystals)
	for k in r.get("crates", {}):
		parts.append(tr(Defs.CRATES[k].name))
	return ", ".join(parts)

func _crate_icon(type: String, size: int) -> Control:
	var tex := Art.tex("res://art/ui/shop/crate_%s.png" % type)
	if tex:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(size, size)
		return t
	var col: Color = Defs.CRATES[type].color
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.draw.connect(func():
		var r := Rect2(Vector2(size * 0.12, size * 0.28), Vector2(size * 0.76, size * 0.6))
		c.draw_rect(r, Color(0.4, 0.28, 0.15))
		c.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.3)), Color(0.5, 0.36, 0.2))
		c.draw_rect(r, col, false, 3.0)
		c.draw_rect(Rect2(r.position + Vector2(r.size.x * 0.42, 0), Vector2(r.size.x * 0.16, r.size.y)), col)
		c.draw_circle(r.get_center() + Vector2(0, -r.size.y * 0.05), size * 0.07, Color(0.5, 1.0, 1.0)))
	return c

# ---------------------------------------------------------------- ежедневная награда

func _open_daily() -> void:
	if sheet.visible or not Game.daily_available():
		return
	_open_sheet("daily", 470)
	_header(tr("Daily reward"))
	sheet_body.add_child(_label(tr("Come back every day for bigger rewards!"), 19, Color(0.8, 0.88, 0.95)))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sheet_body.add_child(grid)
	var next := Game.daily_next_index()
	for i in Defs.DAILY.size():
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var border := Color(1.0, 0.8, 0.3) if i == next else Color(0.5, 0.7, 0.9, 0.4)
		var bg := Color(0.25, 0.18, 0.05, 0.95) if i == next else (Color(0.05, 0.2, 0.1, 0.9) if i < next else Color(0.05, 0.1, 0.18, 0.9))
		cell.add_theme_stylebox_override("panel", _box(bg, border, 12, 3 if i == next else 2))
		var vb := VBoxContainer.new()
		cell.add_child(vb)
		var t := _label(tr("Day %d") % (i + 1), 18, Color(1.0, 0.9, 0.6) if i == next else Color(0.8, 0.85, 0.9))
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(t)
		var rw := _label(("✓ " if i < next else "") + _reward_text(Defs.DAILY[i]), 15)
		rw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(rw)
		grid.add_child(cell)
	sheet_body.add_child(_button(tr("Claim"), func():
		Game.claim_daily()
		_close_sheet(), 72))

# ---------------------------------------------------------------- окно наград и реклама

func _build_popup() -> void:
	popup = PanelContainer.new()
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.custom_minimum_size = Vector2(560, 0)
	popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	popup.add_theme_stylebox_override("panel", _box(Color(0.04, 0.1, 0.18, 0.97), Color(1.0, 0.85, 0.4), 22, 3))
	popup_bg = ColorRect.new()
	popup_bg.color = Color(0, 0, 0, 0.55)
	popup_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	popup_bg.visible = false
	root.add_child(popup_bg)
	popup_bg.add_child(popup)

func _show_rewards(title: String, lines: Array) -> void:
	for ch in popup.get_children():
		ch.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	popup.add_child(vb)
	var is_crate := false
	for k in Defs.CRATES:
		if title == tr(Defs.CRATES[k].name):
			is_crate = true
	var open_tex := Art.tex("res://art/ui/shop/crate_open.png")
	if is_crate and open_tex:
		var img := TextureRect.new()
		img.texture = open_tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = Vector2(0, 220)
		vb.add_child(img)
	var t := _label(title, 32, Color(1.0, 0.88, 0.5))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	for line in lines:
		var l := _label(line, 24)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(l)
	vb.add_child(_button(tr("Great!"), func(): popup_bg.visible = false, 68))
	popup_bg.visible = true
	popup.scale = Vector2(0.6, 0.6)
	popup.pivot_offset = popup.size / 2.0
	var tw := create_tween()
	tw.tween_property(popup, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _build_ad_overlay() -> void:
	ad_overlay = ColorRect.new()
	ad_overlay.color = Color(0, 0, 0, 0.85)
	ad_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ad_overlay.visible = false
	root.add_child(ad_overlay)
	var l := _label(tr("Ad playing… (test mode)"), 30)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ad_overlay.add_child(l)

func _on_ad_started() -> void:
	ad_overlay.visible = true

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
var science_label: Label
var mode_label: Label
var science_icon: Control
var more: Node
var boost_label: Label
var shop_badge: Control
var tasks_badge: Control
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
	Game.banner.connect(show_banner)
	Game.lost.connect(_on_colony_lost)
	view.room_selected.connect(_on_room_selected)
	view.build_finished.connect(_on_build_finished)
	view.colonist_selected.connect(_open_colonist)
	Game.rewards_granted.connect(_show_rewards)
	Game.combo_changed.connect(_on_combo)
	Game.collected.connect(_on_collected)
	Store.ad_started.connect(_on_ad_started)
	Store.ad_finished.connect(func(): ad_overlay.visible = false)
	more = preload("res://scripts/hud_more.gd").new()
	more.hud = self
	add_child(more)
	view.trader_tapped.connect(func(): more.open_trader())
	view.outside_tapped.connect(open_outside)
	view.fallen_tapped.connect(func(i): open_fallen(i))
	_build_expedition_button()
	_build_popup()
	_build_ad_overlay()
	_refresh_top()
	apply_safe_area()
	get_viewport().size_changed.connect(apply_safe_area)
	if Game.colony_lost:
		_on_colony_lost.call_deferred()
	elif not Game.mode_chosen:
		open_mode_picker.call_deferred()
	elif not Game.tutorial_done:
		start_tutorial.call_deferred()
	elif Game.daily_available():
		get_tree().create_timer(1.2).timeout.connect(_open_daily)

var tutorial: CanvasLayer

## Выбор сложности при новой игре.
func open_mode_picker() -> void:
	_open_sheet("mode", 520)
	var title := _label(tr("Choose your challenge"), 32, Color(1.0, 0.86, 0.35))
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.0, 0.9))
	sheet_body.add_child(title)
	var hint := _label(tr("You can only change it by starting over."), 18, Color(0.75, 0.85, 0.95))
	sheet_body.add_child(hint)
	for key in ["calm", "normal", "survival"]:
		var d: Dictionary = Defs.DIFFICULTY[key]
		var row := _card(Color(d.color.darkened(0.8), 0.95), Color(d.color, 0.9))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_l := _label(tr(d.name) + ("  · " + tr("Recommended") if key == "normal" else ""), 26, d.color)
		info.add_child(name_l)
		var dl := _label(tr(d.desc), 17, Color(0.88, 0.92, 0.98))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(dl)
		row.add_child(info)
		var b := _button(tr("Select"), func():
			Game.set_difficulty(key)
			_close_sheet()
			if not Game.tutorial_done:
				start_tutorial(), 64)
		b.custom_minimum_size.x = 140
		var st := button_styles(d.color.darkened(0.2), d.color.lightened(0.3), d.color.darkened(0.6))
		for k in st:
			b.add_theme_stylebox_override(k, st[k])
		row.add_child(b)

## Отступы от выреза камеры, скруглённых углов и системных панелей (например, Samsung S25).
var safe_top := 0.0

var landscape := false
const SHEET_W_LANDSCAPE := 700.0

func apply_safe_area() -> void:
	var win := DisplayServer.window_get_size()
	if win.x <= 0:
		return
	_apply_orientation(win.x > win.y)
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0:
		return
	var vp := get_viewport().get_visible_rect().size
	var k := vp.y / float(win.y)
	var top := maxf(0.0, safe.position.y) * k
	var bottom := maxf(0.0, float(win.y) - float(safe.end.y)) * k
	# в горизонтальном положении вырез камеры сбоку
	var left := maxf(0.0, safe.position.x) * k
	var right := maxf(0.0, float(win.x) - float(safe.end.x)) * k
	safe_top = top
	root.offset_top = top
	root.offset_bottom = -bottom
	root.offset_left = left
	root.offset_right = -right

## Телефон повернули: меняем логический размер экрана и раскладку панелей.
## Вертикально — 720×1280, меню снизу; горизонтально — 1280×720, меню справа.
func _apply_orientation(land: bool) -> void:
	if land == landscape and top_panel.has_meta("oriented"):
		return
	top_panel.set_meta("oriented", true)
	landscape = land
	get_tree().root.content_scale_size = Vector2i(1280, 720) if land else Vector2i(720, 1280)
	if land:
		sheet.anchor_left = 1.0
		sheet.anchor_right = 1.0
		sheet.anchor_top = 0.0
		sheet.anchor_bottom = 1.0
		sheet.offset_left = -SHEET_W_LANDSCAPE
		sheet.offset_right = -12
		sheet.offset_top = 12
		sheet.offset_bottom = -12
		# верхняя панель — только слева, чтобы не растягиваться на весь широкий экран
		var win := DisplayServer.window_get_size()
		var vp_w := maxf(1280.0, 720.0 * win.x / maxf(1.0, win.y))
		top_panel.anchor_right = 0.0
		top_panel.offset_right = 12 + minf(700.0, vp_w - SHEET_W_LANDSCAPE - 48.0)
	else:
		sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		sheet.offset_left = 12
		sheet.offset_right = -12
		sheet.offset_top = 0
		sheet.offset_bottom = -12
		top_panel.anchor_right = 1.0
		top_panel.offset_right = -12
	if sheet.visible:
		var scroll := sheet.get_child(0) as ScrollContainer
		scroll.custom_minimum_size.y = _sheet_height(int(scroll.get_meta("want", 560)))

## Высота прокручиваемой части меню: горизонтально — на всю высоту экрана.
func _sheet_height(want: int) -> int:
	if not landscape:
		return want
	var vp := get_viewport().get_visible_rect().size
	return int(vp.y - safe_top - 24 - 36)

func start_tutorial() -> void:
	if tutorial and is_instance_valid(tutorial):
		return
	tutorial = preload("res://scripts/tutorial.gd").new()
	tutorial.hud = self
	tutorial.view = view
	get_parent().add_child(tutorial)

func _process(delta: float) -> void:
	refresh_timer += delta
	if refresh_timer > 0.2:
		refresh_timer = 0.0
		_refresh_top()
		# поворот телефона: не на всех устройствах приходит size_changed, поэтому проверяем сами
		var win := DisplayServer.window_get_size()
		if win.x > 0 and (win.x > win.y) != landscape:
			apply_safe_area()
		if sheet_kind == "room":
			_refresh_room_live()
		elif sheet_kind == "shop":
			_refresh_shop_live()
		elif sheet_kind == "room" or sheet_kind == "dock":
			pass
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

## Объёмная «игровая» кнопка: светлая кромка, тёмный низ, при нажатии «проседает».
static func button_styles(bg: Color, rim: Color, base: Color) -> Dictionary:
	var n := StyleBoxFlat.new()
	n.bg_color = bg
	n.border_color = base
	n.border_width_left = 2
	n.border_width_right = 2
	n.border_width_top = 2
	n.border_width_bottom = 7
	n.set_corner_radius_all(16)
	n.content_margin_left = 14
	n.content_margin_right = 14
	n.content_margin_top = 8
	n.content_margin_bottom = 12
	n.shadow_color = Color(0, 0, 0, 0.35)
	n.shadow_size = 4
	n.shadow_offset = Vector2(0, 3)
	var h := n.duplicate()
	h.bg_color = bg.lightened(0.12)
	var p := n.duplicate()
	p.bg_color = bg.darkened(0.1)
	p.border_width_bottom = 2
	p.content_margin_top = 13
	p.content_margin_bottom = 7
	p.shadow_size = 1
	var d := n.duplicate()
	d.bg_color = Color(0.16, 0.2, 0.26)
	d.border_color = Color(0.08, 0.1, 0.13)
	d.shadow_size = 0
	# светлый блик сверху — через вторую рамку не выйдет, поэтому светлая верхняя кромка
	for sb in [n, h]:
		sb.border_blend = false
	n.expand_margin_top = 0
	return {"normal": n, "hover": h, "pressed": p, "disabled": d}

const GOLD_KEYS := ["Claim", "Collect loot!", "Launch the bathyscaphe!", "Open", "Deal", "Great!", "Next",
	"+ Assign colonist", "Plan an expedition", "Assign to best room"]

## Главные действия — золотые, покупки за деньги — зелёные.
func _auto_style(b: Button, text: String) -> void:
	for k in GOLD_KEYS:
		if text == tr(k):
			_gold(b)
			return
	var up := tr("Upgrade ◉%d").split("◉")[0]
	if text.begins_with("$") or text.begins_with("⚗") or (up != "" and text.begins_with(up)):
		_green(b) if text.begins_with("$") else _gold(b)

## Золотая кнопка для главных действий.
func _gold(b: Button) -> Button:
	var st := button_styles(Color(1.0, 0.72, 0.16), Color(1.0, 0.92, 0.5), Color(0.62, 0.33, 0.04))
	for k in st:
		b.add_theme_stylebox_override(k, st[k])
	b.add_theme_color_override("font_color", Color(0.3, 0.12, 0.0))
	b.add_theme_color_override("font_hover_color", Color(0.3, 0.12, 0.0))
	b.add_theme_color_override("font_pressed_color", Color(0.3, 0.12, 0.0))
	b.add_theme_color_override("font_outline_color", Color(1.0, 0.95, 0.7, 0.6))
	b.add_theme_constant_override("outline_size", 2)
	return b

## Зелёная кнопка для «купить за реальные деньги».
func _green(b: Button) -> Button:
	var st := button_styles(Color(0.2, 0.75, 0.35), Color(0.6, 1.0, 0.6), Color(0.05, 0.35, 0.12))
	for k in st:
		b.add_theme_stylebox_override(k, st[k])
	return b

func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 24
	th.set_stylebox("panel", "PanelContainer", _box(PANEL_BG, Color(ACCENT, 0.45)))
	var btn := button_styles(Color(0.08, 0.5, 0.72), Color(0.45, 0.9, 1.0), Color(0.03, 0.22, 0.36))
	for k in btn:
		th.set_stylebox(k, "Button", btn[k])
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", Color(1, 1, 1))
	th.set_color("font_hover_color", "Button", Color(1, 1, 1))
	th.set_color("font_pressed_color", "Button", Color(0.9, 0.97, 1.0))
	th.set_color("font_outline_color", "Button", Color(0.02, 0.12, 0.2, 0.9))
	th.set_constant("outline_size", "Button", 5)
	th.set_stylebox("panel", "PanelContainer", _box(PANEL_BG, Color(0.35, 0.85, 1.0, 0.8), 20, 3))
	th.set_color("font_disabled_color", "Button", Color(0.5, 0.55, 0.6))
	th.set_font_size("font_size", "Button", 24)
	th.set_color("font_color", "Label", Color(0.88, 0.96, 1.0))
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.6))
	th.set_constant("outline_size", "Label", 4)
	var pb_bg := _box(Color(0, 0, 0, 0.5), Color(ACCENT, 0.3), 8, 1)
	pb_bg.shadow_size = 0
	pb_bg.set_content_margin_all(0)
	var pb_fill := _box(Color(1.0, 0.78, 0.3), Color(0, 0, 0, 0), 8, 0)
	pb_fill.shadow_size = 0
	pb_fill.set_content_margin_all(0)
	th.set_stylebox("background", "ProgressBar", pb_bg)
	th.set_stylebox("fill", "ProgressBar", pb_fill)
	return th

func _label(text: String, size := 24, color := Color(0.88, 0.96, 1.0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _with_icon(b: Button, name: String, size := 40) -> Button:
	var tex := Art.tex("res://art/ui/icons/%s.png" % name)
	if tex:
		b.icon = tex
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", size)
	return b

func _badge() -> Control:
	var bd := Control.new()
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bd.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bd.position = Vector2(-16, 4)
	bd.draw.connect(func():
		var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() / 150.0)
		bd.draw_circle(Vector2.ZERO, 11 * pulse, Color(1.0, 0.25, 0.3))
		bd.draw_arc(Vector2.ZERO, 11 * pulse, 0, TAU, 20, Color.WHITE, 2.0))
	return bd

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
	b.pressed.connect(func(): Audio.play("tap"))
	b.pressed.connect(cb)
	_auto_style(b, text)
	set_cost_text(b, text)
	return b

## Значки валют в тексте кнопки заменяем настоящими иконками: ◉ жемчуг, ◆ кристаллы, ⚗ наука.
const CURRENCY_GLYPHS := {"◉": "res://art/icons/pearls.png", "◆": "res://art/icons/crystals.png", "⚗": "res://art/icons/science.png"}

## Надпись в кнопке с ценой берёт шрифт и цвета самой кнопки (когда она уже в дереве и видит тему).
func _style_cost_label(b: Button) -> void:
	if not b.has_meta("cost_box"):
		return
	var lab := (b.get_meta("cost_box") as HBoxContainer).get_child(0) as Label
	var fs := b.get_theme_font_size("font_size") if b.is_inside_tree() or b.has_theme_font_size_override("font_size") else 22
	lab.add_theme_font_size_override("font_size", fs)
	var fc := Color.WHITE
	if b.is_inside_tree() or b.has_theme_color_override("font_color"):
		fc = b.get_theme_color("font_disabled_color") if b.disabled else b.get_theme_color("font_color")
	lab.add_theme_color_override("font_color", fc)
	lab.add_theme_color_override("font_outline_color", Color(0.02, 0.12, 0.2, 0.9) if fc.get_luminance() > 0.5 else Color(1, 0.95, 0.7, 0.5))
	lab.add_theme_constant_override("outline_size", 4)

func set_cost_text(b: Button, text: String) -> void:
	var glyph := ""
	for g in CURRENCY_GLYPHS:
		if g in text:
			glyph = g
			break
	var box: HBoxContainer = b.get_meta("cost_box") if b.has_meta("cost_box") else null
	if glyph == "" or Art.tex(CURRENCY_GLYPHS[glyph]) == null:
		if box:
			box.queue_free()
			b.remove_meta("cost_box")
		b.text = text
		return
	# «Улучшить 60 [иконка]»: текст и число, затем картинка валюты
	var clean := text.replace(glyph + " ", "").replace(glyph, "").strip_edges()
	b.text = ""
	if box == null:
		box = HBoxContainer.new()
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 6)
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_bottom = -4
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(l)
		var ic := TextureRect.new()
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(30, 30)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(ic)
		b.add_child(box)
		b.set_meta("cost_box", box)
	var lab := box.get_child(0) as Label
	lab.text = clean
	_style_cost_label(b)
	if not b.is_inside_tree() and not b.tree_entered.is_connected(_style_cost_label):
		b.tree_entered.connect(_style_cost_label.bind(b))
	(box.get_child(1) as TextureRect).texture = Art.tex(CURRENCY_GLYPHS[glyph])
	if b.custom_minimum_size.x < 10:
		b.custom_minimum_size.x = lab.get_minimum_size().x + 70

# ---------------------------------------------------------------- верхняя панель

var top_panel: PanelContainer
var build_cards := {}

func _build_top_bar() -> void:
	var panel := PanelContainer.new()
	top_panel = panel
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
	science_icon = _icon("science", 28)
	row.add_child(science_icon)
	science_label = _label("", 24, Defs.RESOURCES.science.color)
	row.add_child(science_label)
	boost_label = _label("", 20, Color(1.0, 0.85, 0.3))
	boost_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(boost_label)
	row.add_child(_icon("people", 26, Color(0.85, 0.95, 1.0)))
	mode_label = _label("", 18)
	row.add_child(mode_label)
	pop_label = _label("", 24)
	row.add_child(pop_label)
	var gear := TextureButton.new()
	gear.texture_normal = Art.tex("res://art/ui/icons/settings.png")
	gear.ignore_texture_size = true
	gear.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	gear.custom_minimum_size = Vector2(44, 44)
	gear.pressed.connect(func():
		Audio.play("tap")
		_open_settings())
	row.add_child(gear)
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
	# уровень колонии: тонкая золотая шкала
	colony_bar = Control.new()
	colony_bar.custom_minimum_size = Vector2(0, 18)
	colony_bar.draw.connect(_draw_colony_bar)
	vb.add_child(colony_bar)

var colony_bar: Control

func _draw_colony_bar() -> void:
	var r := Rect2(Vector2.ZERO, colony_bar.size)
	var font := ThemeDB.fallback_font
	var txt := tr("Colony lvl %d") % Game.colony_level
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 12
	colony_bar.draw_string_outline(font, Vector2(2, 14), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.8))
	colony_bar.draw_string(font, Vector2(2, 14), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.85, 0.4))
	var br := Rect2(tw, 5, r.size.x - tw, 8)
	colony_bar.draw_rect(br, Color(0, 0, 0, 0.5))
	var f := float(Game.colony_xp) / float(Game.colony_xp_needed())
	colony_bar.draw_rect(Rect2(br.position, Vector2(br.size.x * f, br.size.y)), Color(1.0, 0.78, 0.25))
	colony_bar.draw_rect(Rect2(br.position, Vector2(br.size.x * f, 3)), Color(1, 1, 1, 0.3))

## Комбо и летящие к панели ресурсы при сборе.
var combo_label: Label

func _on_combo(count: int, mult: float) -> void:
	if count < 2:
		return
	if combo_label == null:
		combo_label = _label("", 34, Color(1.0, 0.85, 0.3))
		combo_label.add_theme_constant_override("outline_size", 9)
		combo_label.add_theme_color_override("font_outline_color", Color(0.3, 0.1, 0.0))
		combo_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
		combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		combo_label.offset_left = -200
		combo_label.offset_right = 200
		combo_label.offset_top = 205
		combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(combo_label)
	combo_label.text = tr("Combo ×%d · +%d%%") % [count, int(round((mult - 1.0) * 100))]
	combo_label.modulate.a = 1.0
	combo_label.pivot_offset = Vector2(200, 20)
	combo_label.scale = Vector2(1.3, 1.3)
	var tw := create_tween()
	tw.tween_property(combo_label, "scale", Vector2.ONE, 0.2)
	tw.tween_interval(1.2)
	tw.tween_property(combo_label, "modulate:a", 0.0, 0.4)

func _on_collected(room_id: int, res: String, amount: int) -> void:
	var r := Game.get_room(room_id)
	if r.is_empty():
		return
	view.add_shake(2.5)
	var from: Vector2 = view.get_viewport().get_canvas_transform() * view.room_rect(r).get_center()
	var target_ctrl: Control = res_bars.get(res, pearls_label if res == "pearls" else science_label)
	if target_ctrl == null:
		return
	var to := target_ctrl.get_global_rect().position + Vector2(22, target_ctrl.size.y / 2.0)
	var tex := Art.icon(res)
	if tex == null:
		return
	var n := clampi(amount / 6, 3, 8)
	for i in n:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size = Vector2(34, 34)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ic.position = from + Vector2(randf_range(-40, 40), randf_range(-25, 25)) - ic.size / 2.0
		root.add_child(ic)
		var tw := create_tween()
		tw.tween_interval(i * 0.04)
		tw.tween_property(ic, "position", to - ic.size / 2.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(ic, "scale", Vector2(0.6, 0.6), 0.55)
		tw.tween_callback(ic.queue_free)
	var pulse := create_tween()
	target_ctrl.pivot_offset = target_ctrl.size / 2.0
	pulse.tween_interval(0.55)
	pulse.tween_property(target_ctrl, "scale", Vector2(1.08, 1.08), 0.08)
	pulse.tween_property(target_ctrl, "scale", Vector2.ONE, 0.12)

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
	var md: Dictionary = Game.mode()
	mode_label.text = "" if Game.difficulty == "normal" else tr(md.name) + " "
	mode_label.add_theme_color_override("font_color", md.color)
	var show_sci := Game.science > 0 or Game.count_of("lab") > 0
	science_label.visible = show_sci
	science_icon.visible = show_sci
	science_label.text = str(Game.science)
	pop_label.text = "%d/%d" % [Game.colonists.size(), Game.population_cap()]
	boost_label.text = tr("x2 %s") % _clock(Game.boost_left()) if Game.boost_active() else ""
	_refresh_expedition_button()
	if tasks_badge:
		tasks_badge.visible = Game.quests_ready() > 0 or Game.season_claimable() > 0 or Game.story_ready() or Game.achievements_ready() > 0
		tasks_badge.queue_redraw()
	if shop_badge:
		shop_badge.visible = Game.daily_available() or Game.free_crate_ready()
		shop_badge.queue_redraw()
	for k in res_bars:
		res_bars[k].queue_redraw()
	if colony_bar:
		colony_bar.queue_redraw()

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
	for item in [["Build", _open_build], ["Crew", _open_colonists], ["Tasks", _open_tasks], ["Shop", _open_shop], ["Collect", _collect_all]]:
		var b := _button(item[0], item[1], 84)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 21)
		bottom_bar.add_child(b)
		var icon_name: String = {"Build": "build", "Crew": "crew", "Tasks": "tasks", "Shop": "shop", "Collect": "gift"}[item[0]]
		if Art.tex("res://art/ui/icons/%s.png" % icon_name):
			_with_icon(b, icon_name, 44)
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			b.add_theme_font_size_override("font_size", 17)
		if item[0] == "Tasks":
			tasks_badge = _badge()
			b.add_child(tasks_badge)
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

# кнопка экспедиции: видна, пока экипаж в море или ждёт с добычей
var exp_btn: Button

func _build_expedition_button() -> void:
	exp_btn = _button("", func():
		if Game.expeditions.is_empty():
			return
		var e: Dictionary = Game.expeditions[0]
		if Game.expedition_done(e):
			Game.claim_expedition(e)
		else:
			_open_room(e.dock), 64)
	exp_btn.icon = Art.tex("res://art/creatures/bathyscaphe.png")
	exp_btn.expand_icon = true
	exp_btn.add_theme_constant_override("icon_max_width", 70)
	exp_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	exp_btn.offset_left = -330
	exp_btn.offset_right = -16
	exp_btn.offset_top = 344
	exp_btn.offset_bottom = 408
	exp_btn.visible = false
	root.add_child(exp_btn)

func _refresh_expedition_button() -> void:
	if exp_btn == null:
		return
	exp_btn.visible = not Game.expeditions.is_empty() and not sheet.visible
	if not exp_btn.visible:
		return
	var e: Dictionary = Game.expeditions[0]
	if Game.expedition_done(e):
		exp_btn.text = tr("Collect loot!")
		_gold(exp_btn)
		exp_btn.scale = Vector2.ONE * (1.0 + 0.04 * sin(Time.get_ticks_msec() / 150.0))
	else:
		exp_btn.text = "%s %s" % [tr(Defs.ZONES[e.zone].name), _clock(float(e.end) - Game.now())]
		exp_btn.scale = Vector2.ONE
	exp_btn.pivot_offset = exp_btn.size / 2.0
	exp_btn.offset_top = 270
	exp_btn.offset_bottom = exp_btn.offset_top + 64

func _collect_all() -> void:
	var n := Game.collect_all()
	show_toast(tr("Collected from %d rooms") % n if n > 0 else tr("Nothing to collect yet"))

# ---------------------------------------------------------------- выдвижная панель

func _build_sheet() -> void:
	sheet = PanelContainer.new()
	sheet.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_left = 12
	sheet.offset_right = -12
	sheet.offset_bottom = -12
	var sheet_box := _box(PANEL_BG, Color(ACCENT, 0.45))
	sheet_box.content_margin_left = 20
	sheet_box.content_margin_right = 12
	sheet_box.content_margin_top = 18
	sheet_box.content_margin_bottom = 18
	sheet.add_theme_stylebox_override("panel", sheet_box)
	sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	sheet.visible = false
	root.add_child(sheet)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# без мёртвой зоны любое дрожание пальца считается прокруткой и отменяет нажатие кнопок
	scroll.scroll_deadzone = 24
	scroll.custom_minimum_size = Vector2(0, 560)
	sheet.add_child(scroll)
	# справа — место под полосу прокрутки, чтобы она не налезала на кнопки
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 14)
	scroll.add_child(pad)
	sheet_body = VBoxContainer.new()
	sheet_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_body.add_theme_constant_override("separation", 12)
	pad.add_child(sheet_body)
	get_tree().node_added.connect(_on_node_added)

## Чтобы список прокручивался пальцем, элементы внутри панели не должны «съедать» касание.
func _on_node_added(n: Node) -> void:
	if not (n is Control and sheet and sheet.is_ancestor_of(n)) or n is ScrollBar:
		return
	var c := n as Control
	if c.mouse_filter == Control.MOUSE_FILTER_STOP:
		c.mouse_filter = Control.MOUSE_FILTER_PASS
	# длинные тексты (особенно в переводах) переносим, а не выталкиваем кнопки за край
	var expands := (c.size_flags_horizontal & Control.SIZE_EXPAND) != 0
	if c is Label and (expands or c.get_parent() is VBoxContainer):
		var l := c as Label
		if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _open_sheet(kind: String, height := 560) -> void:
	# обновление того же меню (после нажатия кнопки) — без мигания и прыжка прокрутки наверх
	var refresh := sheet.visible and kind == sheet_kind
	var scroll := sheet.get_child(0) as ScrollContainer
	var keep := scroll.scroll_vertical if refresh else 0
	sheet_kind = kind
	for ch in sheet_body.get_children():
		sheet_body.remove_child(ch)
		ch.queue_free()
	scroll.set_meta("want", height)
	scroll.custom_minimum_size.y = _sheet_height(height)
	if not sheet.visible:
		Audio.play("open")
	sheet.visible = true
	bottom_bar.visible = false
	if refresh:
		_restore_scroll.call_deferred(keep)
		return
	scroll.scroll_vertical = 0
	sheet.pivot_offset = Vector2(sheet.size.x / 2.0, sheet.size.y)
	sheet.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(sheet, "modulate:a", 1.0, 0.15)

func _restore_scroll(v: int) -> void:
	await get_tree().process_frame
	(sheet.get_child(0) as ScrollContainer).scroll_vertical = v

func _close_sheet() -> void:
	if sheet.visible:
		Audio.play("close")
	sheet.visible = false
	sheet_kind = ""
	sheet_room = -1
	bottom_bar.visible = true
	view.selected_room = -1

func _header(title: String) -> void:
	var row := HBoxContainer.new()
	var l := _label(title, 34, Color(1.0, 0.86, 0.35))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.0, 0.9))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var close := _button("✕", _close_sheet, 60)
	close.custom_minimum_size.x = 60
	var red := button_styles(Color(0.85, 0.25, 0.3), Color(1.0, 0.6, 0.6), Color(0.45, 0.08, 0.12))
	for k in red:
		close.add_theme_stylebox_override(k, red[k])
	row.add_child(close)
	sheet_body.add_child(row)

# ---------------------------------------------------------------- строительство

func _open_build() -> void:
	_open_sheet("build", 620)
	_header(tr("Build"))
	build_cards = {}
	for type in Defs.ROOMS:
		var def: Dictionary = Defs.ROOMS[type]
		if not def.buildable:
			continue
		var card := PanelContainer.new()
		build_cards[type] = card
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
		var thumb := Art.room(type)
		if thumb:
			# мини-картинка отсека вместо значка
			var frame := PanelContainer.new()
			var fb := _box(Color(0, 0, 0, 0.4), Color(def.color, 0.9), 10, 2)
			fb.set_content_margin_all(2)
			fb.shadow_size = 0
			frame.add_theme_stylebox_override("panel", fb)
			var pic := TextureRect.new()
			pic.texture = thumb
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pic.custom_minimum_size = Vector2(118, 74) if type != "elevator" else Vector2(56, 74)
			frame.add_child(pic)
			hb.add_child(frame)
		else:
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
			if Game.pearls < cost:
				b.modulate = Color(1, 1, 1, 0.55)
		else:
			b = _button(tr("Needs %d colonists") % def.unlock_pop, func(): pass, 64)
			b.disabled = true
		b.custom_minimum_size.x = 150
		hb.add_child(b)
		sheet_body.add_child(card)

func _start_build(type: String) -> void:
	_close_sheet()
	var need := Game.build_cost(type) - Game.pearls
	if need > 0:
		show_banner("pearls", tr("Not enough pearls"), tr("You need %d more pearls.") % need)
		Audio.play("error")
		return
	var spots := Game.build_spots(type)
	if spots.is_empty():
		show_banner("build", tr("No free space"), tr("Build an Elevator below to open new floors.") if type != "elevator" else tr("Build rooms next to the elevator first."))
		return
	view.build_type = type
	view.focus_cell(spots[0], Defs.room_width(type))
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
	_open_sheet("room", 640 if r.type == "dock" else 520)
	var size_txt := " %d×" % r.size if r.size > 1 else ""
	_header(tr("%s · lvl %d") % [tr(def.name) + size_txt, r.level])
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	var art := Art.room_of(r)
	if art:
		var frame := PanelContainer.new()
		var fb := _box(Color(0, 0, 0, 0.4), Color(def.color, 0.8), 10, 2)
		fb.set_content_margin_all(3)
		frame.add_theme_stylebox_override("panel", fb)
		var pic := TextureRect.new()
		pic.texture = art
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(190, 119)
		frame.add_child(pic)
		top.add_child(frame)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	var d := _label(def.desc, 19, Color(0.75, 0.85, 0.95))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(d)
	var zone := Game.depth_zone(r.row)
	if zone.bonus > 0.0:
		var zl := _label(tr("%s: +%d%% production, more incidents") % [tr(zone.name), int(zone.bonus * 100)], 16, zone.color)
		zl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(zl)
	var eff := Game.room_effect(r)
	if eff != "":
		var el := _label(eff, 18, Color(0.7, 1.0, 0.8))
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(el)
	top.add_child(info)
	sheet_body.add_child(top)
	room_live_labels = {}
	if def.has("produces") == false and r.incident > 0.0:
		var hz := _label("", 22, Color(1.0, 0.6, 0.5))
		hz.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hz.text = "%s · %s" % [tr(Game.HAZARDS[r.hazard].label), tr("Drag colonists here to help!")]
		sheet_body.add_child(hz)
	if r.type == "dock":
		_dock_section(r)
	if r.type == "airlock":
		_outside_section()
	if def.has("produces") and r.ready:
		var col := _button(tr("Collect"), func():
			Game.collect(r)
			_open_room(id), 72)
		_gold(col)
		var ic := Art.icon(def.produces)
		if ic:
			col.icon = ic
			col.expand_icon = true
			col.add_theme_constant_override("icon_max_width", 40)
		sheet_body.add_child(col)
	if def.has("produces"):
		var st := _label("", 20, Color(1.0, 0.92, 0.6))
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(st)
		room_live_labels["status"] = st
	var slots := Game.slots(r)
	if slots > 0:
		var stat_name: String = Defs.STATS[def.stat]
		var training: bool = def.has("train")
		if training:
			sheet_body.add_child(_label(tr("Workers (%d/%d)") % [Game.workers_in(r).size(), slots], 22, ACCENT))
		else:
			sheet_body.add_child(_label(tr("Workers (%d/%d) · needs %s") % [Game.workers_in(r).size(), slots, tr(stat_name)], 22, ACCENT))
		for c in Game.workers_in(r):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.add_child(_portrait(c, 56))
			var line := "%s  ·  %s %d  ·  ♥ %d" % [c.name, tr(stat_name), Game.stat(c, def.stat), int(c.health)]
			if training:
				line = "%s  ·  %s %d%%" % [c.name, tr("training"), int(100.0 * float(c.get("train", 0.0)) / Game.train_time(r))]
			var l := _button(line, _open_colonist.bind(c.id), 56)
			l.alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	if r.level < Defs.MAX_LEVEL and (def.get("buildable", false) or def.get("upgradable", false)):
		var cost := Game.upgrade_cost(r)
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
		_with_icon(safe, "speed", 40)
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
	if room_live_labels.has("exp"):
		_refresh_dock_live(r)
	if room_live_labels.has("status"):
		var res: String = def.produces
		var txt := ""
		if r.incident > 0.0:
			txt = "%s %d%% · %s" % [tr(Game.HAZARDS[r.hazard].label), int(r.incident), tr("Drag colonists here to help!")]
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
		set_cost_text(sb, tr("Finish now, no risk: ◆ %d") % maxi(cost, 0))
		sb.disabled = cost < 0 or r.ready or r.incident > 0.0
		sb.visible = Game.crystal_rush_allowed()

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

func _portrait(c: Dictionary, size: int) -> Control:
	var tex := Art.diver(c.suit)
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size * 0.75, size)
	return t

func reyes_portrait(size: int) -> Control:
	var tex := Art.tex("res://art/characters/reyes.png")
	if tex == null:
		return _portrait({"suit": Art.CAPTAIN_SUIT}, size)
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	return t

func _where(c: Dictionary) -> String:
	if c.get("child", false):
		return tr("Child · grows up in %s") % _clock(float(c.get("grow", 0.0)))
	if c.room == Game.ON_EXPEDITION:
		return tr("On expedition")
	if c.get("help", -1) != -1:
		var hr := Game.get_room(c.help)
		if not hr.is_empty():
			return "%s: %s" % [tr(Game.HAZARDS.get(hr.hazard, {"label": "FIRE"}).label), tr(Defs.ROOMS[hr.type].name)]
	if c.room == -1:
		return tr("Idle (in airlock)")
	return tr(Defs.ROOMS[Game.get_room(c.room).type].name)

## Павший колонист: оживить за жемчуг, пока не вышло время, или похоронить.
func open_fallen(i: int) -> void:
	if i < 0 or i >= Game.fallen.size():
		return
	var f: Dictionary = Game.fallen[i]
	_open_sheet("fallen", 420)
	_header(tr("Fallen: %s") % f.c.name)
	_fallen_card(f, true)

## Карточка сама добавляется в меню (как все _card).
func _fallen_card(f: Dictionary, big: bool) -> void:
	var card := _card(Color(0.2, 0.04, 0.06, 0.92), Color(1.0, 0.35, 0.35, 0.8))
	var por := _portrait(f.c, 76)
	por.modulate = Color(0.55, 0.55, 0.6)
	card.add_child(por)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_label(tr("%s · lvl %d") % [f.c.name, int(f.c.level)], 22, Color(1.0, 0.8, 0.8)))
	var tl := _label(tr("Can be revived for %s more") % _clock(float(f.until) - Game.now()), 17, Color(1.0, 0.65, 0.6))
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tl)
	if big:
		var hint := _label(tr("After that they are lost forever. The cost grows with their level."), 16, Color(0.8, 0.8, 0.85))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(hint)
	card.add_child(vb)
	var col := VBoxContainer.new()
	var cost := Game.revive_cost(f)
	var rb := _button("", func():
		if Game.revive(f):
			_close_sheet() if sheet_kind == "fallen" else _open_colonists(), 60)
	set_cost_text(rb, tr("Revive ◉%d") % cost)
	_gold(rb)
	rb.disabled = Game.pearls < cost
	rb.custom_minimum_size.x = 190
	col.add_child(rb)
	if big:
		col.add_child(_button(tr("Bury"), func():
			Game.bury(f)
			_close_sheet(), 50))
	card.add_child(col)

func _open_colonists() -> void:
	_open_sheet("colonists", 700)
	_header(tr("Colonists (%d/%d)") % [Game.colonists.size(), Game.population_cap()])
	if not Game.fallen.is_empty():
		sheet_body.add_child(_label(tr("Fallen — revive them before it's too late"), 20, Color(1.0, 0.55, 0.5)))
		for f in Game.fallen:
			_fallen_card(f, false)
	sheet_body.add_child(_label(tr("Tap a colonist to see their stats"), 19, Color(0.7, 0.82, 0.92)))
	for c in Game.colonists:
		var card := PanelContainer.new()
		var gold: bool = c.get("rarity", "") == "legendary"
		card.add_theme_stylebox_override("panel", _box(Color(0.06, 0.16, 0.24, 0.9), Color(1.0, 0.8, 0.3, 0.8) if gold else Color(ACCENT, 0.3), 14))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		card.add_child(hb)
		hb.add_child(_portrait(c, 76))
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(vb)
		var top := HBoxContainer.new()
		var n := _label(tr("%s · lvl %d") % [c.name, c.level], 23, Color(1.0, 0.88, 0.5) if gold else Color.WHITE)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(n)
		top.add_child(_label("♥ %d" % int(c.health), 21, Color(1.0, 0.5, 0.5)))
		vb.add_child(top)
		vb.add_child(_label(tr("Strength %d · Tech %d · Biology %d · %s") % [c.str, c.tech, c.bio, _where(c)], 17, Color(0.75, 0.85, 0.95)))
		var xp := ProgressBar.new()
		xp.show_percentage = false
		xp.custom_minimum_size = Vector2(0, 8)
		xp.max_value = Game._xp_needed(c)
		xp.value = c.xp
		vb.add_child(xp)
		var open := Button.new()
		open.flat = true
		open.set_anchors_preset(Control.PRESET_FULL_RECT)
		open.pressed.connect(func():
			Audio.play("tap")
			_open_colonist(c.id))
		card.add_child(open)
		sheet_body.add_child(card)

# ---------------------------------------------------------------- карточка колониста

func _stat_bar(name: String, value: int, col: Color, highlight: bool, key := "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var l := _label(tr(name), 21, Color(1.0, 0.9, 0.6) if highlight else Color(0.85, 0.92, 1.0))
	l.custom_minimum_size.x = 150
	var ic := Art.tex("res://art/ui/stats/%s.png" % key) if key != "" else null
	if ic:
		var tr_ := TextureRect.new()
		tr_.texture = ic
		tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr_.custom_minimum_size = Vector2(36, 36)
		tr_.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(tr_)
		l.custom_minimum_size.x = 120
	row.add_child(l)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 26)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.draw.connect(func():
		var w := bar.size.x
		for i in 10:
			var seg := Rect2(i * w / 10.0 + 2, 2, w / 10.0 - 4, bar.size.y - 4)
			bar.draw_rect(seg, col if i < value else Color(0, 0, 0, 0.45))
			if i < value:
				bar.draw_rect(Rect2(seg.position, Vector2(seg.size.x, 5)), Color(1, 1, 1, 0.25)))
	row.add_child(bar)
	row.add_child(_label("%d" % value, 22))
	return row

func _open_colonist(id: int) -> void:
	var c := Game.get_colonist(id)
	if c.is_empty():
		return
	_open_sheet("colonist", 900)
	var rarity: String = c.get("rarity", "common")
	_header(c.name)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	top.add_child(_portrait(c, 170))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(_label(tr("Level %d") % c.level, 28, Color(1.0, 0.88, 0.5)))
	var rcol: Color = {"common": Color(0.8, 0.85, 0.9), "rare": Color(0.5, 0.8, 1.0), "legendary": Color(1.0, 0.8, 0.3)}[rarity]
	info.add_child(_label(tr("Rarity: %s") % tr(rarity.capitalize()), 19, rcol))
	info.add_child(_label(tr("Works in: %s") % _where(c), 19, Color(0.8, 0.88, 0.95)))
	info.add_child(_label("XP %d / %d" % [int(c.xp), int(Game._xp_needed(c))], 17, Color(0.7, 0.8, 0.9)))
	var xp := ProgressBar.new()
	xp.show_percentage = false
	xp.custom_minimum_size = Vector2(0, 12)
	xp.max_value = Game._xp_needed(c)
	xp.value = c.xp
	info.add_child(xp)
	info.add_child(_label("%s %d%%" % [tr("Health"), int(c.health)], 17, Color(1.0, 0.6, 0.6)))
	var hp := ProgressBar.new()
	hp.show_percentage = false
	hp.custom_minimum_size = Vector2(0, 12)
	hp.value = c.health
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.9, 0.3, 0.35)
	hp_fill.set_corner_radius_all(6)
	hp.add_theme_stylebox_override("fill", hp_fill)
	info.add_child(hp)
	top.add_child(info)
	sheet_body.add_child(top)

	var mood := int(c.get("mood", 70.0))
	var mood_txt := tr("Happy") if mood >= 70 else (tr("Okay") if mood >= 40 else tr("Unhappy"))
	var mood_col := Color(0.5, 1.0, 0.55) if mood >= 70 else (Color(1.0, 0.85, 0.4) if mood >= 40 else Color(1.0, 0.45, 0.4))
	var ml := _label("%s: %s %d%% · %s ×%.2f" % [tr("Mood"), mood_txt, mood, tr("work speed"), Game.mood_factor(c)], 18, mood_col)
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 8)
	var face := Art.tex("res://art/ui/stats/mood_%s.png" % ("happy" if mood >= 70 else ("okay" if mood >= 40 else "sad")))
	if face:
		var fr := TextureRect.new()
		fr.texture = face
		fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fr.custom_minimum_size = Vector2(40, 40)
		mrow.add_child(fr)
	mrow.add_child(ml)
	sheet_body.add_child(mrow)
	var best := Game.best_stat(c)
	for k in Defs.ALL_STATS:
		var row := _stat_bar(Defs.STATS[k], mini(10, Game.stat(c, k)), Defs.STAT_COLORS[k], k == best, k)
		if Game.stat(c, k) > c[k]:
			(row.get_child(row.get_child_count() - 1) as Label).text = "%d+%d" % [c[k], Game.stat(c, k) - c[k]]
		var tb := _button(tr("Train ◆ %d") % Game.train_cost(c, k) if c[k] < 10 else "MAX", func():
			Game.train(c, k)
			_open_colonist(id), 50)
		tb.custom_minimum_size.x = 170
		tb.add_theme_font_size_override("font_size", 18)
		tb.add_theme_color_override("font_color", Defs.RESOURCES.crystals.color)
		tb.disabled = c[k] >= 10 or c.room == Game.ON_EXPEDITION
		row.add_child(tb)
		sheet_body.add_child(row)

	more.add_gear_section(c)
	sheet_body.add_child(_label(tr("Best job: %s") % tr(Defs.ROOMS[Game.best_job_type(c)].name), 20, Color(1.0, 0.9, 0.6)))
	var perks := _label(tr("Endurance: less damage. Charm: trader discounts. Luck: chance to collect double. Mood: work speed."), 17, Color(0.72, 0.82, 0.92))
	perks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sheet_body.add_child(perks)
	var how := _label(tr("How to grow") + ": " + tr("Colonists gain XP while working. Each level adds +1 to the skill their room needs, up to 10."), 17, Color(0.72, 0.82, 0.92))
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sheet_body.add_child(how)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	var best_room := Game.best_room_for(c)
	var ab := _button(tr("Assign to best room"), func():
		Game.assign(c, Game.best_room_for(c))
		_open_colonist(id), 68)
	ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ab.disabled = best_room.is_empty() or best_room.id == c.room or c.room == Game.ON_EXPEDITION
	actions.add_child(ab)
	if c.health < 100.0:
		var hb := _button(tr("Heal ◆ %d") % Game.heal_cost(c), func():
			Game.heal(c)
			_open_colonist(id), 68)
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_theme_color_override("font_color", Defs.RESOURCES.crystals.color)
		actions.add_child(hb)
	sheet_body.add_child(actions)
	sheet_body.add_child(_button(tr("Crew"), _open_colonists, 56))

# ---------------------------------------------------------------- настройки

func _toggle_row(title: String, on: bool, cb: Callable) -> void:
	var row := _card(Color(0.05, 0.12, 0.2, 0.9), Color(ACCENT, 0.4))
	var l := _label(tr(title), 24)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var b := _button(tr("On") if on else tr("Off"), func():
		cb.call(not on)
		_open_settings(), 60)
	b.custom_minimum_size.x = 150
	if not on:
		b.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	row.add_child(b)

func _open_settings() -> void:
	_open_sheet("settings", 900)
	_header(tr("Settings"))
	_toggle_row("Music", Audio.music_on, Audio.set_music)
	_toggle_row("Sounds", Audio.sfx_on, Audio.set_sfx)
	_section(tr("Language"))
	var langs := GridContainer.new()
	langs.columns = 2
	langs.add_theme_constant_override("h_separation", 10)
	langs.add_theme_constant_override("v_separation", 10)
	for code in Audio.LANGUAGES:
		var b := _button(Audio.LANGUAGES[code], func():
			Audio.set_language(code)
			_open_settings(), 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		if Audio.language == code:
			b.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
			b.add_theme_stylebox_override("normal", _box(Color(0.25, 0.18, 0.05), Color(1.0, 0.8, 0.3), 14))
		langs.add_child(b)
	sheet_body.add_child(langs)
	var gap := Control.new()
	gap.custom_minimum_size.y = 20
	sheet_body.add_child(gap)
	sheet_body.add_child(_button(tr("Replay tutorial"), func():
		_close_sheet()
		start_tutorial(), 60))
	var reset := _button(tr("Start over"), func(): pass, 60)
	reset.pressed.connect(func():
		if reset.get_meta("armed", false):
			Game.reset()
			_close_sheet()
			open_mode_picker()
		else:
			reset.set_meta("armed", true)
			reset.text = tr("Tap again to erase all progress"))
	reset.modulate = Color(1, 0.7, 0.7)
	sheet_body.add_child(reset)
	sheet_body.add_child(_label(tr("Version %s") % ProjectSettings.get_setting("application/config/version", "0.1"), 16, Color(0.55, 0.65, 0.75)))

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

# ---------------------------------------------------------------- баннеры

var banner_queue: Array = []
var banner_node: PanelContainer
var banner_busy := false

func show_banner(icon: String, title: String, text: String) -> void:
	banner_queue.append([icon, title.strip_edges().trim_suffix(":"), text])
	if not banner_busy:
		_next_banner()

func _next_banner() -> void:
	if banner_queue.is_empty():
		banner_busy = false
		return
	banner_busy = true
	var b: Array = banner_queue.pop_front()
	if banner_node:
		banner_node.queue_free()
	banner_node = PanelContainer.new()
	banner_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := _box(Color(0.12, 0.08, 0.02, 0.96), Color(1.0, 0.8, 0.3), 22, 4)
	st.shadow_size = 12
	st.content_margin_left = 16
	banner_node.add_theme_stylebox_override("panel", st)
	banner_node.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner_node.offset_left = 24
	banner_node.offset_right = -24
	root.add_child(banner_node)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	banner_node.add_child(hb)
	var tex := Art.marker_icon(b[0])
	if tex:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(76, 76)
		hb.add_child(ic)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := _label(b[1], 28, Color(1.0, 0.86, 0.35))
	t.add_theme_constant_override("outline_size", 7)
	t.add_theme_color_override("font_outline_color", Color(0.3, 0.12, 0.0))
	vb.add_child(t)
	if b[2] != "":
		var d := _label(b[2], 20, Color(1, 0.97, 0.9))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(d)
	hb.add_child(vb)
	# уведомление не должно перехватывать нажатия на кнопки под ним
	for n in banner_node.find_children("*", "Control", true, false):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if landscape:
		banner_node.anchor_right = 0.0
		banner_node.offset_right = top_panel.offset_right - 12
	# выезжает сверху, подпрыгивает, держится и уезжает
	banner_node.offset_top = -160
	banner_node.offset_bottom = -160
	var tw := create_tween()
	tw.tween_property(banner_node, "offset_top", 150.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(banner_node, "offset_bottom", 150.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(2.2)
	tw.tween_property(banner_node, "modulate:a", 0.0, 0.3)
	tw.tween_callback(_next_banner)

func _on_colony_lost() -> void:
	for ch in popup.get_children():
		ch.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	popup.add_child(vb)
	var t := _label(tr("The colony is lost"), 32, Color(1.0, 0.5, 0.45))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var d := _label(tr("Everyone has died. In Survival mode that is the end — but every colony teaches something. Try again?"), 20)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.custom_minimum_size.x = 480
	vb.add_child(d)
	vb.add_child(_gold(_button(tr("Start over"), func():
		popup_bg.visible = false
		Game.reset()
		open_mode_picker(), 70)))
	popup_bg.visible = true

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
	var tex := Art.tex("res://art/ui/shop/%s_card.png" % key)
	if tex == null:
		tex = Art.tex("res://art/ui/shop/%s.png" % key)
	if tex == null:
		return null
	var tr_ := TextureRect.new()
	tr_.texture = tex
	tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr_.custom_minimum_size = Vector2(0, 340)
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
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 8)
	drow.add_child(_label(tr("Day %d") % (Game.daily_next_index() + 1) + ":", 18, Color(0.9, 0.85, 0.7)))
	drow.add_child(_reward_chips(Defs.DAILY[Game.daily_next_index()], 28, 18))
	dinfo.add_child(drow)
	daily.add_child(dinfo)
	var db := _button(tr("Claim") if Game.daily_available() else tr("Tomorrow"), func():
		Game.claim_daily()
		_open_shop(), 64)
	db.disabled = not Game.daily_available()
	db.custom_minimum_size.x = 170
	_with_icon(db, "gift", 36)
	daily.add_child(db)

	var free := _card(Color(0.05, 0.14, 0.22, 0.9), Color(0.5, 0.8, 1.0, 0.7))
	free.add_child(_crate_icon("common", 64))
	var finfo := VBoxContainer.new()
	finfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	finfo.add_child(_label(tr("Free Supply Crate"), 24))
	finfo.add_child(_label(tr("Watch a short video") if not Game.ads_removed() else tr("No ads needed"), 18, Color(0.75, 0.85, 0.95)))
	free.add_child(finfo)
	var fb := _button("", func(): Store.show_rewarded(func():
		Game.claim_free_crate()
		_open_shop()), 64)
	fb.custom_minimum_size.x = 170
	_with_icon(fb, "ad", 36)
	free.add_child(fb)
	shop_live["free"] = fb

	var boost := _card(Color(0.18, 0.15, 0.03, 0.9), Color(1.0, 0.85, 0.3, 0.7))
	var binfo := VBoxContainer.new()
	binfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	binfo.add_child(_label(tr("Double collection"), 24))
	binfo.add_child(_label(tr("x2 resources from rooms for 30 min"), 18, Color(0.9, 0.85, 0.7)))
	boost.add_child(binfo)
	var bb := _button(tr("Watch"), func(): Store.show_rewarded(func():
		Game.start_boost()
		_open_shop()), 64)
	_with_icon(bb, "ad", 36)
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

	if Store.can_buy("no_ads") and not Game.premium:
		var na := Store.product("no_ads")
		var nrow := _card(Color(0.2, 0.06, 0.08, 0.92), Color(1.0, 0.45, 0.45, 0.8))
		var nic := TextureRect.new()
		nic.texture = Art.tex("res://art/ui/icons/ad.png")
		nic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		nic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		nic.custom_minimum_size = Vector2(72, 72)
		nic.draw.connect(func(): nic.draw_line(Vector2(8, 8), Vector2(64, 64), Color(1, 0.2, 0.2), 7.0))
		nrow.add_child(nic)
		var ninfo := VBoxContainer.new()
		ninfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ninfo.add_child(_label(tr(na.title), 24, Color(1.0, 0.8, 0.8)))
		var nd := _label(tr(na.desc), 17)
		nd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ninfo.add_child(nd)
		nrow.add_child(ninfo)
		var nb := _button(na.price, func():
			Store.purchase("no_ads")
			_open_shop(), 64)
		nb.custom_minimum_size.x = 130
		nrow.add_child(nb)

	for id in ["starter_pack", "premium"]:
		if not Store.can_buy(id):
			continue
		var p := Store.product(id)
		_section(tr("Special offer") if id == "starter_pack" else tr("Premium"))
		var banner := _banner(p.banner)
		if banner:
			sheet_body.add_child(banner)
		var offer := _card(Color(0.25, 0.1, 0.3, 0.92) if id == "starter_pack" else Color(0.25, 0.2, 0.05, 0.92), Color(1.0, 0.8, 0.4, 0.9))
		var thumb := Art.tex("res://art/creatures/clownfish.png") if id == "starter_pack" else Art.diver(Art.CAPTAIN_SUIT)
		if thumb:
			var ti := TextureRect.new()
			ti.texture = thumb
			ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ti.custom_minimum_size = Vector2(72, 72)
			offer.add_child(ti)
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
			row.add_child(_crate_icon(item.reward.crates.keys()[0], 64))
		else:
			var pile := Art.tex("res://art/ui/shop/pearls_%d.png" % (1 if item.reward.pearls < 1000 else 2))
			if pile:
				var pt := TextureRect.new()
				pt.texture = pile
				pt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				pt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				pt.custom_minimum_size = Vector2(64, 64)
				row.add_child(pt)
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

	_section(tr("Spend pearls"))
	for item in Store.PEARL_ITEMS:
		var prow := _card(Color(0.16, 0.08, 0.16, 0.9), Color(1.0, 0.7, 0.95, 0.4))
		prow.add_child(_crate_icon(item.reward.crates.keys()[0], 64))
		var pv := VBoxContainer.new()
		pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pv.add_child(_label(tr(item.title), 22))
		var note := _label(tr("Price grows with each purchase today"), 15, Color(0.85, 0.75, 0.85))
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pv.add_child(note)
		prow.add_child(pv)
		var price := Store.pearl_price(item)
		var pb := _button("", func():
			Store.buy_with_pearls(item.id)
			_open_shop(), 60)
		set_cost_text(pb, "◉ %d" % price)
		pb.disabled = Game.pearls < price
		pb.custom_minimum_size.x = 170
		prow.add_child(pb)

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
			fb.text = tr("Free") if not Game.ads_removed() else tr("Claim")
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

## Награда как список [иконка, короткий текст].
func _reward_items(r: Dictionary) -> Array:
	var out := []
	if r.has("pearls"): out.append(["pearls", str(r.pearls)])
	if r.has("crystals"): out.append(["crystals", str(r.crystals)])
	if r.get("resources", 0) > 0: out.append(["food", str(r.resources)])
	for k in r.get("crates", {}):
		out.append(["crate_" + k, "×%d" % r.crates[k]])
	if r.has("colonist"): out.append(["colonist" if r.colonist != "legendary" else "captain", tr(r.colonist.capitalize())])
	if r.has("item"): out.append(["item_" + str(r.get("item_base", "diving_armor")), tr(r.item.capitalize())])
	return out

## Награда картинками: [иконка] 100  [иконка] ×1
func _reward_chips(r: Dictionary, size := 30, font := 18, center := false) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center:
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
	for it in _reward_items(r):
		var tex := Art.marker_icon(it[0])
		if tex:
			var t := TextureRect.new()
			t.texture = tex
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.custom_minimum_size = Vector2(size, size)
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hb.add_child(t)
		var l := _label(it[1], font)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(l)
	return hb

## Кнопка с наградой: иконка первой награды + короткий текст всех.
func _reward_button(b: Button, r: Dictionary, prefix := "") -> void:
	var items := _reward_items(r)
	if items.is_empty():
		return
	var tex := Art.marker_icon(items[0][0])
	if tex:
		b.icon = tex
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 34)
	var parts := []
	for i in items.size():
		parts.append(items[i][1] if i == 0 else tr(items[i][1]) if not items[i][0].begins_with("crate_") else tr(Defs.CRATES[items[i][0].trim_prefix("crate_")].name))
	b.text = prefix + "  ".join(parts)

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
		var chips := _reward_chips(Defs.DAILY[i], 40, 18, true)
		if i < next:
			chips.modulate = Color(1, 1, 1, 0.45)
			var ok := _label("✓", 18, Color(0.5, 1.0, 0.6))
			chips.add_child(ok)
		vb.add_child(chips)
		grid.add_child(cell)
	sheet_body.add_child(_with_icon(_button(tr("Claim"), func():
		Game.claim_daily()
		_close_sheet(), 72), "gift", 48))

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
		var m := Art.split_marker(line)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 12)
		var ic := Art.marker_icon(m[0]) if m[0] != "" else null
		if ic:
			var tr_ := TextureRect.new()
			tr_.texture = ic
			tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr_.custom_minimum_size = Vector2(52, 52)
			row.add_child(tr_)
		var l := _label(m[1], 24)
		if ic == null:
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			# короткая строка рядом с иконкой — без переноса, иначе ширина схлопывается до буквы
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
		if ic == null:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(l)
		vb.add_child(row)
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

# ---------------------------------------------------------------- экспедиции

var plan_zone := 0
var plan_crew: Array = []

## Выход наружу: экспедиции идут через док батискафа.
func open_outside() -> void:
	var dock := Game.find_room_of_type("dock")
	if not dock.is_empty():
		view.selected_room = dock.id
		_open_room(dock.id)
		return
	_open_sheet("outside", 460)
	_header(tr("Expedition"))
	_outside_section()

func _outside_section() -> void:
	var dock := Game.find_room_of_type("dock")
	var z := Art.tex("res://art/zones/reef.png")
	if z:
		var zb := TextureRect.new()
		zb.texture = z
		zb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		zb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		zb.custom_minimum_size = Vector2(0, 140)
		sheet_body.add_child(zb)
	if not dock.is_empty():
		sheet_body.add_child(_with_icon(_button(tr("Plan an expedition"), func(): _open_room(dock.id), 72), "expedition", 44))
		return
	var need: int = Defs.ROOMS.dock.unlock_pop
	var txt := tr("To go outside, build a Sub Dock. Crews sail from it on expeditions for loot.")
	var l := _label(txt, 19, Color(0.85, 0.92, 1.0))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sheet_body.add_child(l)
	if Game.is_unlocked("dock"):
		sheet_body.add_child(_with_icon(_button(tr("Build a Sub Dock"), _start_build.bind("dock"), 72), "build", 44))
	else:
		sheet_body.add_child(_label(tr("Needs %d colonists") % need + "  (%d/%d)" % [Game.colonists.size(), need], 20, Color(1.0, 0.75, 0.5)))

func _dock_section(r: Dictionary) -> void:
	var e := Game.expedition_at(r.id)
	if e.is_empty():
		sheet_body.add_child(_with_icon(_button(tr("Plan an expedition"), _open_planner.bind(r.id, 0), 76), "expedition", 48))
		return
	var zone: Dictionary = Defs.ZONES[e.zone]
	var zbanner := Art.tex("res://art/zones/%s.png" % zone.id)
	if zbanner:
		var zb := TextureRect.new()
		zb.texture = zbanner
		zb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		zb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		zb.custom_minimum_size = Vector2(0, 170)
		sheet_body.add_child(zb)
	var crew_names := []
	for id in e.crew:
		crew_names.append(Game.get_colonist(id).get("name", "?"))
	sheet_body.add_child(_label(tr("Destination: %s") % tr(zone.name), 24, Color(1.0, 0.88, 0.5)))
	var cl := _label(tr("Crew: %s") % ", ".join(crew_names), 19, Color(0.8, 0.88, 0.95))
	cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sheet_body.add_child(cl)
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, 26)
	pb.show_percentage = false
	pb.max_value = 1.0
	pb.step = 0.001
	sheet_body.add_child(pb)
	var st := _label("", 20)
	sheet_body.add_child(st)
	# сводка: опыт, бои, здоровье экипажа и что уже нашли
	var summary := VBoxContainer.new()
	summary.add_theme_constant_override("separation", 6)
	sheet_body.add_child(summary)
	var logbox := VBoxContainer.new()
	logbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logbox.add_theme_constant_override("separation", 6)
	sheet_body.add_child(_label(tr("Expedition log"), 20, ACCENT))
	var logscroll := ScrollContainer.new()
	logscroll.scroll_deadzone = 24
	logscroll.custom_minimum_size = Vector2(0, 260)
	logscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	logscroll.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.35), Color(ACCENT, 0.25), 12, 1))
	logscroll.add_child(logbox)
	sheet_body.add_child(logscroll)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	var fin := _button("", func():
		Game.finish_expedition_now(e)
		_open_room(r.id), 70)
	fin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fin.add_theme_color_override("font_color", Defs.RESOURCES.crystals.color)
	actions.add_child(fin)
	var ad := _button(tr("-30 min"), func(): Store.show_rewarded(func():
		Game.cut_expedition(e, 1800.0)
		_open_room(r.id)), 70)
	ad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_with_icon(ad, "ad", 36)
	_with_icon(fin, "speed", 36)
	actions.add_child(ad)
	sheet_body.add_child(actions)
	var claim := _button(tr("Collect loot!"), func():
		Game.claim_expedition(e)
		_close_sheet(), 76)
	sheet_body.add_child(claim)
	room_live_labels["exp"] = {"e": e, "bar": pb, "status": st, "log": logbox, "summary": summary, "scroll": logscroll, "fin": fin, "ad": ad, "claim": claim, "shown": -1}
	_refresh_dock_live(r)

func _refresh_dock_live(_r: Dictionary) -> void:
	var d: Dictionary = room_live_labels.exp
	var e: Dictionary = d.e
	var done := Game.expedition_done(e)
	d.bar.value = Game.expedition_progress(e)
	d.status.text = tr("Back home! Collect the loot.") if done else tr("Returns in %s") % _clock(float(e.end) - Game.now())
	d.fin.visible = not done and Game.crystal_rush_allowed()
	d.ad.visible = not done and not e.get("ad_used", false) and Game.ads_left() > 0
	d.claim.visible = done
	set_cost_text(d.fin, tr("Finish ◆ %d") % Game.finish_cost(e) if not done else "")
	var evs := Game.visible_events(e)
	if evs.size() != d.shown:
		d.shown = evs.size()
		_fill_expedition_summary(d.summary, e)
		for ch in d.log.get_children():
			ch.queue_free()
		if evs.is_empty():
			d.log.add_child(_label(tr("The sub just left the dock…"), 18, Color(0.7, 0.8, 0.9)))
		for ev in evs:
			d.log.add_child(_log_row(ev))
		# новые записи внизу — прокручиваем к ним
		var sc: ScrollContainer = d.scroll
		get_tree().process_frame.connect(func(): sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value), CONNECT_ONE_SHOT)

## Строка журнала: значок (бой, находка) и текст.
func _log_row(ev: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var kind: String = ev.get("kind", "")
	var icon_key := ""
	var col := Color(0.85, 0.92, 1.0)
	if kind == "fight":
		col = Color(0.6, 1.0, 0.65) if ev.get("won", false) else Color(1.0, 0.6, 0.55)
	elif kind == "find":
		col = Color(1.0, 0.92, 0.6)
		var items := _reward_items(ev.get("loot", {}))
		if not items.is_empty():
			icon_key = items[0][0]
	var tex: Texture2D = Art.tex("res://art/fx/spark_1.png") if kind == "fight" else (Art.marker_icon(icon_key) if icon_key != "" else null)
	if tex:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(30, 30)
		row.add_child(t)
	else:
		row.add_child(_label("•", 18, col))
	var l := _label(ev.text, 18, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row

func _fill_expedition_summary(box: VBoxContainer, e: Dictionary) -> void:
	for ch in box.get_children():
		ch.queue_free()
	var so := Game.expedition_so_far(e)
	box.add_child(_label(tr("XP so far: +%d · Fights: %d won, %d lost") % [so.xp, so.won, so.lost], 19, Color(0.75, 0.9, 1.0)))
	var hp_parts := []
	for id in e.crew:
		var c := Game.get_colonist(id)
		if c.is_empty():
			continue
		var dmg: float = so.hp.get(str(id), 0) * (1.0 - Game.protection(c)) * Game.mode().damage
		hp_parts.append("%s ♥ %d" % [c.name.split(" ")[0], maxi(1, int(c.health - dmg))])
	var hl := _label(", ".join(hp_parts), 18, Color(1.0, 0.7, 0.7))
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hl)
	var lr := HBoxContainer.new()
	lr.add_theme_constant_override("separation", 10)
	lr.add_child(_label(tr("Loot so far:"), 19, Color(1.0, 0.88, 0.5)))
	if so.loot.is_empty():
		lr.add_child(_label(tr("nothing yet"), 18, Color(0.7, 0.8, 0.9)))
	else:
		lr.add_child(_reward_chips(so.loot, 28, 18))
	box.add_child(lr)

func _open_planner(dock_id: int, zone_idx: int) -> void:
	plan_zone = zone_idx
	plan_crew = plan_crew.filter(func(id): return not Game.get_colonist(id).is_empty() and Game.get_colonist(id).room != Game.ON_EXPEDITION)
	_open_sheet("planner", 900)
	_header(tr("Expedition"))
	sheet_body.add_child(_label(tr("1. Choose a destination"), 22, ACCENT))
	for i in Defs.ZONES.size():
		var z: Dictionary = Defs.ZONES[i]
		var unlocked := Game.zone_unlocked(i)
		var sel := i == plan_zone
		var row := _card(Color(0.25, 0.18, 0.05, 0.95) if sel else Color(0.05, 0.12, 0.2, 0.9), Color(1.0, 0.8, 0.3) if sel else Color(0.5, 0.7, 0.9, 0.4))
		var zpic := Art.tex("res://art/zones/%s.png" % z.id)
		if zpic:
			var zt := TextureRect.new()
			zt.texture = zpic
			zt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			zt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			zt.custom_minimum_size = Vector2(130, 90)
			if not unlocked:
				zt.modulate = Color(0.35, 0.35, 0.4)
			row.add_child(zt)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label("%s · %s" % [tr(z.name), _clock(z.minutes * 60.0)], 22, Color(1.0, 0.9, 0.6) if sel else Color.WHITE))
		var dl := _label(tr(z.desc) if unlocked else tr("Needs %d colonists") % z.unlock_pop, 17, Color(0.75, 0.85, 0.95))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(dl)
		info.add_child(_label(tr("Danger: %s · Recommended power: %d") % [_danger_text(z.danger), z.power], 16, Color(1.0, 0.7, 0.6)))
		row.add_child(info)
		var b := _button(tr("Selected") if sel else tr("Select"), _open_planner.bind(dock_id, i), 56)
		b.disabled = not unlocked or sel
		b.custom_minimum_size.x = 130
		row.add_child(b)
	sheet_body.add_child(_label(tr("2. Pick up to 3 crew members"), 22, ACCENT))
	var crew := Game.available_crew()
	crew.sort_custom(func(a, b): return a.str + a.tech + a.bio > b.str + b.tech + b.bio)
	for c in crew:
		var chosen: bool = c.id in plan_crew
		var t := _button("%s%s  ·  %s %d  ♥%d" % ["✓ " if chosen else "", c.name, tr("power"), c.str + c.tech + c.bio, int(c.health)], func():
			if chosen:
				plan_crew.erase(c.id)
			elif plan_crew.size() < 3:
				plan_crew.append(c.id)
			_open_planner(dock_id, plan_zone), 58)
		t.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if chosen:
			t.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		sheet_body.add_child(t)
	var chance := Game.expedition_chance(plan_zone, plan_crew) if not plan_crew.is_empty() else 0.0
	var summary := tr("Crew power: %d / %d recommended") % [int(Game.crew_power(plan_crew)), Defs.ZONES[plan_zone].power]
	var col := Color(0.5, 1.0, 0.6) if chance >= 1.0 else (Color(1.0, 0.85, 0.4) if chance >= 0.7 else Color(1.0, 0.5, 0.5))
	sheet_body.add_child(_label(summary, 20, col))
	var left := Game.colonists.filter(func(c): return c.room != Game.ON_EXPEDITION and not c.id in plan_crew).size()
	if not plan_crew.is_empty() and left == 0:
		var wl := _label(tr("Warning: nobody will stay at the base! Rooms will stop working until the crew returns."), 18, Color(1.0, 0.5, 0.45))
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sheet_body.add_child(wl)
	var go := _button(tr("Launch the bathyscaphe!"), func():
		if plan_crew.is_empty():
			return
		if Game.launch_expedition(dock_id, plan_zone, plan_crew):
			plan_crew = []
			_close_sheet(), 80)
	go.disabled = plan_crew.is_empty()
	sheet_body.add_child(go)

func _danger_text(d: float) -> String:
	if d < 0.2: return tr("low")
	if d < 0.4: return tr("medium")
	if d < 0.6: return tr("high")
	return tr("extreme")

# ---------------------------------------------------------------- задания и сезон

func _open_tasks() -> void:
	_open_sheet("tasks", 900)
	_header(tr("Tasks"))
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 10)
	var rb := _with_icon(_button(tr("Research"), more.open_research, 64), "expedition", 36)
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if Game.research_current.is_empty() and Game.count_of("lab") > 0:
		rb.add_child(_badge())
	nav.add_child(rb)
	var ab := _with_icon(_button(tr("Achievements"), more.open_achievements, 64), "trophy", 36)
	ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if Game.achievements_ready() > 0:
		ab.add_child(_badge())
	nav.add_child(ab)
	sheet_body.add_child(nav)
	more.add_story_section()
	more.add_weekly_section()
	_section(tr("Daily tasks"))
	for q in Game.quests:
		var row := _card(Color(0.05, 0.14, 0.1, 0.9) if q.claimed else Color(0.05, 0.12, 0.2, 0.9), Color(0.5, 0.9, 0.6, 0.6) if q.progress >= q.target else Color(0.5, 0.7, 0.9, 0.4))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(_label(tr(q.text) % q.target, 22))
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(0, 14)
		pb.show_percentage = false
		pb.max_value = q.target
		pb.value = q.progress
		info.add_child(pb)
		var qrow := HBoxContainer.new()
		qrow.add_theme_constant_override("separation", 10)
		qrow.add_child(_label("%d/%d" % [q.progress, q.target], 16, Color(0.75, 0.85, 0.95)))
		qrow.add_child(_reward_chips(q.reward, 26, 16))
		qrow.add_child(_label("+%d %s" % [q.xp, tr("season XP")], 16, Color(0.75, 0.85, 0.95)))
		info.add_child(qrow)
		row.add_child(info)
		var b := _button(tr("Done") if q.claimed else tr("Claim"), func():
			Game.claim_quest(q)
			_open_tasks(), 60)
		b.disabled = q.claimed or q.progress < q.target
		b.custom_minimum_size.x = 130
		row.add_child(b)
	sheet_body.add_child(_label(tr("New tasks every day"), 16, Color(0.6, 0.7, 0.8)))

	_section(tr("Season Pass · %d days left") % Game.season_days_left())
	var tier := Game.season_tier()
	var into := Game.season_xp % Defs.SEASON_XP_PER_TIER
	var head := _label(tr("Tier %d · %d/%d XP to next") % [tier, into, Defs.SEASON_XP_PER_TIER] if tier < Defs.SEASON_TIERS.size() else tr("All tiers reached!"), 20, Color(1.0, 0.88, 0.5))
	sheet_body.add_child(head)
	var banner := _banner("season")
	if banner and not Game.season_pass:
		sheet_body.add_child(banner)
	if not Game.season_pass:
		var p := Store.product("season_pass")
		var offer := _card(Color(0.25, 0.2, 0.05, 0.92), Color(1.0, 0.8, 0.4, 0.9))
		var d := _label(tr(p.desc), 18)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		offer.add_child(d)
		var bb := _button(p.price, func():
			Store.purchase("season_pass")
			_open_tasks(), 70)
		bb.custom_minimum_size.x = 140
		offer.add_child(bb)
	var hdr := HBoxContainer.new()
	var h1 := _label(tr("Free"), 18, Color(0.8, 0.9, 1.0))
	h1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var h2 := _label(tr("Premium"), 18, Color(1.0, 0.85, 0.4))
	h2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sp := Control.new()
	sp.custom_minimum_size.x = 60
	hdr.add_child(sp)
	hdr.add_child(h1)
	hdr.add_child(h2)
	sheet_body.add_child(hdr)
	for i in Defs.SEASON_TIERS.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var num := _label(str(i + 1), 24, Color(1.0, 0.88, 0.5) if i < tier else Color(0.5, 0.6, 0.7))
		num.custom_minimum_size.x = 60
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(num)
		for prem in [false, true]:
			var claimed: bool = i in (Game.season_claimed_premium if prem else Game.season_claimed_free)
			var reached := i < tier
			var locked: bool = prem and not Game.season_pass
			var b := _button("", func():
				Game.claim_season(i, prem)
				_open_tasks(), 62)
			_reward_button(b, Defs.SEASON_TIERS[i]["premium" if prem else "free"], "✓ " if claimed else ("🔒 " if locked else ""))
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 17)
			b.disabled = claimed or not reached or locked
			if prem:
				b.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
				b.add_theme_color_override("font_disabled_color", Color(0.6, 0.5, 0.3))
			row.add_child(b)
		sheet_body.add_child(row)

func _reward_text_full(r: Dictionary) -> String:
	var t := _reward_text(r)
	if r.has("colonist"):
		t = (t + ", " if t != "" else "") + tr("%s colonist") % tr(r.colonist.capitalize())
	return t

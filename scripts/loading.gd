extends CanvasLayer
## Экран загрузки при старте: океан, логотип, полоса загрузки и подсказка.

signal done

const TIPS := [
	"Put strong colonists in the Reactor, techies in the O₂ Generator, biologists on the Farm.",
	"Tap a room when a bubble appears above it to collect resources.",
	"Drag colonists into a room with a fire, flood or monster to help.",
	"Build the same room right next to another to merge them into a bigger one.",
	"Expeditions bring pearls, crystals, gear and rare colonists.",
	"Come back every day for a bigger daily reward.",
]

var bar: ProgressBar
var progress := 0.0

func _ready() -> void:
	layer = 50
	var bg := TextureRect.new()
	bg.texture = Art.tex("res://art/backgrounds/ocean.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.03, 0.08, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var logo := TextureRect.new()
	logo.texture = Art.tex("res://art/ui/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.offset_left = -300
	logo.offset_right = 300
	logo.offset_top = 220
	logo.offset_bottom = 720
	add_child(logo)
	var dome := TextureRect.new()
	dome.texture = Art.tex("res://art/backgrounds/dome.png")
	dome.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dome.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dome.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dome.offset_left = -260
	dome.offset_right = 260
	dome.offset_top = -560
	dome.offset_bottom = -260
	add_child(dome)
	bar = ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.step = 0.001
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.offset_left = -240
	bar.offset_right = 240
	bar.offset_top = -210
	bar.offset_bottom = -186
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.55)
	st.set_corner_radius_all(12)
	st.border_color = Color(0.4, 0.9, 1.0, 0.7)
	st.set_border_width_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.78, 0.25)
	fill.set_corner_radius_all(12)
	bar.add_theme_stylebox_override("background", st)
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)
	var tip := Label.new()
	tip.text = tr(TIPS.pick_random())
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tip.offset_left = -300
	tip.offset_right = 300
	tip.offset_top = -170
	tip.offset_bottom = -80
	tip.add_theme_font_size_override("font_size", 22)
	tip.add_theme_color_override("font_color", Color(0.9, 0.97, 1.0))
	tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	tip.add_theme_constant_override("outline_size", 6)
	add_child(tip)

func _process(delta: float) -> void:
	progress = minf(1.0, progress + delta / 1.6)
	bar.value = progress
	if progress >= 1.0 and not is_queued_for_deletion():
		set_process(false)
		var tw := create_tween()
		for ch in get_children():
			tw.parallel().tween_property(ch, "modulate:a", 0.0, 0.35)
		tw.tween_callback(func():
			done.emit()
			queue_free())

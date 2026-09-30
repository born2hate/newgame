extends Node
## Собирает сцену: фон-океан, вид колонии с камерой, интерфейс.

var bg_material: ShaderMaterial
var view: Node2D
var camera: Camera2D
var hud: CanvasLayer

func _ready() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_material = ShaderMaterial.new()
	bg_material.shader = load("res://shaders/ocean.gdshader")
	bg.material = bg_material
	var ocean := Art.tex("res://art/backgrounds/ocean.png")
	if ocean:
		bg_material.set_shader_parameter("bg_tex", ocean)
		bg_material.set_shader_parameter("use_tex", true)
	bg_layer.add_child(bg)

	view = preload("res://scripts/base_view.gd").new()
	add_child(view)
	camera = Camera2D.new()
	camera.position = Vector2(400, 200)
	camera.zoom = Vector2(1.2, 1.2)
	view.add_child(camera)
	view.camera = camera

	hud = preload("res://scripts/hud.gd").new()
	hud.view = view
	add_child(hud)
	_dev_screenshot()

## Для разработки: godot -- --screenshot=out.png [--scene=build|room|colonists]
func _dev_screenshot() -> void:
	var path := ""
	var scene := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--screenshot="):
			path = a.trim_prefix("--screenshot=")
		elif a.begins_with("--scene="):
			scene = a.trim_prefix("--scene=")
	if path == "":
		return
	await get_tree().create_timer(1.5).timeout
	match scene:
		"build": hud._open_build()
		"buildmode": hud._start_build("living")
		"room": view.room_selected.emit(Game.find_room_of_type("reactor").id)
		"colonists": hud._open_colonists()
		"shop": hud._open_shop()
		"tasks": hud._open_tasks()
		"bar": hud._close_sheet()
		"captain":
			hud._close_sheet()
			Store.purchase("premium")
			var cap: Dictionary = Game.colonists[-1]
			Game.assign(cap, Game.find_room_of_type("reactor"))
			var d := Game._add_room("dock", 3, 1)
			hud.popup_bg.visible = false
		"planner":
			var d := Game._add_room("dock", 3, 1)
			hud._open_planner(d.id, 1)
		"expedition":
			var d := Game._add_room("dock", 3, 1)
			Game.launch_expedition(d.id, 1, [Game.colonists[3].id, Game.colonists[0].id])
			var e := Game.expedition_at(d.id)
			e.start = Game.now() - 1100.0
			e.end = Game.now() + 700.0
			view.room_selected.emit(d.id)
		"pet":
			hud._close_sheet()
			Store.purchase("starter_pack")
			hud.popup_bg.visible = false
		"shop1":
			hud._open_shop()
			await get_tree().process_frame
			(hud.sheet.get_child(0) as ScrollContainer).scroll_vertical = 480
		"shop2":
			hud._open_shop()
			await get_tree().process_frame
			var sc := hud.sheet.get_child(0) as ScrollContainer
			sc.scroll_vertical = 1100
		"daily": hud._open_daily()
		"crate":
			Game.crates.silver = 1
			Game.open_crate("silver")
		"deep": camera.position.y = 700
		"zoom":
			camera.zoom = Vector2(1.5, 1.5)
			camera.position = Vector2(200, 120)
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()

func _process(_delta: float) -> void:
	var depth := clampf(camera.position.y / (base_view_cell_h() * 12.0), 0.0, 1.0)
	bg_material.set_shader_parameter("depth", depth)
	bg_material.set_shader_parameter("cam_offset", camera.position)

func base_view_cell_h() -> float:
	return 130.0

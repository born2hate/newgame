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
	bg_layer.add_child(bg)

	view = preload("res://scripts/base_view.gd").new()
	add_child(view)
	camera = Camera2D.new()
	camera.position = Vector2(400, 180)
	camera.zoom = Vector2(0.85, 0.85)
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
		"deep": camera.position.y = 700
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()

func _process(_delta: float) -> void:
	var depth := clampf(camera.position.y / (base_view_cell_h() * 12.0), 0.0, 1.0)
	bg_material.set_shader_parameter("depth", depth)
	bg_material.set_shader_parameter("cam_offset", camera.position)

func base_view_cell_h() -> float:
	return 130.0

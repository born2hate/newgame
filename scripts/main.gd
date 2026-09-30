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
	if scene != "mode":
		Game.mode_chosen = true
	if not scene.begins_with("tut"):
		Game.tutorial_done = true
		if hud.tutorial and is_instance_valid(hud.tutorial):
			hud.tutorial.queue_free()
	await get_tree().create_timer(1.5).timeout
	if not scene.begins_with("tut") and hud.tutorial and is_instance_valid(hud.tutorial):
		hud.tutorial.queue_free()
	if scene != "mode" and hud.sheet_kind == "mode":
		hud._close_sheet()
	if scene.begins_with("tut"):
		hud.start_tutorial()
		await get_tree().create_timer(0.6).timeout
	if not scene.begins_with("tut") and hud.sheet_kind == "daily" and scene != "daily":
		hud._close_sheet()
	match scene:
		"build": hud._open_build()
		"buildmode":
			camera.position = Vector2(400, 900)
			hud._start_build("living")
			await get_tree().create_timer(0.6).timeout
		"room": view.room_selected.emit(Game.find_room_of_type("reactor").id)
		"colonists": hud._open_colonists()
		"shop": hud._open_shop()
		"tasks": hud._open_tasks()
		"tasks_ru":
			Audio.set_language("ru")
			hud._open_tasks()
		"tasks_ru2":
			Audio.set_language("ru")
			hud._open_tasks()
			await get_tree().process_frame
			(hud.sheet.get_child(0) as ScrollContainer).scroll_vertical = 900
		"tasks_ru3":
			Audio.set_language("ru")
			hud._open_tasks()
			await get_tree().process_frame
			(hud.sheet.get_child(0) as ScrollContainer).scroll_vertical = 2000
		"research_ru":
			Audio.set_language("ru")
			hud.more.open_research()
		"planner_ru":
			Audio.set_language("ru")
			var dk := Game._add_room("dock", 3, 1)
			hud._open_planner(dk.id, 1)
		"shop_ru":
			Audio.set_language("ru")
			hud._open_shop()
		"colonist_ru":
			Audio.set_language("ru")
			hud._open_colonist(Game.colonists[0].id)
		"room_ru":
			Audio.set_language("ru")
			view.room_selected.emit(Game.find_room_of_type("reactor").id)
		"banner":
			Game.track(Game.quests[0].event, 999)
			await get_tree().create_timer(0.7).timeout
		"scrolltest":
			hud._open_build()
			await get_tree().create_timer(0.5).timeout
			var sc := hud.sheet.get_child(0) as ScrollContainer
			var before := sc.scroll_vertical
			var start := Vector2(360, 1000)
			var ev := InputEventScreenTouch.new()
			ev.index = 0
			ev.position = start
			ev.pressed = true
			Input.parse_input_event(ev)
			for i in 20:
				await get_tree().process_frame
				var d := InputEventScreenDrag.new()
				d.index = 0
				d.position = start - Vector2(0, (i + 1) * 20)
				d.relative = Vector2(0, -20)
				Input.parse_input_event(d)
			var up := InputEventScreenTouch.new()
			up.index = 0
			up.position = start - Vector2(0, 400)
			up.pressed = false
			Input.parse_input_event(up)
			await get_tree().create_timer(0.5).timeout
			print("SCROLL before=%d after=%d build_type=%s" % [before, sc.scroll_vertical, view.build_type])
		"mode":
			hud._close_sheet()
			hud.open_mode_picker()
		"tut1": pass
		"tut_top":
			hud.root.offset_top = 90
			hud.tutorial._show(2)
		"tut_card":
			hud._open_build()
			hud.tutorial._show(4)
		"tut_slot":
			hud.tutorial._show(5)
			hud._start_build("living")
			await get_tree().create_timer(0.6).timeout
		"tut_reactor":
			hud.tutorial._show(1)
		"tut2":
			await get_tree().create_timer(4.0).timeout
			Game.collect(Game.find_room_of_type("reactor"))
			await get_tree().create_timer(0.3).timeout
		"tut3":
			hud.tutorial._show(6)
		"research":
			Game.science = 180
			Game.research_done = ["efficient_reactors", "hydroponics"]
			Game.research_current = {"id": "electrolysis", "start": Game.now() - 60, "end": Game.now() + 60}
			hud.more.open_research()
		"achievements":
			Game.stats["build"] = 6
			hud.more.open_achievements()
		"trader":
			Game._spawn_trader()
			hud._close_sheet()
			await get_tree().create_timer(0.5).timeout
			hud.more.open_trader()
		"trader_ru":
			Audio.set_language("ru")
			Game._spawn_trader()
			await get_tree().create_timer(0.3).timeout
			hud.more.open_trader()
		"trader_btn":
			Audio.set_language("ru")
			Game._spawn_trader()
			await get_tree().create_timer(0.8).timeout
		"gear":
			Game.add_item("rare", "torch")
			Game.add_item("legendary", "explorer_suit")
			Game.equip(Game.colonists[0], Game.items[1].uid)
			Game.equip(Game.colonists[0], Game.add_item("legendary", "diving_armor").uid)
			hud._open_colonist(Game.colonists[0].id)
		"deep":
			Game.pearls = 5000
			Game.research_done = ["deep_drilling"]
			for r in range(2, 7):
				Game.build("elevator", 5, r)
			Game.build("farm", 3, 1)
			Game.build("farm", 1, 1)
			Game.build("reactor", 6, 5)
			hud._close_sheet()
			view.treasure.append({"p": Vector2(200, 300), "rich": false, "ph": 0.0})
			view.treasure.append({"p": Vector2(560, 500), "rich": true, "ph": 1.0})
			Game._spawn_trader()
			camera.zoom = Vector2(0.7, 0.7)
			camera.position = Vector2(400, 420)
		"settings": hud._open_settings()
		"settings_de":
			Audio.set_language("de")
			hud._open_settings()
		"tasks_es":
			Audio.set_language("es")
			hud._open_tasks()
		"settings_ru":
			Audio.set_language("ru")
			hud._open_settings()
		"colonist":
			hud._close_sheet()
			hud._open_colonist(Game.colonists[0].id)
		"fire":
			hud._close_sheet()
			Game.start_hazard(Game.find_room_of_type("reactor"), "fire")
			Game.start_hazard(Game.find_room_of_type("farm"), "flood", 70.0)
			Game.start_hazard(Game.find_room_of_type("oxygen"), "creature")
			Game.send_help(Game.colonists[3], Game.find_room_of_type("reactor"))
			await get_tree().create_timer(1.5).timeout
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
		"work":
			camera.zoom = Vector2(1.8, 1.8)
			camera.position = Vector2(620, 300)
			Game.assign(Game.colonists[3], Game.find_room_of_type("farm"))
			Game.find_room_of_type("farm").level = 3
			Game.assign(Game.colonists[1], Game.find_room_of_type("farm"))
			await get_tree().create_timer(6.0).timeout
		"fight":
			hud._close_sheet()
			camera.zoom = Vector2(1.7, 1.7)
			camera.position = Vector2(560, 230)
			Game.add_item("rare", "harpoon")
			Game.equip(Game.colonists[1], Game.items[-1].uid)
			Game.start_hazard(Game.find_room_of_type("oxygen"), "creature")
			Game.send_help(Game.colonists[3], Game.find_room_of_type("oxygen"))
			Game.start_hazard(Game.find_room_of_type("farm"), "fire")
			Game.send_help(Game.colonists[0], Game.find_room_of_type("farm"))
			await get_tree().create_timer(2.5).timeout
		"wide":
			camera.zoom = Vector2(0.5, 0.5)
			camera.position = Vector2(700, 300)
			hud._start_build("farm")
			await get_tree().create_timer(0.6).timeout
			camera.zoom = Vector2(0.5, 0.5)
			camera.position = Vector2(700, 300)
		"outside":
			Audio.set_language("ru")
			view.room_selected.emit(Game.find_room_of_type("airlock").id)
		"drag":
			camera.zoom = Vector2(1.2, 1.2)
			camera.position = Vector2(450, 250)
			view.drag_colonist = Game.colonists[3].id
			view.drag_pos = Vector2(620, 180)
			await get_tree().create_timer(0.3).timeout
		"zoom3d":
			camera.zoom = Vector2(2.0, 2.0)
			camera.position = Vector2(560, 150)
		"lab":
			Game.pearls = 5000
			Game.build("elevator", 5, 2)
			Game.build("lab", 6, 2)
			Game.find_room_of_type("lab").progress = 0.6
			Game.build("dock", 3, 1)
			Game.build("storage", 3, 2)
			camera.position = Vector2(400, 330)
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

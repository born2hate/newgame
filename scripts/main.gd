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
	var uargs := Array(OS.get_cmdline_user_args())
	var dev: bool = "--selftest" in uargs or uargs.any(func(a): return str(a).begins_with("--screenshot"))
	if not dev or "--scene=loading" in uargs:
		var ld = preload("res://scripts/loading.gd").new()
		add_child(ld)
	_dev_screenshot()
	_dev_selftest()

func _dev_selftest() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--selftest" in args:
		return
	for a in args:
		if a.begins_with("--lang="):
			Audio.set_language(a.trim_prefix("--lang="))
	var st = preload("res://scripts/selftest.gd").new()
	st.main = self
	st.hud = hud
	st.view = view
	add_child(st)
	st.run()

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
	for a2 in OS.get_cmdline_user_args():
		if a2.begins_with("--force-lang="):
			Audio.forced_lang = a2.trim_prefix("--force-lang=")
			Audio.set_language(Audio.forced_lang)
	if scene != "mode":
		Game.mode_chosen = true
	if not scene.begins_with("tut"):
		Game.tutorial_done = true
		if hud.tutorial and is_instance_valid(hud.tutorial):
			hud.tutorial.queue_free()
	if scene == "loading":
		Audio.set_language("ru")
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png(path)
		get_tree().quit()
		return
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
		"hazards":
			var fr := Game.find_room_of_type("farm")
			Game.start_hazard(fr, "fire")
			var ox := Game.find_room_of_type("oxygen")
			Game.start_hazard(ox, "flood")
			camera.position = Vector2(700, 300)
			view.treasure.append({"p": Vector2(500, -150), "rich": false, "ph": 0.0})
			await get_tree().create_timer(0.8).timeout
		"deck":
			Game.find_room_of_type("living").level = 3
			Game._add_room("observatory", 7, 1)
			camera.position = Vector2(700, 300)
			await get_tree().create_timer(0.5).timeout
		"gym_ru":
			Audio.set_language("ru")
			var gy := Game._add_room("gym", 7, 1)
			Game.colonists[0].room = gy.id
			Game.colonists[1].room = gy.id
			view.room_selected.emit(gy.id)
		"build2_ru":
			Audio.set_language("ru")
			hud._open_build()
			await get_tree().process_frame
			(hud.sheet.get_child(0) as ScrollContainer).scroll_vertical = 1400
		"room_ru":
			Audio.set_language("ru")
			view.room_selected.emit(Game.find_room_of_type("reactor").id)
		"banner":
			Game.track(Game.quests[0].event, 999)
			await get_tree().create_timer(0.7).timeout
		"closetest":
			hud._open_build()
			await get_tree().create_timer(0.5).timeout
			var xbtn: Button = hud.sheet_body.get_child(0).get_child(1)
			var pos := xbtn.get_global_rect().get_center()
			var e1 := InputEventScreenTouch.new(); e1.index = 0; e1.position = pos; e1.pressed = true
			Input.parse_input_event(e1)
			await get_tree().process_frame
			var d := InputEventScreenDrag.new(); d.index = 0; d.position = pos + Vector2(3, 4); d.relative = Vector2(3, 4)
			Input.parse_input_event(d)
			await get_tree().process_frame
			var e2 := InputEventScreenTouch.new(); e2.index = 0; e2.position = pos + Vector2(3, 4); e2.pressed = false
			Input.parse_input_event(e2)
			await get_tree().create_timer(0.3).timeout
			print("CLOSE visible_after=", hud.sheet.visible)
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
			hud.tutorial._show(5)
		"tut_card":
			hud._open_build()
			hud.tutorial._show(2)
		"tut_slot":
			hud.tutorial._show(3)
			hud._start_build("living")
			await get_tree().create_timer(0.6).timeout
		"tut_reactor":
			hud.tutorial._show(0)
		"tut2":
			await get_tree().create_timer(4.0).timeout
			Game.collect(Game.find_room_of_type("reactor"))
			await get_tree().create_timer(0.3).timeout
		"tut3":
			hud.tutorial._show(4)
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
		"bounds":
			camera.zoom = Vector2(0.45, 0.45)
			camera.position = Vector2(1600, 200)
			hud._start_build("living")
			await get_tree().create_timer(0.6).timeout
		"fallen_ru":
			Audio.set_language("ru")
			Game.set_difficulty("normal")
			Game.colonists[1].health = 0.0
			Game._check_deaths()
			camera.position = Vector2(600, 250)
			await get_tree().create_timer(0.3).timeout
			hud._close_sheet()
			hud.open_fallen(0)
		"raid_ru":
			Audio.set_language("ru")
			Game.find_room_of_type("airlock").level = 2
			Game.start_raid()
			Game.raid.door = 0.0
			Game.send_help(Game.colonists[0], Game.find_room_of_type("airlock"))
			camera.position = Vector2(450, 150)
			await get_tree().create_timer(1.5).timeout
		"raider_bodies":
			var alr := Game.find_room_of_type("airlock")
			for i in 2:
				Game.raider_bodies.append({"room": alr.id, "x": 0.5 + 0.3 * i, "kind": i, "tier": 1, "until": Game.now() + 600.0, "id": 900 + i})
			camera.position = Vector2(450, 150)
			await get_tree().create_timer(0.5).timeout
		"family_ru":
			Audio.set_language("ru")
			var home := Game._add_room("living", 7, 1)
			Game.colonists[2].room = home.id
			Game.colonists[3].room = home.id
			home.progress = 0.6
			var kid := Game._make_colonist()
			kid["child"] = true
			kid["grow"] = 15000.0
			kid.room = home.id
			Game.colonists.append(kid)
			for r in Game.rooms:
				if Defs.ROOMS[r.type].has("produces"):
					r.ready = true
			camera.position = Vector2(600, 260)
			await get_tree().create_timer(0.3).timeout
			for r in Game.rooms:
				if r.ready:
					Game.collect(r)
					await get_tree().create_timer(0.15).timeout
			await get_tree().create_timer(0.3).timeout
		"persp":
			camera.position = Vector2(300, -150)
			camera.zoom = Vector2(1.6, 1.6)
			await get_tree().create_timer(0.3).timeout
		"persp2":
			camera.position = Vector2(900, 500)
			camera.zoom = Vector2(1.6, 1.6)
			await get_tree().create_timer(0.3).timeout
		"boss_ru":
			Audio.set_language("ru")
			while Game.colonists.size() < 20:
				Game.colonists.append(Game._make_colonist())
			Game.start_boss()
			Game.boss.hp = Game.boss.max * 0.6
			camera.position = Vector2(700, -250)
			camera.zoom = Vector2(0.8, 0.8)
			await get_tree().create_timer(0.8).timeout
		"choice_ru":
			Audio.set_language("ru")
			var dkc := Game._add_room("dock", 3, 1)
			Game.launch_expedition(dkc.id, 1, [Game.colonists[3].id])
			var ec := Game.expedition_at(dkc.id)
			ec.start = Game.now() - 1000.0
			ec.end = Game.now() + 800.0
			ec["choice"] = {"id": "stranger", "at": 0.2, "pick": ""}
			view.room_selected.emit(dkc.id)
			await get_tree().create_timer(0.6).timeout
		"pets_ru":
			Audio.set_language("ru")
			Game.grant_pet("puffer")
			Game.grant_pet("lion")
			Game.grant_pet("angel")
			hud.open_pets()
		"weapons_ru":
			Audio.set_language("ru")
			var cw: Dictionary = Game.colonists[0]
			Game.equip(cw, Game.add_item("legendary", "trident").uid)
			Game.equip(cw, Game.add_item("rare", "titan_suit").uid)
			hud._open_colonist(cw.id)
			await get_tree().process_frame
			(hud.sheet.get_child(0) as ScrollContainer).scroll_vertical = 700
		"rest":
			var home := Game._add_room("living", 7, 1)
			Game.colonists[2].room = home.id
			Game.colonists[3].room = home.id
			Game.colonists[2].suit = 3
			Game.colonists[3].suit = 2
			camera.position = Vector2(780, 220)
			camera.zoom = Vector2(1.8, 1.8)
			await get_tree().create_timer(0.6).timeout
		"deep_ru":
			Audio.set_language("ru")
			hud.more.open_research(Game.next_depth_research())
			await get_tree().create_timer(0.5).timeout
		"creature_ru":
			Audio.set_language("ru")
			Game.start_hazard(Game.find_room_of_type("farm"), "creature")
			Game.start_hazard(Game.find_room_of_type("oxygen"), "creature")
			camera.position = Vector2(700, 200)
			camera.zoom = Vector2(1.3, 1.3)
			await get_tree().create_timer(0.8).timeout
		"creature_far":
			Audio.set_language("ru")
			Game.start_hazard(Game.find_room_of_type("farm"), "creature")
			Game.start_hazard(Game.find_room_of_type("oxygen"), "fire")
			camera.position = Vector2(700, 300)
			camera.zoom = Vector2(0.5, 0.5)
			await get_tree().create_timer(0.8).timeout
		"stats":
			Game.stats.merge({"build": 23, "upgrade": 11, "collect": 812, "collect_pearls": 9450, "birth": 4, "level_up": 57, "incident_resolved": 19, "raid_won": 3, "boss_won": 1, "expedition_done": 14, "research": 6, "craft": 2, "crate": 9, "deaths": 2, "revive": 1, "max_pop": 27, "founded": Game.today() - 5}, true)
			Game.colony_level = 8
			hud.open_stats()
		"notify_plan":
			var dkn := Game._add_room("dock", 3, 1)
			Game.launch_expedition(dkn.id, 1, [Game.colonists[3].id])
			for n in Notifier.plan():
				print("NOTIFY in %ds: %s — %s" % [int(n[0]), n[1], n[2]])
			hud._open_settings()
		"expedition_ru":
			Audio.set_language("ru")
			var d2 := Game._add_room("dock", 3, 1)
			Game.launch_expedition(d2.id, 2, [Game.colonists[3].id, Game.colonists[0].id])
			var e2 := Game.expedition_at(d2.id)
			e2.start = Game.now() - 2900.0
			e2.end = Game.now() + 700.0
			view.room_selected.emit(d2.id)
			await get_tree().create_timer(0.4).timeout
			(hud.sheet.get_child(0) as ScrollContainer).scroll_vertical = 300
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
		"expbtn":
			Audio.set_language("ru")
			hud._close_sheet()
			var dk := Game._add_room("dock", 3, 1)
			Game.launch_expedition(dk.id, 0, [Game.colonists[0].id])
			await get_tree().create_timer(0.5).timeout
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
		"plan_explore_ru":
			Audio.set_language("ru")
			var dkp := Game._add_room("dock", 3, 1)
			hud.plan_mode = "explore"
			hud.plan_crew = [Game.colonists[0].id, Game.colonists[1].id]
			hud._open_planner(dkp.id, 1)
			await get_tree().process_frame
			(hud.sheet.get_child(0) as ScrollContainer).scroll_vertical = 600
		"exploring_ru":
			Audio.set_language("ru")
			var dkx := Game._add_room("dock", 3, 1)
			Game.launch_exploration(dkx.id, 2, [Game.colonists[0].id, Game.colonists[3].id], true)
			Game.clock_offset += 5400.0
			Game._tick_explorations()
			view.room_selected.emit(dkx.id)
			await get_tree().create_timer(0.4).timeout
			(hud.sheet.get_child(0) as ScrollContainer).scroll_vertical = 250
		"store_base":
			_showcase()
		"store_boss":
			_showcase()
			Game.start_boss()
			Game.boss.hp = Game.boss.max * 0.55
			camera.position = Vector2(600, -120)
			await get_tree().create_timer(0.8).timeout
		"store_raid":
			_showcase()
			Game.find_room_of_type("airlock").level = 2
			Game.start_raid()
			Game.raid.door = 0.0
			Game.send_help(Game.colonists[0], Game.find_room_of_type("airlock"))
			camera.zoom = Vector2(1.0, 1.0)
			camera.position = Vector2(460, 260)
			await get_tree().create_timer(1.5).timeout
		"store_fire":
			_showcase()
			Game.start_hazard(Game.find_room_of_type("kitchen"), "fire")
			Game.start_hazard(Game.find_room_of_type("gym"), "creature")
			Game.start_hazard(Game.find_room_of_type("oxygen"), "flood")
			camera.zoom = Vector2(1.0, 1.0)
			camera.position = Vector2(460, 300)
			await get_tree().create_timer(0.8).timeout
		"store_exp":
			_showcase()
			var dks := Game.find_room_of_type("dock")
			Game.launch_expedition(dks.id, 2, [Game.colonists[3].id, Game.colonists[0].id])
			var es := Game.expedition_at(dks.id)
			es.start = Game.now() - 2900.0
			es.end = Game.now() + 700.0
			view.room_selected.emit(dks.id)
			await get_tree().create_timer(0.4).timeout
			(hud.sheet.get_child(0) as ScrollContainer).scroll_vertical = 300
		"store_gear":
			_showcase()
			var cg: Dictionary = Game.colonists[0]
			Game.equip(cg, Game.add_item("legendary", "trident").uid)
			Game.equip(cg, Game.add_item("rare", "titan_suit").uid)
			cg.level = 14
			hud._open_colonist(cg.id)
		"store_family":
			_showcase()
			var homes := Game.rooms.filter(func(r): return r.type == "living")
			for h in homes:
				h.progress = 0.6
			var kid2 := Game._make_colonist()
			kid2["child"] = true
			kid2["grow"] = 15000.0
			kid2.room = homes[0].id
			Game.colonists.append(kid2)
			camera.zoom = Vector2(1.2, 1.2)
			camera.position = Vector2(560, 250)
			await get_tree().create_timer(0.6).timeout
		"store_pets":
			_showcase()
			Game.grant_pet("puffer")
			Game.grant_pet("lion")
			Game.grant_pet("angel")
			Game.grant_pet("clownfish")
			hud.open_pets()
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()

## Витрина для скриншотов магазина: развитая колония на 8 этажей.
func _showcase() -> void:
	hud._close_sheet()
	Game.research_done.append("deep_drilling")
	Game.colony_level = 14
	Game.pearls = 18450
	Game.crystals = 320
	Game.science = 460
	Game.rooms.clear()
	Game.colonists.clear()
	var layout := [
		["reactor", 1, 0], ["airlock", 3, 0], ["elevator", 5, 0], ["oxygen", 6, 0], ["lab", 8, 0], ["storage", 10, 0],
		["living", 1, 1], ["kitchen", 3, 1], ["elevator", 5, 1], ["farm", 6, 1], ["pearl", 8, 1], ["dock", 10, 1],
		["medbay", 1, 2], ["gym", 3, 2], ["elevator", 5, 2], ["living", 6, 2], ["school", 10, 2],
		["radio", 1, 3], ["workshop", 3, 3], ["elevator", 5, 3], ["reactor", 6, 3], ["medbay", 8, 3], ["armory", 10, 3],
		["lounge", 1, 4], ["aquarium", 3, 4], ["elevator", 5, 4], ["farm", 6, 4], ["oxygen", 8, 4], ["pearl", 10, 4],
		["observatory", 1, 5], ["living", 3, 5], ["elevator", 5, 5], ["turbine", 6, 5], ["lab", 8, 5], ["kitchen", 10, 5],
		["oxygen", 3, 6], ["elevator", 5, 6], ["farm", 6, 6], ["reactor", 8, 6], ["workshop", 10, 6],
		["living", 3, 7], ["elevator", 5, 7], ["pearl", 6, 7], ["storage", 8, 7],
	]
	var lv := [3, 5, 2, 4, 3, 2, 5, 4, 3, 1, 4, 2]
	for i in layout.size():
		var r := Game._add_room(layout[i][0], layout[i][1], layout[i][2])
		if Defs.ROOMS[r.type].get("buildable", false) and r.type != "elevator":
			r.level = lv[i % lv.size()]
		r.progress = fmod(i * 0.37, 1.0)
	Game.get_room(Game.rooms[15].id)["size"] = 2
	for r in Game.rooms:
		if r.type == "elevator":
			continue
		var n := mini(Game.slots(r), 2) if r.type != "living" else 2
		for k in n:
			var c := Game._make_colonist()
			c.level = 3 + (c.id % 9)
			Game.colonists.append(c)
			c.room = r.id
	for i in Game.rooms.size():
		if Defs.ROOMS[Game.rooms[i].type].has("produces") and i % 3 == 0:
			Game.rooms[i].ready = true
	Game.resources.energy = 92.0
	Game.resources.oxygen = 88.0
	Game.resources.food = 95.0
	Game.changed.emit()
	camera.zoom = Vector2(0.62, 0.62)
	camera.position = Vector2(640, 380)

func _process(_delta: float) -> void:
	var depth := clampf(camera.position.y / (base_view_cell_h() * 12.0), 0.0, 1.0)
	bg_material.set_shader_parameter("depth", depth)
	bg_material.set_shader_parameter("cam_offset", camera.position)

func base_view_cell_h() -> float:
	return 130.0

extends Node
## Автопроверка интерфейса настоящими касаниями. Запуск: godot -- --selftest [--lang=ru]
## Печатает строки «ISSUE: ...» и итог «SELFTEST: N issues».

var main: Node
var hud
var view
var issues := 0

func issue(msg: String) -> void:
	issues += 1
	print("ISSUE: ", msg)

func wait(sec := 0.25) -> void:
	await get_tree().create_timer(sec).timeout

func tap(pos: Vector2, jitter := Vector2(2, 3)) -> void:
	var a := InputEventScreenTouch.new()
	a.index = 0; a.position = pos; a.pressed = true
	Input.parse_input_event(a)
	await get_tree().process_frame
	var d := InputEventScreenDrag.new()
	d.index = 0; d.position = pos + jitter; d.relative = jitter
	Input.parse_input_event(d)
	await get_tree().process_frame
	var b := InputEventScreenTouch.new()
	b.index = 0; b.position = pos + jitter; b.pressed = false
	Input.parse_input_event(b)
	await wait(0.2)

func drag(from: Vector2, to: Vector2) -> void:
	var a := InputEventScreenTouch.new()
	a.index = 0; a.position = from; a.pressed = true
	Input.parse_input_event(a)
	await get_tree().process_frame
	for i in 16:
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = from.lerp(to, (i + 1) / 16.0)
		d.relative = (to - from) / 16.0
		Input.parse_input_event(d)
		await get_tree().process_frame
	var b := InputEventScreenTouch.new()
	b.index = 0; b.position = to; b.pressed = false
	Input.parse_input_event(b)
	await wait(0.3)

func world_to_screen(p: Vector2) -> Vector2:
	return view.get_viewport().get_canvas_transform() * p

func room_screen(type: String) -> Vector2:
	var r: Dictionary = Game.find_room_of_type(type)
	return world_to_screen(view.room_rect(r).get_center())

func find_button(root: Node, text: String) -> Button:
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and (b.text == text or (b.has_meta("cost_box") and text in (b.get_meta("cost_box") as HBoxContainer).get_child(0).text)):
			return b
	return null

func press(b: Button, what: String) -> bool:
	if b == null:
		issue("button not found: " + what)
		return false
	await tap(b.get_global_rect().get_center())
	return true

## Проверка открытой панели: ничего не вылезает за её края.
func check_sheet(name: String) -> void:
	await wait(0.35)
	if not hud.sheet.visible:
		issue(name + ": sheet not visible")
		return
	var sr: Rect2 = hud.sheet.get_global_rect()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if sr.position.x < -1 or sr.end.x > vp.x + 1:
		issue("%s: sheet outside screen %s" % [name, sr])
	for n in hud.sheet.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or c is ScrollBar:
			continue
		var r := c.get_global_rect()
		if c is Label and (c as Label).text.length() > 4 and r.size.x < 30 and r.size.y > 60:
			issue("%s: text broken into a column: %s" % [name, (c as Label).text.left(30)])
		if r.size.x < 2:
			continue
		if r.end.x > sr.end.x + 2 or r.position.x < sr.position.x - 2:
			var t: String = c.text if "text" in c else c.get_class()
			issue("%s: '%s' sticks out (%d..%d of %d..%d)" % [name, t.left(40), r.position.x, r.end.x, sr.position.x, sr.end.x])
			return

func close_sheet(name: String) -> void:
	var x := find_button(hud.sheet, "✕")
	if x == null:
		issue(name + ": no close button")
		hud._close_sheet()
		return
	await tap(x.get_global_rect().get_center())
	if hud.sheet.visible:
		issue(name + ": close button did not close")
		hud._close_sheet()

func run() -> void:
	await wait(1.0)
	# 1. выбор режима
	if hud.sheet_kind == "mode":
		await press(find_button(hud.sheet, tr("Select")), "mode select")
	await wait(0.8)
	var tut = hud.tutorial
	if tut == null or not is_instance_valid(tut):
		issue("tutorial did not start")
	else:
		# шаг 0: далее
		await press(find_button(tut, tr("Next")), "tutorial next 0")
		# шаг 1: реактор готов — нажать на него
		var e0: float = Game.resources.energy
		await tap(room_screen("reactor"))
		if Game.resources.energy <= e0:
			issue("tutorial: tap on reactor did not collect")
		await wait(0.4)
		await press(find_button(tut, tr("Next")), "tutorial next 2")
		# шаг 3: кнопка «Стройка»
		await tap(hud.bottom_bar.get_child(0).get_global_rect().get_center())
		if hud.sheet_kind != "build":
			issue("tutorial: build sheet did not open")
		await wait(0.4)
		# шаг 4: жилой отсек
		var card: Control = hud.build_cards.get("living")
		if card:
			var btn: Button = card.find_children("*", "Button", true, false)[0]
			await tap(btn.get_global_rect().get_center())
		if view.build_type != "living":
			issue("tutorial: build mode not started")
		await wait(0.7)
		# шаг 5: зелёное место
		var spots := Game.build_spots("living")
		var n_rooms := Game.rooms.size()
		if not spots.is_empty():
			var cell: Vector2i = spots[0]
			await tap(world_to_screen(Vector2((cell.x + 1) * view.CELL_W, (cell.y + 0.5) * view.CELL_H)))
		if Game.rooms.size() <= n_rooms and Game.count_of("living") == 0:
			issue("tutorial: tap on slot did not build")
		await wait(0.5)
		# шаг 6: перетащить свободного колониста в ферму
		var idle := {}
		for c in Game.colonists:
			if c.room == -1:
				idle = c
		if idle.is_empty():
			issue("no idle colonist for drag step")
		else:
			var from := world_to_screen(view.colonist_world_pos(idle) + Vector2(0, -28))
			var farm: Dictionary = Game.find_room_of_type("farm")
			for r in Game.rooms:
				if r.type in ["farm", "oxygen", "reactor"] and Game.workers_in(r).size() < Game.slots(r):
					farm = r
			await drag(from, world_to_screen(view.room_rect(farm).get_center()))
			if idle.room == -1:
				issue("drag colonist into room did not assign")
		await wait(0.4)
		# шаг 7: нажать на колониста
		var cc: Dictionary = Game.colonists[0]
		await tap(world_to_screen(view.colonist_world_pos(cc) + Vector2(0, -28)), Vector2.ZERO)
		if hud.sheet_kind != "colonist":
			issue("tap on colonist did not open card (" + hud.sheet_kind + ")")
		await wait(0.4)
		await close_sheet("colonist card")
		if is_instance_valid(tut):
			tut.finish()
	await wait(0.5)
	# 2. все меню: открыть, проверить края, закрыть крестиком
	Game.pearls = 5000
	Game.crystals = 500
	Game.science = 500
	var dock: Dictionary = Game._add_room("dock", 3, 2) if Game.find_room_of_type("dock").is_empty() else Game.find_room_of_type("dock")
	Game._spawn_trader()
	await wait(0.4)
	var screens := [
		["build", func(): hud._open_build()],
		["crew", func(): hud._open_colonists()],
		["tasks", func(): hud._open_tasks()],
		["shop", func(): hud._open_shop()],
		["settings", func(): hud._open_settings()],
		["daily", func(): hud._open_daily()],
		["research", func(): hud.more.open_research()],
		["achievements", func(): hud.more.open_achievements()],
		["trader", func(): hud.more.open_trader()],
		["room reactor", func(): hud._open_room(Game.find_room_of_type("reactor").id)],
		["room airlock", func(): hud._open_room(Game.find_room_of_type("airlock").id)],
		["room dock", func(): hud._open_room(dock.id)],
		["planner", func(): hud._open_planner(dock.id, 0)],
		["colonist", func(): hud._open_colonist(Game.colonists[1].id)],
		["gear", func(): hud.more.open_gear_picker(Game.colonists[1].id, "armor")],
		["mode", func(): hud.open_mode_picker()],
	]
	for sc in screens:
		sc[1].call()
		await check_sheet(sc[0])
		if sc[0] == "mode":
			hud._close_sheet()
			continue
		# прокрутить вниз и проверить ещё раз
		var scroll := hud.sheet.get_child(0) as ScrollContainer
		scroll.scroll_vertical = 100000
		await wait(0.2)
		await check_sheet(sc[0] + " (bottom)")
		scroll.scroll_vertical = 0
		await wait(0.1)
		await close_sheet(sc[0])
	# 3. нижние кнопки открывают свои меню
	for i in 4:
		await tap(hud.bottom_bar.get_child(i).get_global_rect().get_center())
		if not hud.sheet.visible:
			issue("bottom button %d did not open a sheet" % i)
		hud._close_sheet()
		await wait(0.2)
	# 4. экспедиция через интерфейс
	hud._open_planner(dock.id, 0)
	await wait(0.4)
	var crew_btns: Array = hud.sheet.find_children("*", "Button", true, false).filter(func(b): return tr("power") in b.text)
	if crew_btns.is_empty():
		issue("planner: no crew buttons")
	else:
		var sc0 := hud.sheet.get_child(0) as ScrollContainer
		sc0.ensure_control_visible(crew_btns[0])
		await wait(0.2)
		var before: int = sc0.scroll_vertical
		await tap(crew_btns[0].get_global_rect().get_center())
		await wait(0.2)
		if absi(sc0.scroll_vertical - before) > 30:
			issue("planner: list jumped to top after picking crew")
		await wait(0.3)
		var go := find_button(hud.sheet, tr("Launch the bathyscaphe!"))
		if go:
			var sc := hud.sheet.get_child(0) as ScrollContainer
			sc.scroll_vertical = 100000
			await wait(0.2)
			go = find_button(hud.sheet, tr("Launch the bathyscaphe!"))
			await tap(go.get_global_rect().get_center())
		if Game.expedition_at(dock.id).is_empty():
			issue("planner: expedition did not launch")
	hud._close_sheet()
	# 5. торговец: кнопка и сделка
	await wait(0.3)
	if hud.trader_btn and hud.trader_btn.visible:
		await tap(hud.trader_btn.get_global_rect().get_center())
		if hud.sheet_kind != "trader":
			issue("trader button did not open trader")
		else:
			Game.resources.food = 200
			Game.resources.energy = 200
			hud.more.open_trader()
			await wait(0.3)
			var deal := find_button(hud.sheet, tr("Deal"))
			var p0 := Game.pearls + Game.crystals + Game.science
			await press(deal, "trader deal")
			if Game.pearls + Game.crystals + Game.science == p0 and Game.trader.bought.is_empty():
				issue("trader deal did nothing")
		hud._close_sheet()
	else:
		issue("trader button not visible")
	# 6. сюжетная награда (одна строка с иконкой)
	Game.track("collect_energy", 50)
	Game.claim_story()
	await wait(0.5)
	for n in hud.popup.find_children("*", "Label", true, false):
		var lr2 := (n as Label).get_global_rect()
		if (n as Label).text.length() > 3 and lr2.size.y > lr2.size.x * 1.5:
			issue("story popup: text broken into a column: " + (n as Label).text)
	hud.popup_bg.visible = false
	# 7. ящик и окно награды закрывается
	Game.crates.common = 1
	Game.open_crate("common")
	await wait(0.5)
	if not hud.popup_bg.visible:
		issue("reward popup not shown")
	else:
		for n in hud.popup.find_children("*", "Label", true, false):
			var lr := (n as Label).get_global_rect()
			if (n as Label).text.length() > 3 and lr.size.y > lr.size.x * 1.5:
				issue("reward popup: text broken into a column: " + (n as Label).text)
		await press(find_button(hud.popup, tr("Great!")), "reward great")
		if hud.popup_bg.visible:
			issue("reward popup did not close")
	print("SELFTEST: %d issues" % issues)
	get_tree().quit()

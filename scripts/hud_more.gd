extends Node
## Экраны прогрессии: исследования, сюжет, событие недели, достижения, торговец, снаряжение.
## Использует помощники интерфейса из hud.gd.

var hud  # hud.gd

func _body() -> VBoxContainer:
	return hud.sheet_body

# ---------------------------------------------------------------- исследования

## focus — исследование, к которому ведём: оно и его недостающие шаги подсвечены, список прокручен к ним.
func open_research(focus := "") -> void:
	hud._open_sheet("research", 900)
	hud._header(tr("Research"))
	var path: Array = Game.research_path(focus) if focus != "" else []
	var scroll_to: Control = null
	var top := HBoxContainer.new()
	top.add_child(hud._icon("science", 32))
	top.add_child(hud._label("%d" % Game.science, 26, Defs.RESOURCES.science.color))
	var hint = hud._label(tr("Build a Research Lab to produce science") if Game.count_of("lab") == 0 else "", 17, Color(0.7, 0.8, 0.9))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(hint)
	_body().add_child(top)
	if not Game.research_current.is_empty():
		var d := Game.research_def(Game.research_current.id)
		var row: HBoxContainer = hud._card(Color(0.15, 0.08, 0.28, 0.95), Color(0.75, 0.6, 1.0))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(hud._label(tr("Researching: %s") % tr(d.name), 22, Color(0.9, 0.8, 1.0)))
		var pb := ProgressBar.new()
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 14)
		pb.max_value = 1.0
		pb.step = 0.001
		var total: float = float(Game.research_current.end) - float(Game.research_current.start)
		pb.value = 1.0 - Game.research_left() / maxf(1.0, total)
		info.add_child(pb)
		info.add_child(hud._label(hud._clock(Game.research_left()), 17, Color(0.8, 0.8, 0.9)))
		row.add_child(info)
		var fin: Button = hud._button(tr("Finish ◆ %d") % Game.research_finish_cost(), func():
			Game.finish_research_now()
			open_research(), 60)
		fin.visible = Game.crystal_rush_allowed()
		fin.custom_minimum_size.x = 170
		fin.add_theme_color_override("font_color", Defs.RESOURCES.crystals.color)
		row.add_child(fin)
	var tier := 0
	for d in Defs.RESEARCH:
		if d.tier != tier:
			tier = d.tier
			hud._section(tr("Tier %d") % tier)
		var done := Game.has_research(d.id)
		var avail := Game.research_available(d.id)
		var active: bool = Game.research_current.get("id", "") == d.id
		var bg := Color(0.05, 0.2, 0.1, 0.9) if done else (Color(0.1, 0.08, 0.2, 0.92) if avail else Color(0.05, 0.07, 0.1, 0.9))
		var border := Color(0.5, 0.95, 0.6, 0.7) if done else (Color(0.75, 0.6, 1.0, 0.8) if avail else Color(0.4, 0.45, 0.5, 0.4))
		if d.id in path:
			border = Color(1.0, 0.82, 0.3)
			bg = Color(0.25, 0.17, 0.04, 0.95)
		var row: HBoxContainer = hud._card(bg, border)
		var ric := Art.tex("res://art/research/%s.png" % d.id)
		if ric:
			var rt := TextureRect.new()
			rt.texture = ric
			rt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			rt.custom_minimum_size = Vector2(64, 64)
			if not done and not avail:
				rt.modulate = Color(0.45, 0.45, 0.5)
			row.add_child(rt)
		if d.id in path and (scroll_to == null or avail):
			if scroll_to == null or not scroll_to.has_meta("avail"):
				scroll_to = row.get_parent()
				if avail:
					scroll_to.set_meta("avail", true)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(hud._label(("✓ " if done else ("→ " if d.id in path else "")) + tr(d.name), 22, Color(0.95, 0.9, 1.0) if avail or done else Color(0.6, 0.65, 0.7)))
		var dl: Label = hud._label(tr(d.desc), 17, Color(0.78, 0.85, 0.95))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(dl)
		if not done and not avail and not d.req.is_empty():
			var names := []
			for rq in d.req:
				if not Game.has_research(rq):
					names.append(tr(Game.research_def(rq).name))
			var rl: Label = hud._label(tr("Requires: %s") % ", ".join(names), 15, Color(1.0, 0.7, 0.6))
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_child(rl)
		row.add_child(info)
		if not done:
			var b: Button = hud._button("⚗ %d · %s" % [d.cost, hud._clock(d.minutes * 60.0)] if not active else tr("In progress"), func():
				if Game.start_research(d.id):
					open_research(), 60)
			b.custom_minimum_size.x = 190
			b.add_theme_font_size_override("font_size", 18)
			b.disabled = not avail or active or not Game.research_current.is_empty()
			row.add_child(b)
	if scroll_to:
		_scroll_to.call_deferred(scroll_to)
	if focus != "":
		var tip: Label = hud._label(tr("Highlighted: what to research, step by step."), 17, Color(1.0, 0.85, 0.4))
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body().add_child(tip)
		_body().move_child(tip, 1)

func _scroll_to(c: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var sc := hud.sheet.get_child(0) as ScrollContainer
	if is_instance_valid(c):
		sc.scroll_vertical = int(maxf(0.0, c.position.y - 80.0))

# ---------------------------------------------------------------- сюжет, событие недели, достижения (в «Заданиях»)

## Короткая цель главы для плашки на главном экране.
func story_goal_text(st: Dictionary) -> String:
	var g: String = st.goal[0]
	var n: int = st.goal[1]
	if g.begins_with("build_"):
		return tr("Build: %s") % tr(Defs.ROOMS[g.trim_prefix("build_")].name)
	if g.begins_with("expedition_") and g != "expedition_done":
		var zid := g.trim_prefix("expedition_")
		for z in Defs.ZONES:
			if z.id == zid:
				return tr("Expedition: %s") % tr(z.name)
	match g:
		"collect_energy":
			return tr("Collect %d energy") % n
		"assign":
			return tr("Assign a colonist to a room")
		"upgrade":
			return tr("Upgrade %d rooms") % n
		"population":
			return tr("Reach %d colonists") % n
		"expedition":
			return tr("Send %d expeditions") % n
		"research":
			return tr("Finish %d research projects") % n
		"incident_resolved":
			return tr("Handle %d incidents") % n
		"depth":
			return tr("Build on row %d") % n
		"level_up":
			return tr("Level up colonists %d times") % n
		"craft":
			return tr("Craft %d pieces of gear") % n
		"expedition_done":
			return tr("Complete %d expeditions") % n
		"blueprint":
			return tr("Learn %d new blueprints") % n
		"raid_won":
			return tr("Repel %d pirate raids") % n
		"boss_won":
			return tr("Defeat %d bosses") % n
		"birth":
			return tr("Welcome %d children") % n
		"stranger":
			return tr("Catch the stranger %d times") % n
		"project":
			return tr("Build %d project stages") % n
	return tr(st.get("title", ""))

## Нажатие на плашку: забрать награду или перейти к нужному действию.
func story_go() -> void:
	var st := Game.story_current()
	if st.is_empty():
		return
	if Game.story_ready():
		Game.claim_story()
		return
	var g: String = st.goal[0]
	if g.begins_with("build_"):
		hud._start_build(g.trim_prefix("build_"))
		return
	if g.begins_with("expedition"):
		var dock := Game.find_room_of_type("dock")
		if dock.is_empty():
			hud._start_build("dock")
		else:
			var zi := 0
			for i in Defs.ZONES.size():
				if g == "expedition_" + Defs.ZONES[i].id:
					zi = i
			hud._open_planner(dock.id, zi)
		return
	match g:
		"research":
			if Game.count_of("lab") == 0:
				hud._start_build("lab")
			else:
				open_research()
			return
		"depth":
			var nr := Game.next_depth_research()
			if nr != "" and not Game.has_research(nr):
				open_research(nr)
			else:
				hud._start_build("elevator")
			return
		"upgrade":
			var best := {}
			for r in Game.rooms:
				if r.level < Defs.MAX_LEVEL and Defs.ROOMS[r.type].get("buildable", false) and r.type != "elevator" and (best.is_empty() or Game.upgrade_cost(r) < Game.upgrade_cost(best)):
					best = r
			if not best.is_empty():
				hud.view.room_selected.emit(best.id)
				return
		"craft":
			var ws := Game.find_room_of_type("workshop")
			if ws.is_empty():
				hud._start_build("workshop")
			else:
				hud.view.room_selected.emit(ws.id)
			return
		"population":
			if Game.colonists.size() >= Game.NATURAL_POP and Game.count_of("radio") == 0 and Game.is_unlocked("radio"):
				hud._start_build("radio")
				return
			if Game.colonists.size() >= Game.population_cap():
				hud._start_build("living")
				return
	hud._open_tasks()

func add_story_section() -> void:
	var st := Game.story_current()
	if st.is_empty():
		hud._section(tr("Story complete!"))
		return
	hud._section(tr("Story · chapter %d/%d") % [Game.story_index + 1, Defs.STORY.size()])
	var row: HBoxContainer = hud._card(Color(0.08, 0.14, 0.26, 0.95), Color(1.0, 0.8, 0.4, 0.8))
	row.add_child(hud.reyes_portrait(96))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(hud._label(tr(st.title), 22, Color(1.0, 0.88, 0.5)))
	var txt: Label = hud._label("«" + tr(st.text) + "»", 17, Color(0.85, 0.92, 1.0))
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(txt)
	if not st.get("unlocks", []).is_empty():
		var names: Array = st.unlocks.map(func(t): return tr(Defs.ROOMS[t].name))
		info.add_child(hud._label(tr("New rooms: %s") % ", ".join(names), 16, Color(0.6, 1.0, 0.7)))
	var goal: int = st.goal[1]
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 12)
	pb.max_value = goal
	pb.value = mini(goal, Game.story_progress())
	info.add_child(pb)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	srow.add_child(hud._label("%d/%d" % [mini(goal, Game.story_progress()), goal], 15, Color(0.75, 0.85, 0.95)))
	srow.add_child(hud._reward_chips(st.reward, 26, 15))
	info.add_child(srow)
	row.add_child(info)
	var b: Button = hud._button(tr("Claim"), func():
		Game.claim_story()
		hud._open_tasks(), 60)
	b.disabled = not Game.story_ready()
	b.custom_minimum_size.x = 120
	row.add_child(b)

func add_chains_section() -> void:
	hud._section(tr("Task chains"))
	for cd in Defs.CHAINS:
		var step := Game.chain_step(cd)
		var cs := Game.chain_state(cd.id)
		var row: HBoxContainer = hud._card(Color(0.06, 0.12, 0.22, 0.92), Color(0.6, 0.8, 1.0, 0.5))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(hud._label("%s · %d/%d" % [tr(cd.name), mini(int(cs.step) + 1, cd.steps.size()), cd.steps.size()], 21, Color(0.75, 0.9, 1.0)))
		if step.is_empty():
			info.add_child(hud._label(tr("Complete!"), 18, Color(0.6, 1.0, 0.6)))
			row.add_child(info)
			continue
		var goal: int = step.goal[1]
		info.add_child(hud._label(story_goal_text({"goal": step.goal}), 18, Color(0.88, 0.94, 1.0)))
		var pb := ProgressBar.new()
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 10)
		pb.max_value = goal
		pb.value = mini(goal, int(cs.count))
		info.add_child(pb)
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 10)
		srow.add_child(hud._label("%d/%d" % [mini(goal, int(cs.count)), goal], 15, Color(0.75, 0.85, 0.95)))
		srow.add_child(hud._reward_chips(step.reward, 24, 15))
		info.add_child(srow)
		row.add_child(info)
		var b: Button = hud._button(tr("Claim"), func():
			Game.claim_chain(cd)
			hud._open_tasks(), 56)
		b.disabled = not Game.chain_ready(cd)
		b.custom_minimum_size.x = 110
		row.add_child(b)

func add_weekly_section() -> void:
	var ev := Game.weekly_event()
	hud._section(tr("Weekly event · %d days left") % Game.weekly_days_left())
	var row: HBoxContainer = hud._card(Color(0.22, 0.08, 0.2, 0.95), Color(1.0, 0.5, 0.8, 0.8))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(hud._label(tr(ev.name), 23, Color(1.0, 0.75, 0.9)))
	var d: Label = hud._label(tr(ev.desc), 17, Color(0.9, 0.85, 0.95))
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(d)
	var last: int = ev.tiers[-1]
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 12)
	pb.max_value = last
	pb.value = mini(last, Game.weekly_progress)
	info.add_child(pb)
	info.add_child(hud._label("%d / %d" % [mini(last, Game.weekly_progress), last], 15, Color(0.85, 0.8, 0.9)))
	row.add_child(info)
	var tiers := HBoxContainer.new()
	tiers.add_theme_constant_override("separation", 8)
	for i in ev.tiers.size():
		var claimed: bool = i in Game.weekly_claimed
		var b: Button = hud._button("", func():
			Game.claim_weekly(i)
			hud._open_tasks(), 56)
		hud._reward_button(b, Defs.WEEKLY_REWARDS[i], ("✓ " if claimed else "") + "%d → " % ev.tiers[i])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.disabled = claimed or Game.weekly_progress < ev.tiers[i]
		tiers.add_child(b)
	_body().add_child(tiers)
	# жетоны и магазин события
	var srow: HBoxContainer = hud._card(Color(0.18, 0.12, 0.04, 0.95), Color(1.0, 0.8, 0.35, 0.85))
	srow.add_child(hud._icon("event_token", 40, EVENT_GOLD))
	var tl: Label = hud._label(tr("%d event tokens") % Game.event_token_count(), 21, EVENT_GOLD)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(tl)
	var sb: Button = hud._button(tr("Event shop"), open_event_shop, 56)
	sb.custom_minimum_size.x = 170
	hud._gold(sb)
	if Game.event_shop_ready():
		sb.add_child(hud._badge())
	srow.add_child(sb)

## Справка «Как играть».
func open_guide() -> void:
	hud._open_sheet("guide", 900)
	hud._header(tr("How to play"))
	for g in Defs.GUIDE:
		var row: HBoxContainer = hud._card(Color(0.05, 0.11, 0.2, 0.95), Color(0.5, 0.75, 1.0, 0.5))
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		var key: String = g.icon
		var t: Texture2D = Art.marker_icon(key)
		if t == null:
			t = Art.tex("res://art/ui/icons/%s.png" % key)
		if t:
			var ti := TextureRect.new()
			ti.texture = t
			ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ti.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ti.custom_minimum_size = Vector2(64, 64)
			ti.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(ti)
		else:
			var ic: Control = hud._icon(key, 64, EVENT_GOLD if key == "event_token" else Color.WHITE)
			ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			row.add_child(ic)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(hud._label(tr(g.title), 23, Color(1.0, 0.88, 0.5)))
		var tl: Label = hud._label(tr(g.text), 17, Color(0.88, 0.92, 1.0))
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(tl)
		row.add_child(info)

const EVENT_GOLD := Color(1.0, 0.82, 0.35)

## Иконка трофея: картинка art/ui/trophies/<mod>.png, если есть, иначе нарисованный кубок.
func _trophy_icon(mod: String, size: int, lit := true) -> Control:
	var t := Art.tex("res://art/ui/trophies/%s.png" % mod)
	if t == null:
		return hud._icon("cup", size, Defs.TROPHIES[mod].color if lit else Color(0.3, 0.32, 0.4))
	var tr_i := TextureRect.new()
	tr_i.texture = t
	tr_i.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr_i.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr_i.custom_minimum_size = Vector2(size, size)
	tr_i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not lit:
		tr_i.modulate = Color(0.25, 0.25, 0.3)
	return tr_i

## Магазин события: жетоны недели → трофей, чертёж, ящики. Жетоны сгорают в конце недели.
func open_event_shop() -> void:
	var ev := Game.weekly_event()
	hud._open_sheet("event_shop", 900)
	hud._header(tr(ev.name))
	var art := Art.tex("res://art/events/weekly_%s.png" % ev.mod)
	if art:
		var pic := TextureRect.new()
		pic.texture = art
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(0, 170)
		_body().add_child(pic)
	var bal := HBoxContainer.new()
	bal.alignment = BoxContainer.ALIGNMENT_CENTER
	bal.add_theme_constant_override("separation", 10)
	bal.add_child(hud._icon("event_token", 52, EVENT_GOLD))
	bal.add_child(hud._label(str(Game.event_token_count()), 40, EVENT_GOLD))
	_body().add_child(bal)
	var note: Label = hud._label(tr("Earn tokens from this week's goal. Tokens burn when the event ends in %d days!") % Game.weekly_days_left(), 17, Color(1.0, 0.75, 0.6))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body().add_child(note)
	# пропуск события
	if Game.event_pass_active():
		var on: Label = hud._label(tr("Event Pass active: double tokens!"), 20, Color(0.6, 1.0, 0.6))
		on.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_body().add_child(on)
	elif Store.can_buy("event_pass"):
		var p: Dictionary = Store.product("event_pass")
		var offer: HBoxContainer = hud._card(Color(0.3, 0.1, 0.25, 0.95), Color(1.0, 0.8, 0.4, 0.95))
		offer.add_child(hud._icon("event_token", 56, EVENT_GOLD))
		var oi := VBoxContainer.new()
		oi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		oi.add_child(hud._label(tr(p.title), 24, Color(1.0, 0.9, 0.6)))
		var od: Label = hud._label(tr(p.desc), 16)
		od.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		oi.add_child(od)
		offer.add_child(oi)
		var pb: Button = hud._button(Store.price_of("event_pass"), func():
			Store.purchase("event_pass")
			open_event_shop(), 64)
		pb.custom_minimum_size.x = 130
		hud._gold(pb)
		offer.add_child(pb)
	# товары
	hud._section(tr("Event shop"))
	for it in Defs.EVENT_SHOP:
		var id: String = it.id
		var left: int = int(it.limit) - Game.event_bought_count(id)
		var row: HBoxContainer = hud._card(Color(0.08, 0.1, 0.2, 0.95), Color(EVENT_GOLD, 0.6) if Game.can_buy_event(id) else Color(0.4, 0.5, 0.7, 0.4))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if id == "trophy":
			var td: Dictionary = Defs.TROPHIES[ev.mod]
			var lv := Game.trophy_level(ev.mod)
			row.add_child(_trophy_icon(ev.mod, 64))
			info.add_child(hud._label(tr(td.name) + "  " + tr("Lv %d/%d") % [lv, Defs.TROPHY_MAX], 22, td.color))
			var tdl: Label = hud._label(tr("Event trophy, forever: %s. Levels up each time this event returns.") % tr(td.desc), 15, Color(0.85, 0.85, 0.95))
			tdl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.add_child(tdl)
		else:
			info.add_child(hud._reward_chips(it.reward, 34, 20))
			if id == "legendary_bp":
				info.add_child(hud._label(tr("Legendary blueprint"), 17, Color(1.0, 0.75, 0.25)))
		info.add_child(hud._label(tr("%d left this week") % maxi(0, left), 14, Color(0.7, 0.75, 0.85)))
		row.add_child(info)
		var b: Button = hud._button(str(it.cost), func():
			if Game.buy_event(id):
				open_event_shop(), 56)
		b.custom_minimum_size.x = 120
		b.disabled = not Game.can_buy_event(id)
		var bi: Control = hud._icon("event_token", 26, EVENT_GOLD)
		bi.position = Vector2(8, 15)
		b.add_child(bi)
		row.add_child(b)
	# жетоны за жемчуг
	var crow: HBoxContainer = hud._card(Color(0.15, 0.06, 0.15, 0.95), Color(1.0, 0.6, 0.85, 0.6))
	crow.add_child(hud._icon("event_token", 40, EVENT_GOLD))
	var cl: Label = hud._label(tr("+%d tokens") % Defs.EVENT_CACHE_TOKENS, 20, EVENT_GOLD)
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(cl)
	var price := Game.event_cache_price()
	var cb: Button = hud._button(str(price), func():
		if Game.buy_event_cache():
			open_event_shop(), 56)
	cb.custom_minimum_size.x = 150
	cb.disabled = Game.pearls < price
	var ci: Control = hud._icon("pearls", 24)
	ci.position = Vector2(8, 16)
	cb.add_child(ci)
	crow.add_child(cb)
	var cn: Label = hud._label(tr("Price doubles with each purchase this week."), 14, Color(0.7, 0.7, 0.8))
	_body().add_child(cn)
	# коллекция трофеев
	hud._section(tr("Trophy collection"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_body().add_child(grid)
	for mod in Defs.TROPHIES:
		var td: Dictionary = Defs.TROPHIES[mod]
		var lv := Game.trophy_level(mod)
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_stylebox_override("panel", hud._box(Color(0.06, 0.08, 0.16, 0.95), Color(td.color, 0.7 if lv > 0 else 0.2), 14))
		var hb := HBoxContainer.new()
		cell.add_child(hb)
		hb.add_child(_trophy_icon(mod, 52, lv > 0))
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nl: Label = hud._label(tr(td.name), 17, td.color if lv > 0 else Color(0.5, 0.55, 0.65))
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(nl)
		vb.add_child(hud._label(tr("Lv %d/%d") % [lv, Defs.TROPHY_MAX], 15, Color(0.75, 0.8, 0.9)))
		hb.add_child(vb)
		grid.add_child(cell)

func open_achievements() -> void:
	hud._open_sheet("achievements", 900)
	hud._header(tr("Achievements"))
	for a in Defs.ACHIEVEMENTS:
		var t := Game.achievement_tier(a)
		var maxed: bool = t >= a.tiers.size()
		var ready := Game.achievement_ready(a)
		var row: HBoxContainer = hud._card(Color(0.2, 0.15, 0.04, 0.95) if ready else Color(0.05, 0.12, 0.2, 0.9), Color(1.0, 0.8, 0.3) if ready else Color(0.5, 0.7, 0.9, 0.4))
		var cup := TextureRect.new()
		var cup_names := ["trophy_bronze", "trophy_bronze", "trophy_silver", "trophy_gold"]
		cup.texture = Art.tex("res://art/ui/icons/%s.png" % cup_names[t])
		cup.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cup.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cup.custom_minimum_size = Vector2(64, 64)
		cup.modulate = Color(0.35, 0.35, 0.4, 0.8) if t == 0 else Color.WHITE
		row.add_child(cup)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(hud._label(tr(a.name) + "  " + "★".repeat(t) + "☆".repeat(a.tiers.size() - t), 22, Color(1.0, 0.9, 0.6)))
		var goal: int = a.tiers[mini(t, a.tiers.size() - 1)]
		info.add_child(hud._label(tr(a.desc) % goal, 17, Color(0.8, 0.88, 0.95)))
		var pb := ProgressBar.new()
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 10)
		pb.max_value = goal
		pb.value = mini(goal, Game.stat_value(a.stat))
		info.add_child(pb)
		row.add_child(info)
		var b: Button = hud._button("MAX" if maxed else "◆ %d" % a.reward[t], func():
			Game.claim_achievement(a)
			open_achievements(), 60)
		b.disabled = not ready
		b.custom_minimum_size.x = 120
		b.add_theme_color_override("font_color", Defs.RESOURCES.crystals.color)
		row.add_child(b)

# ---------------------------------------------------------------- торговец

func open_trader() -> void:
	if Game.trader.is_empty():
		return
	hud._open_sheet("trader", 560)
	hud._header(tr("Wandering Trader"))
	_body().add_child(hud._label(tr("Leaves in %s") % hud._clock(float(Game.trader.until) - Game.now()), 18, Color(0.7, 1.0, 0.8)))
	if Game.trade_discount() > 0.0:
		var dl: Label = hud._label(tr("Charm discount: −%d%%") % int(round(Game.trade_discount() * 100)), 18, Defs.STAT_COLORS.cha)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body().add_child(dl)
	for i in Game.trader.offers.size():
		var o: Dictionary = Game.trader.offers[i]
		var bought: bool = i in Game.trader.bought
		var row: HBoxContainer = hud._card(Color(0.05, 0.18, 0.12, 0.92), Color(0.5, 1.0, 0.6, 0.6))
		# «отдаёшь → получаешь» картинками
		var deal := HBoxContainer.new()
		deal.add_theme_constant_override("separation", 10)
		deal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var give := {}
		for k in o.give:
			give[k] = Game.trade_price(o, k)
		deal.add_child(_offer_chip(give, 44))
		deal.add_child(hud._label("→", 30, Color(0.7, 1.0, 0.75)))
		deal.add_child(_offer_chip(o.get, 52))
		row.add_child(deal)
		var b: Button = hud._button(tr("Done") if bought else tr("Deal"), func():
			Game.trade(i)
			open_trader(), 60)
		b.disabled = bought
		if not bought and not Game.can_trade(i):
			# не хватает — кнопка неактивна, а то, чего не хватает, подсвечено красным
			b.disabled = true
			deal.get_child(0).modulate = Color(1.0, 0.45, 0.45)
		b.custom_minimum_size.x = 150
		row.add_child(b)

func _offer_chip(d: Dictionary, size: int) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var key: String = d.keys()[0]
	var val = d[key]
	var icon_key := key
	var txt := ""
	match key:
		"crates":
			icon_key = "crate_" + val.keys()[0]
			txt = tr(Defs.CRATES[val.keys()[0]].name)
		"item":
			icon_key = "item_" + ("explorer_suit" if val == "legendary" else "diving_armor")
			txt = tr(Defs.ITEM_RARITY[val].name)
		_:
			txt = str(val)
	var tex := Art.marker_icon(icon_key)
	if tex:
		var t := TextureRect.new()
		t.texture = tex
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(size, size)
		hb.add_child(t)
	hb.add_child(hud._label(txt, 22))
	return hb

# ---------------------------------------------------------------- снаряжение в карточке колониста

func add_gear_section(c: Dictionary) -> void:
	hud._section(tr("Gear"))
	var row := GridContainer.new()
	row.columns = 2
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	for kind in ["suit", "tool", "weapon", "armor"]:
		var uid: int = c.get(kind + "_item", -1)
		var it := Game.get_item(uid) if uid != -1 else {}
		var txt: String = slot_name(kind) + ":\n"
		if it.is_empty():
			txt += tr("empty")
		else:
			txt += "%s\n%s" % [Game.item_name(it), item_effect(it)]
		var b: Button = hud._button(txt, open_gear_picker.bind(c.id, kind), 96)
		if not it.is_empty():
			var ic := Art.tex("res://art/items/%s.png" % it.base)
			if ic:
				b.icon = ic
				b.expand_icon = true
				b.add_theme_constant_override("icon_max_width", 52)
				b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
				b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 0
		if not it.is_empty():
			b.add_theme_color_override("font_color", Defs.ITEM_RARITY[it.rarity].color)
		row.add_child(b)
	_body().add_child(row)

func slot_name(kind: String) -> String:
	return {"suit": tr("Suit"), "tool": tr("Tool"), "armor": tr("Armor"), "weapon": tr("Weapon")}[kind]

func item_effect(it: Dictionary) -> String:
	var b := Game.item_base(it)
	if b.kind == "armor":
		return tr("-%d%% damage") % int((Game.ARMOR_PROTECTION[it.rarity] + float(b.get("prot", 0.0))) * 100)
	if b.kind == "weapon":
		return tr("+%d attack") % int(round(float(b.atk) * Game.WEAPON_RARITY[it.rarity]))
	var st: Array = b.stats.map(func(k): return tr(Defs.STATS[k]))
	return "+%d %s" % [Game.item_bonus(it), "/".join(st)]

func open_gear_picker(cid: int, kind: String) -> void:
	var c := Game.get_colonist(cid)
	hud._open_sheet("gear", 700)
	hud._header({"suit": tr("Choose a suit"), "tool": tr("Choose a tool"), "armor": tr("Choose armor"), "weapon": tr("Choose a weapon")}[kind])
	if kind == "weapon":
		var wh: Label = hud._label(tr("Weapons help against pirates, monsters and bosses."), 18, Color(0.75, 0.85, 0.95))
		wh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body().add_child(wh)
	if kind == "armor":
		var hint: Label = hud._label(tr("Armor reduces damage from incidents and expeditions."), 18, Color(0.75, 0.85, 0.95))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body().add_child(hint)
	if c.get(kind + "_item", -1) != -1:
		_body().add_child(hud._button(tr("Take off"), func():
			Game.unequip(c, kind)
			hud._open_colonist(cid), 60))
	var list := Game.items.filter(func(it): return Game.item_base(it).kind == kind)
	list.sort_custom(func(a, b): return Defs.ITEM_RARITY.keys().find(a.rarity) > Defs.ITEM_RARITY.keys().find(b.rarity))
	if list.is_empty():
		var l: Label = hud._label(tr("No gear yet. Find it on expeditions and in crates!"), 19, Color(0.7, 0.8, 0.9))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body().add_child(l)
	for it in list:
		var owner := Game.item_owner(it.uid)
		var txt := "%s · %s" % [Game.item_name(it), item_effect(it)]
		if not owner.is_empty():
			txt += " · " + owner.name.split(" ")[0]
		var b: Button = hud._button(txt, func():
			Game.equip(c, it.uid)
			hud._open_colonist(cid), 60)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", Defs.ITEM_RARITY[it.rarity].color)
		var ic2 := Art.tex("res://art/items/%s.png" % it.base)
		if ic2:
			b.icon = ic2
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 48)
		b.disabled = owner.get("id", -1) == cid
		_body().add_child(b)
	_body().add_child(hud._button(tr("Back"), hud._open_colonist.bind(cid), 56))


# ---------------------------------------------------------------- мастерская: крафт по чертежам

## Строка материалов картинками; need — сколько нужно (красным, если не хватает).
func materials_row(mats: Dictionary, need := false, size := 28) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	for m in mats:
		var t := TextureRect.new()
		t.texture = Art.material(m)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(size, size)
		t.tooltip_text = tr(Defs.MATERIALS[m].name)
		hb.add_child(t)
		var have := int(Game.materials.get(m, 0))
		var txt := "%d/%d" % [have, int(mats[m])] if need else str(int(mats[m]))
		var col := Color(1, 1, 1) if not need or have >= int(mats[m]) else Color(1.0, 0.45, 0.4)
		hb.add_child(hud._label(txt, 17, col))
		var gap := Control.new()
		gap.custom_minimum_size.x = 6
		hb.add_child(gap)
	return hb

func workshop_section(r: Dictionary) -> void:
	hud._section(tr("Materials"))
	var have := {}
	for m in Defs.MATERIALS:
		if int(Game.materials.get(m, 0)) > 0:
			have[m] = Game.materials[m]
	if have.is_empty():
		hud.sheet_body.add_child(hud._label(tr("No materials yet. Find them on expeditions; the workshop also makes scrap."), 17, Color(0.75, 0.85, 0.95)))
	else:
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_child(materials_row(have, false, 30))
		hud.sheet_body.add_child(flow)
	# текущий заказ
	var job := Game.craft_job(r)
	var job_box := VBoxContainer.new()
	job_box.add_theme_constant_override("separation", 8)
	hud.sheet_body.add_child(job_box)
	hud.room_live_labels["craft"] = {"box": job_box, "key": str(job.get("key", "")), "ready": Game.craft_ready(r)}
	_fill_job(job_box, r)
	hud._section(tr("Blueprints"))
	var keys: Array = Game.blueprints.duplicate()
	keys.sort_custom(func(a, b):
		var ra := Defs.RARITIES.find(a.split(":")[1])
		var rb := Defs.RARITIES.find(b.split(":")[1])
		return ra > rb if ra != rb else a < b)
	for key in keys:
		var parts: PackedStringArray = key.split(":")
		var d := Defs.item_def(parts[0])
		var rcol: Color = Defs.ITEM_RARITY[parts[1]].color
		var row: HBoxContainer = hud._card(Color(0.05, 0.12, 0.2, 0.92), Color(rcol, 0.6))
		var ic := TextureRect.new()
		ic.texture = Art.tex("res://art/items/%s.png" % parts[0])
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.custom_minimum_size = Vector2(64, 64)
		row.add_child(ic)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(hud._label(Game.blueprint_name(key), 20, rcol))
		info.add_child(materials_row(Defs.recipe(key), true, 24))
		var cost_row := HBoxContainer.new()
		cost_row.add_theme_constant_override("separation", 4)
		cost_row.add_child(hud._icon("pearls", 22))
		cost_row.add_child(hud._label("%d · %s" % [Game.craft_cost(key), hud._clock(Game.craft_time(r, key))], 16, Color(1.0, 0.85, 0.95) if Game.pearls >= Game.craft_cost(key) else Color(1.0, 0.45, 0.4)))
		info.add_child(cost_row)
		row.add_child(info)
		var b: Button = hud._button(tr("Craft"), func():
			if Game.start_craft(r, key):
				hud._open_room(r.id)
			else:
				hud.show_toast(tr("Not enough materials or pearls") if Game.craft_job(r).is_empty() else tr("The workshop is busy")), 56)
		b.custom_minimum_size.x = 120
		b.disabled = not Game.can_craft(r, key)
		row.add_child(b)

func _fill_job(box: VBoxContainer, r: Dictionary) -> void:
	for ch in box.get_children():
		ch.queue_free()
	var job := Game.craft_job(r)
	if job.is_empty():
		box.add_child(hud._label(tr("Pick a blueprint below to start crafting."), 18, Color(0.75, 0.9, 1.0)))
		return
	box.add_child(hud._label(tr("Crafting: %s") % Game.blueprint_name(job.key), 21, Color(1.0, 0.88, 0.5)))
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, 22)
	pb.show_percentage = false
	pb.max_value = 1.0
	pb.step = 0.001
	pb.value = clampf((Game.now() - float(job.start)) / maxf(1.0, float(job.end) - float(job.start)), 0.0, 1.0)
	box.add_child(pb)
	var st: Label = hud._label("", 18)
	box.add_child(st)
	hud.room_live_labels.craft["bar"] = pb
	hud.room_live_labels.craft["status"] = st
	if Game.craft_ready(r):
		st.text = tr("Ready!")
		var cb: Button = hud._button(tr("Take the gear"), func():
			Game.claim_craft(r)
			hud._open_room(r.id), 70)
		hud._gold(cb)
		box.add_child(cb)
	else:
		st.text = tr("Ready in %s") % hud._clock(float(job.end) - Game.now())
		if Game.crystal_rush_allowed():
			var fb: Button = hud._button("", func():
				Game.finish_craft_now(r)
				hud._open_room(r.id), 60)
			hud.set_cost_text(fb, tr("Finish ◆ %d") % Game.craft_finish_cost(r))
			box.add_child(fb)

func refresh_workshop_live(r: Dictionary) -> void:
	var d: Dictionary = hud.room_live_labels.craft
	var job := Game.craft_job(r)
	if str(job.get("key", "")) != d.key or Game.craft_ready(r) != d.ready:
		d.key = str(job.get("key", ""))
		d.ready = Game.craft_ready(r)
		_fill_job(d.box, r)
		return
	if d.has("bar") and not job.is_empty():
		d.bar.value = clampf((Game.now() - float(job.start)) / maxf(1.0, float(job.end) - float(job.start)), 0.0, 1.0)
		if not Game.craft_ready(r):
			d.status.text = tr("Ready in %s") % hud._clock(float(job.end) - Game.now())


# ---------------------------------------------------------------- проекты колонии

func open_projects() -> void:
	hud._open_sheet("projects", 900)
	hud._header(tr("Colony projects"))
	var intro: Label = hud._label(tr("Big builds for a grown colony. Each stage gives a permanent bonus and a crate."), 18, Color(0.8, 0.9, 1.0))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.sheet_body.add_child(intro)
	for p in Defs.PROJECTS:
		var st := Game.project_stage(p.id)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", hud._box(Color(0.05, 0.11, 0.19, 0.95), Color(p.color, 0.7), 16, 2))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 8)
		card.add_child(vb)
		hud.sheet_body.add_child(card)
		var pic := Art.tex("res://art/projects/%s.png" % p.id)
		if pic:
			var tr_pic := TextureRect.new()
			tr_pic.texture = pic
			tr_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr_pic.custom_minimum_size = Vector2(0, 150)
			if not Game.project_unlocked(p.id):
				tr_pic.modulate = Color(0.4, 0.4, 0.45)
			vb.add_child(tr_pic)
		var head := HBoxContainer.new()
		var nl: Label = hud._label(tr(p.name), 24, p.color)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nl)
		var pips := ""
		for i in Defs.PROJECT_STAGES:
			pips += "●" if i < st else "○"
		var mastery := Game.project_mastery(p.id)
		if mastery > 0:
			pips += "  ★%d" % mastery
		head.add_child(hud._label(pips, 24, p.color))
		vb.add_child(head)
		var dl: Label = hud._label(tr(p.desc), 17, Color(0.8, 0.88, 0.95))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(dl)
		if st >= Defs.PROJECT_STAGES:
			var ml: Label = hud._label(tr("Complete! Mastery: each level adds a quarter of a stage bonus."), 17, Color(0.6, 1.0, 0.6))
			ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(ml)
		if not Game.project_unlocked(p.id):
			vb.add_child(hud._label(tr("Needs colony level %d") % p.level, 19, Color(1.0, 0.7, 0.5)))
			continue
		var cost := Game.project_cost(p.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(hud._icon("pearls", 24))
		row.add_child(hud._label(str(cost.pearls), 18, Color(1.0, 0.85, 0.95) if Game.pearls >= int(cost.pearls) else Color(1.0, 0.45, 0.4)))
		row.add_child(materials_row(cost.materials, true, 24))
		vb.add_child(row)
		var pid: String = p.id
		if not Game.has_materials(cost.materials):
			var pl := Game.fill_plan(cost.materials)
			if not pl.is_empty():
				var mats_need: Dictionary = cost.materials
				var fb: Button = hud._button(tr("Trade spare materials: %d") % int(pl.pearls), func():
					if Game.fill_materials(mats_need):
						open_projects(), 54)
				fb.disabled = Game.pearls < int(pl.pearls)
				var fi: Control = hud._icon("pearls", 24)
				fi.position = Vector2(10, 15)
				fb.add_child(fi)
				vb.add_child(fb)
		var btxt: String = tr("Build stage %d") % (st + 1) if st < Defs.PROJECT_STAGES else tr("Mastery %d") % (Game.project_mastery(p.id) + 1)
		var b: Button = hud._button(btxt, func():
			if Game.build_project_stage(pid):
				open_projects(), 64)
		b.disabled = not Game.can_build_project(p.id)
		if not b.disabled:
			hud._gold(b)
		vb.add_child(b)


# ---------------------------------------------------------------- магазин: наборы, копилка, колесо

func add_shop_extras() -> void:
	# магазин события недели
	var ev := Game.weekly_event()
	hud._section(tr(ev.name) + " · " + tr("%d days left") % Game.weekly_days_left())
	var er: HBoxContainer = hud._card(Color(0.18, 0.12, 0.04, 0.95), Color(1.0, 0.8, 0.35, 0.85))
	er.add_child(hud._icon("event_token", 44, EVENT_GOLD))
	var el: Label = hud._label(tr("%d event tokens") % Game.event_token_count(), 21, EVENT_GOLD)
	el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	er.add_child(el)
	var eb: Button = hud._button(tr("Event shop"), open_event_shop, 60)
	eb.custom_minimum_size.x = 170
	hud._gold(eb)
	if Game.event_shop_ready():
		eb.add_child(hud._badge())
	er.add_child(eb)
	# наборы по поводу (живут 24 часа)
	for oid in Game.active_offers():
		var p: Dictionary = Store.product(oid)
		if p.is_empty() or not Store.can_buy(oid):
			continue
		hud._section(tr("Special offer") + " · " + hud._clock(Game.offer_left(oid)))
		var row: HBoxContainer = hud._card(Color(0.3, 0.1, 0.25, 0.95), Color(1.0, 0.8, 0.4, 0.95))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(hud._label(tr(p.title), 24, Color(1.0, 0.9, 0.6)))
		var d: Label = hud._label(tr(p.desc), 17, Color(0.92, 0.9, 0.95))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(d)
		info.add_child(hud._reward_chips(p.reward, 28, 17))
		row.add_child(info)
		var pid: String = oid
		var b: Button = hud._button(Store.price_of(oid), func():
			Store.purchase(pid)
			hud._open_shop(), 72)
		hud._gold(b)
		b.custom_minimum_size.x = 140
		row.add_child(b)
	# колесо удачи
	var wrow: HBoxContainer = hud._card(Color(0.12, 0.08, 0.25, 0.92), Color(0.75, 0.55, 1.0, 0.8))
	var wi := VBoxContainer.new()
	wi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wi.add_child(hud._label(tr("Lucky wheel"), 24, Color(0.9, 0.8, 1.0)))
	wi.add_child(hud._label(tr("One free spin every day!") if Game.wheel_free_ready() else tr("Free spin used. Come back tomorrow!"), 17, Color(0.8, 0.85, 0.95)))
	wrow.add_child(wi)
	var wb: Button = hud._button(tr("Spin!") if Game.wheel_free_ready() else tr("Open"), open_wheel, 64)
	if Game.wheel_free_ready():
		hud._gold(wb)
	wb.custom_minimum_size.x = 150
	wrow.add_child(wb)
	# копилка
	var prow: HBoxContainer = hud._card(Color(0.25, 0.15, 0.05, 0.92), Color(1.0, 0.75, 0.35, 0.8))
	var pi := VBoxContainer.new()
	pi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pi.add_child(hud._label(tr("Treasure Piggy Bank"), 24, Color(1.0, 0.85, 0.5)))
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 6)
	pr.add_child(hud._icon("crystals", 26))
	pr.add_child(hud._label("%d / %d" % [int(Game.piggy), int(Game.PIGGY_CAP)], 20, Defs.RESOURCES.crystals.color))
	pi.add_child(pr)
	var pbar := ProgressBar.new()
	pbar.show_percentage = false
	pbar.custom_minimum_size = Vector2(0, 12)
	pbar.max_value = Game.PIGGY_CAP
	pbar.value = Game.piggy
	pi.add_child(pbar)
	var hint: Label = hud._label(tr("Crystals pile up as you collect. Break it to take them all!") if Game.piggy_can_break() else tr("Fills up as you collect. Can be opened from %d crystals.") % int(Game.PIGGY_MIN), 15, Color(0.85, 0.8, 0.7))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pi.add_child(hint)
	prow.add_child(pi)
	var pb: Button = hud._button(Store.price_of("piggy_bank"), func():
		Store.purchase("piggy_bank")
		hud._open_shop(), 64)
	pb.disabled = not Game.piggy_can_break()
	pb.custom_minimum_size.x = 140
	prow.add_child(pb)

## Колесо удачи: сектора с призами, стрелка сверху; крутится и останавливается на призе.
var wheel_ctrl: Control
var wheel_angle := 0.0
var wheel_busy := false

func open_wheel() -> void:
	hud._open_sheet("wheel", 860)
	hud._header(tr("Lucky wheel"))
	wheel_ctrl = Control.new()
	wheel_ctrl.custom_minimum_size = Vector2(0, 460)
	wheel_ctrl.draw.connect(_draw_wheel)
	hud.sheet_body.add_child(wheel_ctrl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	hud.sheet_body.add_child(row)
	if Game.wheel_free_ready():
		var fb: Button = hud._button(tr("Free spin"), func(): _spin("free"), 70)
		hud._gold(fb)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(fb)
	else:
		if Game.wheel_ad_ready():
			var ab: Button = hud._button(tr("Spin for a video"), func(): Store.show_rewarded(func(): _spin("ad")), 70)
			hud._with_icon(ab, "ad", 34)
			ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(ab)
		var cb: Button = hud._button("", func(): _spin("paid"), 70)
		hud.set_cost_text(cb, tr("Spin ◆ %d") % Defs.WHEEL_CRYSTAL_COST)
		cb.disabled = not Game.wheel_paid_ready()
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cb)
	hud.sheet_body.add_child(hud._label(tr("Paid spins today: %d / %d") % [Game.wheel_paid, Defs.WHEEL_PAID_PER_DAY], 16, Color(0.7, 0.8, 0.9)))

func _spin(kind: String) -> void:
	if wheel_busy:
		return
	var idx := Game.spin_wheel(kind)
	if idx < 0:
		return
	wheel_busy = true
	var n := Defs.WHEEL.size()
	var sector := TAU / n
	# стрелка сверху: сектор idx должен встать под неё
	var target := -PI / 2.0 - (idx + 0.5) * sector
	var base := wheel_angle - fmod(wheel_angle, TAU)
	var final_angle := base + TAU * 5.0 + fposmod(target, TAU)
	var tw: Tween = hud.create_tween()
	tw.tween_method(func(a):
		wheel_angle = a
		if is_instance_valid(wheel_ctrl):
			wheel_ctrl.queue_redraw(), wheel_angle, final_angle, 3.2).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		wheel_busy = false
		Game.grant_wheel(idx)
		Audio.play("crate")
		open_wheel())

func _draw_wheel() -> void:
	var c := wheel_ctrl.size / 2.0
	var r := minf(c.x, c.y) - 16.0
	var n := Defs.WHEEL.size()
	var sector := TAU / n
	wheel_ctrl.draw_circle(c, r + 12, Color(0.8, 0.6, 0.25))
	wheel_ctrl.draw_circle(c, r + 6, Color(0.25, 0.15, 0.08))
	for i in n:
		var a0 := wheel_angle + i * sector
		var pts := PackedVector2Array([c])
		for k in 17:
			var a := a0 + sector * k / 16.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		var col: Color = Defs.WHEEL[i].color
		wheel_ctrl.draw_colored_polygon(pts, col.darkened(0.15 if i % 2 == 0 else 0.35))
		wheel_ctrl.draw_line(c, c + Vector2(cos(a0), sin(a0)) * r, Color(0.2, 0.12, 0.06), 3.0)
		var am := a0 + sector / 2.0
		var ip := c + Vector2(cos(am), sin(am)) * r * 0.68
		var rw: Dictionary = Defs.WHEEL[i].reward
		var items: Array = hud._reward_items(rw) if not rw.has("blueprint") else [["blueprint", ""]]
		if not items.is_empty():
			var tex := Art.marker_icon(items[0][0])
			if tex:
				wheel_ctrl.draw_texture_rect(tex, Rect2(ip - Vector2(24, 24), Vector2(48, 48)), false)
			var txt: String = str(items[0][1]) if not rw.has("blueprint") else ""
			if txt != "" and not txt.begins_with("×"):
				var f := ThemeDB.fallback_font
				var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
				var tp := ip + Vector2(-tw / 2.0, 40)
				wheel_ctrl.draw_string_outline(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color(0, 0, 0, 0.8))
				wheel_ctrl.draw_string(f, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	wheel_ctrl.draw_circle(c, 34, Color(0.8, 0.6, 0.25))
	wheel_ctrl.draw_circle(c, 26, Color(0.35, 0.2, 0.08))
	# стрелка сверху
	var tip := c + Vector2(0, -r + 18)
	wheel_ctrl.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-20, -40), tip + Vector2(20, -40)]), Color(1.0, 0.3, 0.3))
	wheel_ctrl.draw_polyline(PackedVector2Array([tip, tip + Vector2(-20, -40), tip + Vector2(20, -40), tip]), Color(1, 1, 1, 0.9), 2.0)

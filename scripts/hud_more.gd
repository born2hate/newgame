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
	return tr(st.title)

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

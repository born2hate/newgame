extends SceneTree
## Логические тесты: godot --headless --path . --script res://tests/run_tests.gd

var failures := 0

func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FAIL ", what)

func _initialize() -> void:
	var g = load("res://scripts/game_state.gd").new()
	g.traits_enabled = false
	g.rng.seed = 1
	g.new_game()
	check(g.rooms.size() == 6, "стартовая база из 6 отсеков")
	check(g.colonists.size() == 4, "4 стартовых колониста")

	check(g.can_build_at("living", 6, 2) == false, "нельзя строить без соединения")
	check(g.can_build_at("elevator", 5, 2), "лифт под лифтом")
	check(g.build("elevator", 5, 2), "строим лифт")
	check(g.can_build_at("living", 6, 2), "жилой отсек рядом с лифтом")
	var pearls_before: int = g.pearls
	var lcost: int = g.build_cost("living")
	check(g.build("living", 6, 2), "строим жилой отсек")
	check(g.pearls == pearls_before - lcost and lcost >= 100, "жемчуг списан")
	check(g.population_cap() == 10, "вместимость выросла до 10")
	check(not g.can_build_at("farm", 6, 2), "нельзя строить поверх")

	var reactor: Dictionary = g.find_room_of_type("reactor")
	var t: float = g.cycle_time(reactor)
	check(t < INF, "реактор работает (цикл %.1f с)" % t)
	for i in int(t) + 2:
		g.simulate(1.0, false)
	check(reactor.ready, "реактор готов к сбору")
	var e: float = g.resources.energy
	g.collect(reactor)
	check(g.resources.energy > e, "энергия собрана")
	check(not reactor.ready and reactor.progress == 0.0, "цикл сброшен")

	var up_cost := Defs.upgrade_cost("reactor", 1)
	g.pearls = 1000
	g.upgrade(reactor)
	check(reactor.level == 2 and g.pearls == 1000 - up_cost, "улучшение реактора")
	check(Defs.room_slots("reactor", 2) == 3, "мест стало 3")

	var free: Dictionary = g.colonists[3]
	check(g.assign(free, reactor), "назначение колониста")
	check(g.workers_in(reactor).size() == 2, "2 рабочих в реакторе")
	check(g.assign(free, g.find_room_of_type("living")), "в жилой отсек можно поселить пару")
	g.assign(free, reactor)

	g.rush(reactor)
	check(reactor.ready or reactor.incident > 0.0, "ускорение: успех или авария")

	# сохранение/загрузка
	g.save_game()
	var g2 = load("res://scripts/game_state.gd").new()
	check(g2.load_game(), "загрузка сохранения")
	check(g2.rooms.size() == g.rooms.size() and g2.pearls == g.pearls, "данные совпадают")
	check(typeof(g2.rooms[0].level) == TYPE_INT, "целые поля восстановлены")

	# офлайн: 2 часа
	var g3 = load("res://scripts/game_state.gd").new()
	g3.new_game()
	g3._apply_offline(7200.0)
	var ready := 0
	for r in g3.rooms:
		if r.ready: ready += 1
	check(ready >= 3, "после 2 ч отсеки ждут сбора (%d)" % ready)
	check(g3.colonists.size() == 6, "колонисты прибыли офлайн до лимита")

	# экономика
	var eco = load("res://scripts/game_state.gd").new()
	eco.new_game()
	check(eco.crystals == 25 and eco.crates.common == 1, "стартовые кристаллы и ящик")
	var p0: int = eco.pearls
	eco.open_crate("common")
	check(eco.crates.common == 0, "ящик открыт")
	check(eco.pearls > p0 or eco.crystals > 25 or eco.colonists.size() > 4 or eco.resources.energy > 60.0, "из ящика что-то выпало")
	eco.open_crate("common")
	check(eco.crates.common == 0, "пустой ящик не открывается")
	var odds_sum := 0.0
	for o in eco.crate_odds("gold"):
		odds_sum += o[1]
	check(absf(odds_sum - 1.0) < 0.001, "шансы ящика в сумме 100%")
	check(eco.daily_available(), "ежедневная награда доступна")
	var pd: int = eco.pearls
	eco.claim_daily()
	check(eco.pearls == pd + int(Defs.DAILY[0].pearls) and not eco.daily_available(), "награда дня 1 получена, повторно нельзя")
	eco.daily_day -= 1
	check(eco.daily_available() and eco.daily_next_index() == 1, "следующий день продолжает серию")
	eco.daily_day -= 2
	check(eco.daily_next_index() == 0, "пропуск дня сбрасывает серию")
	var farm: Dictionary = eco.find_room_of_type("farm")
	var cost: int = eco.safe_rush_cost(farm)
	var cr: int = eco.crystals
	eco.rush_safe(farm)
	check(farm.ready and eco.crystals == cr - cost, "безопасное ускорение за %d кристаллов" % cost)
	eco.start_boost()
	eco.resources.food = 0.0
	var food0: float = eco.resources.food
	eco.collect(farm)
	check(eco.resources.food - food0 >= eco.production_amount(farm) * 2.0 - 0.01, "x2 сбор при бусте")
	eco.grant({"pet": "clownfish"}, "test")
	check(eco.pet == "clownfish", "питомец из стартового набора")
	check(not eco.ads_removed(), "реклама есть по умолчанию")
	eco.grant({"no_ads": true}, "test")
	check(eco.ads_removed(), "покупка No Ads отключает рекламу")
	eco.crystals = 0
	check(not eco.spend_crystals(5), "нельзя потратить больше, чем есть")
	eco.grant({"premium": true, "crystals": 100, "crates": {"gold": 1}}, "test")
	check(eco.premium and eco.crystals == 100 and eco.crates.gold == 1, "выдача награды из покупки")
	check(eco.colonists[-1].suit == Art.CAPTAIN_SUIT, "Premium даёт капитана")
	eco.save_game()
	var e2 = load("res://scripts/game_state.gd").new()
	e2.load_game()
	check(e2.premium and e2.crates.gold == 1 and e2.crystals == 100, "экономика сохраняется")
	eco.free(); e2.free()

	# экспедиции
	var ex = load("res://scripts/game_state.gd").new()
	ex.new_game()
	ex.pearls = 1000
	var dock: Dictionary = ex._add_room("dock", 3, 1)
	var crew := [ex.colonists[0].id, ex.colonists[1].id]
	check(ex.launch_expedition(dock.id, 0, crew), "экспедиция запущена")
	check(ex.colonists[0].room == ex.ON_EXPEDITION, "экипаж ушёл из отсеков")
	check(not ex.assign(ex.colonists[0], ex.find_room_of_type("farm")), "нельзя назначить ушедшего")
	check(not ex.launch_expedition(dock.id, 0, [ex.colonists[2].id]), "один батискаф на док")
	var exp_e: Dictionary = ex.expedition_at(dock.id)
	check(not ex.expedition_done(exp_e) and ex.visible_log(exp_e).is_empty(), "в начале журнал пуст")
	exp_e.start = ex.now() - 600.0
	exp_e.end = ex.now()
	check(ex.expedition_done(exp_e) and ex.visible_log(exp_e).size() == exp_e.events.size(), "по возвращении виден весь журнал")
	var pb: int = ex.pearls
	ex.claim_expedition(exp_e)
	check(ex.expeditions.is_empty() and ex.colonists[0].room == -1, "экипаж вернулся")
	check(ex.pearls > pb, "добыча получена")
	ex.refresh_daily_systems()
	check(ex.quests.size() == Defs.QUESTS_PER_DAY, "ежедневные задания выданы")
	var q: Dictionary = ex.quests[0]
	ex.track(q.event, 1000)
	check(q.progress == q.target, "прогресс задания")
	ex.claim_quest(q)
	check(q.claimed and ex.season_xp == q.xp, "задание даёт опыт сезона")
	ex.season_xp = 250
	check(ex.season_tier() == 2, "уровень сезона 2")
	var pp: int = ex.pearls
	ex.claim_season(0, false)
	check(ex.pearls == pp + 200, "бесплатная награда сезона")
	ex.claim_season(0, true)
	check(not 0 in ex.season_claimed_premium, "платная ветка закрыта без пропуска")
	ex.season_pass = true
	ex.claim_season(0, true)
	check(0 in ex.season_claimed_premium, "платная ветка с пропуском")
	ex.claim_season(5, false)
	check(not 5 in ex.season_claimed_free, "недостигнутый уровень недоступен")
	ex.save_game()
	var ex2 = load("res://scripts/game_state.gd").new()
	ex2.load_game()
	check(ex2.season_xp == 250 and ex2.season_pass and ex2.quests.size() == Defs.QUESTS_PER_DAY, "сезон и задания сохраняются")
	ex.free(); ex2.free()

	# инциденты
	var hz = load("res://scripts/game_state.gd").new()
	hz.new_game()
	var react: Dictionary = hz.find_room_of_type("reactor")
	hz.start_hazard(react, "fire")
	check(react.incident == 100.0 and react.hazard == "fire", "пожар начался")
	var prog0: float = react.progress
	hz.simulate(1.0, false)
	check(react.progress == prog0, "производство стоит во время беды")
	check(react.incident < 100.0, "рабочие тушат пожар")
	var al: Dictionary = hz.find_room_of_type("airlock")
	hz.start_hazard(al, "fire")
	check(al.incident == 0.0, "в шлюзе беды не бывает")
	var helper: Dictionary = hz.colonists[3]
	hz.send_help(helper, react)
	check(hz.responders(react).size() == 2, "помощник прибежал")
	var pearls0: int = hz.pearls
	for i in 60:
		hz.simulate(1.0, false)
	check(react.incident == 0.0 and react.hazard == "", "пожар потушен")
	check(hz.pearls > pearls0 and helper.help == -1, "награда и помощник вернулся")
	var farm2: Dictionary = hz.find_room_of_type("farm")
	for c in hz.workers_in(farm2):
		hz.assign(c, {})
	hz.start_hazard(farm2, "flood", 70.0)
	for i in 25:
		hz.simulate(1.0, false)
	check(farm2.incident > 70.0, "без людей беда растёт")
	# прокачка
	var cc: Dictionary = hz.colonists[0]
	hz.crystals = 100
	var s0: int = cc.tech
	var tcost: int = hz.train_cost(cc, "tech")
	check(hz.train(cc, "tech") and cc.tech == s0 + 1 and hz.crystals == 100 - tcost, "тренировка навыка")
	cc.health = 50.0
	hz.heal(cc)
	check(cc.health == 100.0, "лечение")
	hz.free()

	# объединение, исследования, глубина, снаряжение, сюжет, достижения
	var pg = load("res://scripts/game_state.gd").new()
	pg.new_game()
	pg.pearls = 5000
	var n_before: int = pg.rooms.size()
	pg.build("elevator", 5, 2)
	pg.build("farm", 6, 2)
	check(pg.build("farm", 3, 1), "ферма у лифта")
	check(pg.build("farm", 1, 1), "вторая ферма рядом")
	var farm1: Dictionary = pg.room_at(1, 1)
	check(farm1.size == 2 and farm1.col == 1 and pg.room_w(farm1) == 4, "фермы объединились в 2×")
	check(pg.slots(farm1) == 4, "у 2× отсека 4 места")
	check(not pg.can_build_at("elevator", 5, 5), "зона Midnight закрыта без исследования")
	pg.science = 1000
	check(not pg.start_research("deep_drilling"), "нельзя без предыдущих исследований")
	check(pg.start_research("efficient_reactors"), "исследование началось")
	check(not pg.start_research("hydroponics"), "только одно исследование за раз")
	pg.research_current.end = pg.now()
	pg.simulate(0.1, false)
	check(pg.has_research("efficient_reactors"), "исследование завершено")
	pg.research_done.append("reinforced_hull")
	check(pg.research_available("deep_drilling"), "Deep Drilling стало доступно")
	pg.research_done.append("deep_drilling")
	for r in range(3, 6):
		pg.build("elevator", 5, r)
	check(pg.can_build_at("elevator", 5, 6) or pg.room_at(5, 5).type == "elevator", "в Midnight можно строить")
	var it: Dictionary = pg.add_item("rare", "torch")
	var col0: Dictionary = pg.colonists[0]
	var t0: int = pg.stat(col0, "tech")
	pg.equip(col0, it.uid)
	check(pg.stat(col0, "tech") == t0 + 2, "снаряжение даёт +2 к технике")
	pg.equip(pg.colonists[1], it.uid)
	check(col0.tool_item == -1 and pg.colonists[1].tool_item == it.uid, "предмет переходит к другому")
	var arm: Dictionary = pg.add_item("rare", "diving_armor")
	var hc: Dictionary = pg.colonists[2]
	hc.traits = []
	pg.equip(hc, arm.uid)
	check(hc.armor_item == arm.uid and absf(pg.protection(hc) - (0.3 + pg.stat(hc, "end") * 0.02)) < 0.001, "броня надета: −30% урона плюс выносливость")
	check(pg.story_index == 0 and not pg.story_ready(), "сюжет: глава 1")
	pg.track("collect_energy", 20)
	check(pg.story_ready(), "глава 1 выполнена")
	pg.claim_story()
	check(pg.story_index == 1 and pg.story_count == 0, "глава 2")
	var ach: Dictionary = Defs.ACHIEVEMENTS[1]
	pg.stats["build"] = 5
	var cr0: int = pg.crystals
	pg.claim_achievement(ach)
	check(pg.crystals == cr0 + ach.reward[0] and pg.achievement_tier(ach) == 1, "достижение получено")
	pg.refresh_daily_systems()
	var ev: Dictionary = pg.weekly_event()
	pg.track(ev.goal, ev.tiers[0])
	pg.claim_weekly(0)
	check(0 in pg.weekly_claimed, "награда недели")
	pg._spawn_trader()
	check(pg.trader.offers.size() == 3, "торговец с 3 предложениями")
	pg.resources.food = 200
	pg.resources.energy = 200
	pg.crystals = 500
	check(pg.trade(0), "сделка с торговцем")
	check(not pg.trade(0), "повторно та же сделка нельзя")
	var p1: int = pg.pearls
	pg.pop_bubble(false)
	check(pg.pearls > p1 and pg.stats.bubble == 1, "пузырь с жемчугом")
	pg.save_game()
	var pg2 = load("res://scripts/game_state.gd").new()
	pg2.load_game()
	check(pg2.room_at(1, 1).size == 2 and pg2.has_research("deep_drilling") and pg2.items.size() >= 1 and pg2.story_index == 1, "прогрессия сохраняется")
	pg.free(); pg2.free()

	# сложность
	var sv = load("res://scripts/game_state.gd").new()
	sv.new_game()
	check(not sv.mode_chosen, "новая игра просит выбрать режим")
	sv.set_difficulty("survival")
	check(sv.difficulty == "survival" and not sv.crystal_rush_allowed(), "выживание: без ускорения за кристаллы")
	var vic: Dictionary = sv.colonists[0]
	vic.health = 1.0
	sv.resources.oxygen = 0.0
	var n0: int = sv.colonists.size()
	for i in 3:
		sv.resources.oxygen = 0.0
		sv.simulate(1.0, false)
	check(sv.colonists.size() == n0 - 1, "выживание: колонист погибает")
	sv.colonists = [sv.colonists[0]]
	sv.pearls = 0
	sv.colonists[0].health = 0.0
	sv.simulate(1.0, false)
	check(sv.colony_lost, "выживание: колония потеряна, когда погибли все")
	var cm = load("res://scripts/game_state.gd").new()
	cm.new_game()
	cm.set_difficulty("calm")
	cm.colonists[0].health = 50.0
	cm.resources.oxygen = 0.0
	cm.resources.food = 0.0
	cm.simulate(5.0, false)
	check(cm.colonists[0].health >= 50.0, "спокойный: голод не ранит")
	# гибель и воскрешение
	var rv = load("res://scripts/game_state.gd").new()
	rv.new_game()
	rv.set_difficulty("normal")
	var vic2: Dictionary = rv.colonists[1]
	vic2.health = 0.0
	rv.resources.oxygen = 100.0
	rv.resources.food = 100.0
	rv.simulate(1.0, false)
	check(rv.fallen.size() == 1 and not vic2 in rv.colonists, "обычный режим: погибший лежит среди павших")
	var rcost: int = rv.revive_cost(rv.fallen[0])
	rv.pearls = rcost + 5
	check(rv.revive(rv.fallen[0]) and vic2 in rv.colonists and rv.pearls == 5 and vic2.health > 0.0, "оживление за жемчуг")
	rv.colonists[0].health = 0.0
	rv.simulate(1.0, false)
	rv.fallen[0].until = rv.now() - 1.0
	rv.simulate(1.0, false)
	check(rv.fallen.is_empty() and rv.colonists.size() == 3, "время вышло — потерян навсегда")
	rv.colonists[0].level = 5
	rv.colonists[0].health = 0.0
	rv.simulate(1.0, false)
	check(rv.revive_cost(rv.fallen[0]) > rcost, "оживление дороже с уровнем")
	# время вне игры прибавляется к сроку — за 3 ч отсутствия оставшееся время не уменьшилось
	var until0: float = float(rv.fallen[0].until)
	rv._apply_offline(3 * 3600.0)
	check(absf(float(rv.fallen[0].until) - until0 - 3 * 3600.0) < 1.0, "вне игры таймер воскрешения стоит")
	# офлайн: запасы не уходят в ноль, отсеки ждут сбора
	var of = load("res://scripts/game_state.gd").new()
	of.new_game()
	of.set_difficulty("normal")
	of.resources = {"energy": 80.0, "oxygen": 80.0, "food": 80.0}
	of._apply_offline(8 * 3600.0)
	check(of.resources.oxygen >= 80.0 * 0.35 - 0.01 and of.resources.food >= 80.0 * 0.35 - 0.01, "офлайн 8 ч: запасы не обнулились (%.0f O₂, %.0f еды)" % [of.resources.oxygen, of.resources.food])
	rv.free(); of.free()
	# дети
	var fam = load("res://scripts/game_state.gd").new()
	fam.new_game()
	var home: Dictionary = fam._add_room("living", 8, 1)
	fam.arrival_timer = -1.0e9
	fam.colonists[0].room = home.id
	fam.colonists[1].room = home.id
	var fam_n: int = fam.colonists.size()
	for i in 6000:
		fam.resources.oxygen = 100.0
		fam.resources.food = 100.0
		fam.resources.energy = 100.0
		fam.simulate(10.0, true)
		if fam.colonists.size() > fam_n:
			break
	var kid2: Dictionary = fam.colonists[-1]
	check(fam.colonists.size() == fam_n + 1 and kid2.get("child", false), "у пары в жилом отсеке родился ребёнок")
	check(not fam.assign(kid2, fam.find_room_of_type("reactor")), "ребёнок не работает")
	for i in int(fam.GROW_TIME) + 5:
		fam.simulate(1.0, true)
	check(not kid2.get("child", false), "ребёнок вырос")
	# медленный самостоятельный приход после 8 колонистов
	check(fam.arrival_speed() >= 1.0 or fam.colonists.size() >= fam.NATURAL_POP, "маленькая колония — люди приходят сами")
	while fam.colonists.size() < 9:
		fam.colonists.append(fam._make_colonist())
	check(fam.arrival_speed() < 0.5, "большая колония без радио — приток медленный")
	# комбо и уровень колонии
	fam.combo = 0
	fam.combo_until = 0.0
	check(absf(fam.combo_mult() - 1.0) < 0.01, "без комбо множитель 1")
	fam.combo = 10
	check(fam.combo_mult() <= 1.5 + 0.001, "комбо не больше +50%")
	var lv: int = fam.colony_level
	fam.add_colony_xp(fam.colony_xp_needed())
	check(fam.colony_level == lv + 1, "уровень колонии растёт")
	fam.free()
	# босс и выбор в экспедиции
	var bs = load("res://scripts/game_state.gd").new()
	bs.new_game()
	bs.start_boss()
	check(not bs.boss.is_empty(), "босс появился")
	var p_b: int = bs.pearls
	for i in 500:
		if bs.boss.is_empty():
			break
		bs.hit_boss()
	check(bs.boss.is_empty() and bs.pearls > p_b, "босса победили нажатиями — награда")
	bs.start_boss()
	bs.boss.until = bs.now() - 1.0
	bs.simulate(1.0, false)
	check(bs.boss.is_empty(), "босс уплывает, если не успели")
	var dk: Dictionary = bs._add_room("dock", 8, 1)
	bs.launch_expedition(dk.id, 0, [bs.colonists[0].id])
	var ex3: Dictionary = bs.expedition_at(dk.id)
	ex3["choice"] = {"id": "chest", "at": 0.0, "pick": ""}
	check(not bs.pending_choice(ex3).is_empty(), "в экспедиции ждёт выбор")
	var txt: String = bs.resolve_choice(ex3, true)
	check(txt != "" and bs.pending_choice(ex3).is_empty(), "выбор сделан, результат в журнале")
	bs.free()
	# питомцы
	var pt = load("res://scripts/game_state.gd").new()
	pt.new_game()
	pt.grant_pet("puffer")
	check(pt.pet == "puffer" and "puffer" in pt.pets_owned, "первый питомец сразу с тобой")
	var ab: float = pt.armory_bonus()
	pt.grant_pet("angel")
	pt.set_pet("angel")
	check(pt.pet == "angel" and pt.armory_bonus() < ab and pt.mood_bonus() >= 10.0, "смена питомца меняет бонус")
	for i in 10:
		pt.grant_pet()
	check(pt.pets_owned.size() == Defs.PETS.size(), "все питомцы собраны, дальше — кристаллы")
	pt.free()
	# оружие и новая броня
	var wq = load("res://scripts/game_state.gd").new()
	wq.new_game()
	var wc: Dictionary = wq.colonists[0]
	var fp0: float = wq.fight_power(wc)
	var wpn: Dictionary = wq.add_item("legendary", "trident")
	wq.equip(wc, wpn.uid)
	check(wc.weapon_item == wpn.uid and wq.fight_power(wc) > fp0 + 5.0, "трезубец усиливает в бою")
	var arm2: Dictionary = wq.add_item("rare", "abyss_armor")
	wq.equip(wc, arm2.uid)
	check(absf(wq.protection(wc) - minf(0.8, wq.stat(wc, "end") * 0.02 + 0.3 + 0.15)) < 0.001, "броня бездны защищает сильнее")
	wq.free()
	# налёт пиратов
	var pr = load("res://scripts/game_state.gd").new()
	pr.new_game()
	pr.set_difficulty("normal")
	pr.pearls = 1000
	for c in pr.colonists:
		c.room = -1
	pr.start_raid()
	check(not pr.raid.is_empty() and pr.find_room_of_type("airlock").hazard == "raid", "налёт начался у шлюза")
	var moved_on := false
	for i in 120:
		pr.resources.oxygen = 100.0
		pr.resources.food = 100.0
		pr.simulate(1.0, false)
		if not pr.raid.is_empty() and int(pr.raid.room) != pr.find_room_of_type("airlock").id:
			moved_on = true
	check(moved_on and pr.pearls < 1000, "без защитников пираты грабят и идут дальше")
	# сильные защитники отбивают налёт
	var pd2 = load("res://scripts/game_state.gd").new()
	pd2.new_game()
	pd2.set_difficulty("normal")
	pd2.start_raid()
	var al2: Dictionary = pd2.find_room_of_type("airlock")
	for c in pd2.colonists:
		c.str = 10
		c["end"] = 10
		pd2.send_help(c, al2)
	var p_before: int = pd2.pearls
	for i in 120:
		pd2.resources.oxygen = 100.0
		pd2.resources.food = 100.0
		pd2.simulate(1.0, false)
		if pd2.raid.is_empty():
			break
	check(pd2.raid.is_empty() and pd2.pearls > p_before and al2.incident <= 0.0, "защитники отбили налёт и получили награду")
	check(pd2.raider_bodies.size() >= 2, "тела пиратов остались лежать")
	var pb2: int = pd2.pearls
	var lt: Dictionary = pd2.loot_raider(pd2.raider_bodies[0])
	check(pd2.pearls > pb2 and lt.get("pearls", 0) > 0, "обыск тела пирата даёт добычу")
	pd2.raider_bodies[0].until = pd2.now() - 1.0
	var nb: int = pd2.raider_bodies.size()
	pd2._expire_raider_bodies()
	check(pd2.raider_bodies.size() == nb - 1, "тело пирата со временем исчезает")
	pr.free(); pd2.free()
	# беда без людей: разгорается, перекидывается на соседа и сама выгорает
	var bz = load("res://scripts/game_state.gd").new()
	bz.new_game()
	var oxr: Dictionary = bz.find_room_of_type("oxygen")
	for c in bz.colonists:
		c.room = -1
	bz.start_hazard(oxr, "fire")
	var spread_seen := false
	var burned_out := false
	for i in 400:
		bz.resources.oxygen = 100.0
		bz.resources.food = 100.0
		bz.simulate(1.0, false)
		for c in bz.colonists:
			c.help = -1
		if bz.rooms.filter(func(r): return r.incident > 0.0 and r.id != oxr.id).size() > 0:
			spread_seen = true
		if oxr.incident <= 0.0:
			burned_out = true
	check(spread_seen, "пожар без людей перекинулся на соседний отсек")
	check(burned_out, "пожар без людей в отсеке выгорел сам")
	check(oxr.get("damaged", false), "выгоревший отсек сломан")
	var ct_bad: float = bz.cycle_time(bz.find_room_of_type("reactor"))
	bz.pearls = 1000
	check(bz.repair(oxr) and not oxr.get("damaged", false), "ремонт за жемчуг")
	bz.free()
	# новые отсеки и характеристики
	var nw = load("res://scripts/game_state.gd").new()
	nw.new_game()
	nw.set_difficulty("calm")
	var nc: Dictionary = nw.colonists[0]
	check(nc.has("end") and nc.has("cha") and nc.has("luck") and nc.has("mood"), "у колониста выносливость, обаяние, удача, настроение")
	check(not nw.can_build_at("turbine", 7, 1), "турбина не строится выше 7-го ряда")
	var gym: Dictionary = nw._add_room("gym", 8, 1)
	nc.room = gym.id
	nc.str = 1
	nc.end = 1
	for i in int(nw.train_time(gym) * 1.5) + 5:
		nw.resources.energy = 100.0
		nw.simulate(1.0, false)
	check(nc.str + nc.end >= 3, "спортзал качает силу/выносливость")
	var tb: Dictionary = nw._add_room("turbine", 10, 1)
	check(nw.cycle_time(tb) < INF, "турбина работает без людей")
	var ws: Dictionary = nw._add_room("workshop", 12, 1)
	nw.colonists[1].room = ws.id
	ws.ready = true
	var nscrap: int = int(nw.materials.get("scrap", 0))
	nw.collect(ws)
	check(int(nw.materials.get("scrap", 0)) > nscrap, "мастерская без заказа делает металлолом")
	nc.room = -1
	nc.cha = 10
	check(absf(nw.trade_discount() - 0.3) < 0.001, "обаяние 10 → скидка 30%")
	var mood0: float = nw.colonists[1].mood
	nw._add_room("lounge", 0, 3)
	for i in 300:
		nw.resources.oxygen = 100.0
		nw.resources.food = 100.0
		nw.resources.energy = 100.0
		nw.simulate(1.0, false)
	check(nw.mood_bonus() >= 10.0 and nw.colonists[1].mood > mood0 + 20.0, "комната отдыха поднимает настроение (%.0f → %.0f)" % [mood0, nw.colonists[1].mood])
	nw.free()
	sv.save_game()
	var sv2 = load("res://scripts/game_state.gd").new()
	sv2.load_game()
	check(sv2.difficulty == "survival", "режим сохраняется")
	sv.free(); sv2.free(); cm.free()

	# сюжет: жилой отсек, построенный в туториале (до главы), засчитывается
	var stg = load("res://scripts/game_state.gd").new()
	stg.new_game()
	stg._add_room("living", 1, 1)
	stg.story_index = 1
	stg.story_count = 0
	check(stg.story_ready(), "глава «построй жилой отсек» видит уже построенный")
	stg.story_index = 2
	stg.story_count = 0
	check(stg.story_ready(), "глава «поставь колониста» видит уже работающих")
	# значок исследований: только когда реально можно начать
	check(not stg.can_start_any_research(), "без лаборатории значка исследований нет")
	stg._add_room("lab", 3, 1)
	stg.science = 0
	check(not stg.can_start_any_research(), "без науки значка исследований нет")
	stg.science = 1000
	check(stg.can_start_any_research(), "наука есть — значок горит")
	stg.start_research("efficient_reactors")
	check(not stg.can_start_any_research(), "исследование идёт — значка нет")
	check(stg.research_finish_cost() == 3, "ускорение 10 минут стоит 3 кристалла (%d)" % stg.research_finish_cost())
	stg.free()
	# открытие отсеков: глава сюжета ИЛИ население
	var ul = load("res://scripts/game_state.gd").new()
	ul.new_game()
	check(not ul.is_unlocked("radio"), "радио закрыто в начале")
	ul.story_index = Defs.unlock_chapter("radio")
	check(ul.is_unlocked("radio"), "глава открыла радио")
	ul.story_index = 0
	while ul.colonists.size() < int(Defs.ROOMS.radio.unlock_pop):
		ul.colonists.append(ul._make_colonist())
	check(ul.is_unlocked("radio"), "радио открылось по населению без сюжета")
	# разовая цель, выполненная заранее, засчитывается
	ul.stats["upgrade"] = 1
	for i in Defs.STORY.size():
		if Defs.STORY[i].goal[0] == "upgrade":
			ul.story_index = i
	ul.story_count = 0
	check(ul.story_ready(), "«улучши отсек» засчитан, если улучшал раньше")
	check(ul.arrival_speed() == 0.0, "без радио после 8 человек никто не приходит")
	ul._add_room("radio", 1, 1)
	check(ul.arrival_speed() > 0.0, "пустое радио слабо, но вещает")
	ul.free()

	# сохранение и загрузка новых систем + старые сохранения без них
	var sv_a = load("res://scripts/game_state.gd").new()
	sv_a.new_game()
	sv_a.add_material("coral", 7)
	sv_a.learn_blueprint("trident:rare")
	sv_a.projects = {"garden_dome": 2}
	sv_a.chains = {"lost_diver": {"step": 1, "count": 0}}
	sv_a.pet_xp = {"clownfish": 120}
	sv_a.piggy = 77.5
	sv_a.trophies = {"harvest": 2}
	sv_a.event_tokens = 42.0
	sv_a.event_bought = {"gold_crate": 1}
	sv_a.colonists[0].traits = ["genius"]
	var sv_dock: Dictionary = sv_a._add_room("dock", 3, 1)
	sv_a.launch_exploration(sv_dock.id, 0, [sv_a.colonists[1].id], true)
	var sv_ws: Dictionary = sv_a._add_room("workshop", 7, 1)
	sv_a.colonists[2].room = sv_ws.id
	sv_a.add_material("scrap", 10); sv_a.add_material("shell", 10); sv_a.pearls = 5000
	sv_a.start_craft(sv_ws, "spear:common")
	sv_a.save_game()
	var sv_b = load("res://scripts/game_state.gd").new()
	check(sv_b.load_game(), "сохранение с новыми системами загружается")
	check(int(sv_b.materials.get("coral", 0)) == 7 and "trident:rare" in sv_b.blueprints, "материалы и чертежи сохранились")
	check(sv_b.project_stage("garden_dome") == 2 and int(sv_b.chain_state("lost_diver").step) == 1, "проекты и цепочки сохранились")
	check(sv_b.pet_level("clownfish") == 2 and absf(sv_b.piggy - 77.5) < 0.01, "питомец и копилка сохранились")
	check("genius" in sv_b.colonists[0].traits, "черты сохранились")
	check(sv_b.trophy_level("harvest") == 2 and sv_b.event_token_count() == 42 and sv_b.event_bought_count("gold_crate") == 1, "трофеи и жетоны сохранились")
	check(not sv_b.expeditions.is_empty() and sv_b.is_exploring(sv_b.expeditions[0]), "исследование продолжается после загрузки")
	check(not sv_b.craft_job(sv_b.get_room(sv_ws.id)).is_empty(), "заказ мастерской сохранился")
	# старое сохранение: убираем новые поля
	var raw = JSON.parse_string(FileAccess.get_file_as_string(sv_a.SAVE_PATH))
	for k in ["materials", "blueprints", "craft_jobs", "projects", "pet_xp", "chains", "piggy", "wheel", "offers", "offers_seen", "storm_until", "storm_next"]:
		raw.meta.erase(k)
	for sv_col in raw.colonists:
		sv_col.erase("traits")
	var fw := FileAccess.open(sv_a.SAVE_PATH, FileAccess.WRITE)
	fw.store_string(JSON.stringify(raw))
	fw.close()
	var sv_c = load("res://scripts/game_state.gd").new()
	check(sv_c.load_game(), "старое сохранение загружается")
	check(sv_c.blueprints.size() == Defs.START_BLUEPRINTS.size() and sv_c.materials.is_empty() and sv_c.projects.is_empty(), "старое сохранение: стартовые чертежи, пустые материалы")
	sv_c.simulate(1.0, false)
	check(true, "старое сохранение: симуляция без ошибок")
	sv_a.free(); sv_b.free(); sv_c.free()

	# копилка, колесо удачи, наборы по поводу
	var mg = load("res://scripts/game_state.gd").new()
	mg.new_game()
	check(not mg.piggy_can_break(), "копилка пуста")
	for i in 2000:
		mg._piggy_add(mg.PIGGY_PER_COLLECT)
	check(mg.piggy_can_break() and mg.piggy <= mg.PIGGY_CAP, "копилка наполнилась (не больше предела)")
	var pig: int = mg.break_piggy()
	check(pig >= 60 and mg.piggy == 0.0, "копилку разбили")
	var wsum := 0.0
	for o in mg.wheel_odds():
		wsum += o
	check(absf(wsum - 1.0) < 0.001, "шансы колеса в сумме 100%")
	var widx: int = mg.spin_wheel("free")
	check(widx >= 0 and widx < Defs.WHEEL.size(), "бесплатное вращение")
	check(mg.spin_wheel("free") == -1, "второе бесплатное — только завтра")
	mg.crystals = 100
	check(mg.spin_wheel("paid") >= 0 and mg.crystals == 80, "платное вращение за кристаллы")
	mg.grant_wheel(widx)
	mg.offer_trigger("offer_hero")
	check(mg.offer_active("offer_hero") and mg.offer_left("offer_hero") > 86000.0, "набор героя на 24 часа")
	mg.close_offer("offer_hero")
	mg.offer_trigger("offer_hero")
	check(not mg.offer_active("offer_hero"), "набор показывается только один раз")
	mg.free()

	# цепочки заданий
	var ch = load("res://scripts/game_state.gd").new()
	ch.new_game()
	var cd0: Dictionary = Defs.CHAINS[0]
	check(not ch.chain_ready(cd0), "цепочка: шаг 1 не выполнен")
	ch.track("expedition_reef")
	check(ch.chain_ready(cd0), "цепочка: шаг 1 выполнен")
	var chp: int = ch.pearls
	ch.claim_chain(cd0)
	check(ch.pearls == chp + 300 and int(ch.chain_state(cd0.id).step) == 1, "награда за шаг, следующий шаг")
	ch.free()

	# морская буря и уровни питомцев
	var sb = load("res://scripts/game_state.gd").new()
	sb.new_game()
	while sb.colonists.size() < 8:
		sb.colonists.append(sb._make_colonist())
	sb.storm_next = sb.now() - 1.0
	sb._tick_storm()
	check(sb.storm_active() and sb.storm_left() > 7000.0, "буря началась на 2 часа")
	check(sb.storm_next > sb.storm_until, "следующая буря — позже")
	sb.grant_pet("clownfish")
	sb.set_pet("clownfish")
	check(sb.pet_level() == 1 and sb.pet_power() == 1.0, "питомец 1 уровня")
	sb._pet_gain(600)
	check(sb.pet_level() >= 4 and sb.pet_power() > 1.5, "питомец вырос, бонус сильнее")
	sb.free()

	# проекты колонии
	var pj = load("res://scripts/game_state.gd").new()
	pj.new_game()
	check(not pj.can_build_project("garden_dome"), "проект закрыт до нужного уровня колонии")
	pj.colony_level = 6
	pj.pearls = 100000
	var pjc: Dictionary = pj.project_cost("garden_dome")
	for m in pjc.materials:
		pj.add_material(m, int(pjc.materials[m]))
	var pj_food0: float = pj.production_amount(pj.find_room_of_type("farm"))
	check(pj.build_project_stage("garden_dome") and pj.project_stage("garden_dome") == 1, "этап проекта построен")
	check(pj.production_amount(pj.find_room_of_type("farm")) > pj_food0, "сад даёт больше еды")
	check(int(pj.project_cost("garden_dome").pearls) > int(pjc.pearls), "следующий этап дороже")
	# мастерство после всех этапов
	pj.projects["garden_dome"] = Defs.PROJECT_STAGES
	var pj_m1: Dictionary = pj.project_cost("garden_dome")
	check(not pj_m1.is_empty(), "после 3 этапов доступно мастерство")
	for m in pj_m1.materials:
		pj.add_material(m, int(pj_m1.materials[m]))
	var pj_food3: float = pj.production_amount(pj.find_room_of_type("farm"))
	pj.pearls = 10000000
	check(pj.build_project_stage("garden_dome") and pj.project_mastery("garden_dome") == 1, "уровень мастерства построен")
	check(pj.production_amount(pj.find_room_of_type("farm")) > pj_food3, "мастерство усиливает бонус")
	check(int(pj.project_cost("garden_dome").pearls) > int(pj_m1.pearls), "мастерство дорожает")
	# обмен лишних материалов
	pj.materials = {"scrap": 30, "coral": 1}
	pj.pearls = 5000
	var pj_need := {"coral": 4, "shell": 1}
	var pj_pl: Dictionary = pj.fill_plan(pj_need)
	check(not pj_pl.is_empty() and int(pj_pl.made) == 4 and int(pj_pl.take.scrap) == 12, "обмен: 4 недостающих из 12 лома")
	check(pj.fill_materials(pj_need) and pj.has_materials(pj_need) and int(pj.materials.scrap) == 18 and pj.pearls == 5000 - 4 * pj.EXCHANGE_PEARLS, "обмен выполнен, жемчуг списан")
	check(pj.fill_plan({"abyss_pearl": 3, "scrap": 18}).is_empty(), "без лишнего обменять нельзя")
	pj.projects["deep_bathyscaphe"] = 30
	check(pj.project_return_mult() >= 0.4 - 0.001, "путь домой не короче 40%")
	pj.free()

	# магазин события
	var evg = load("res://scripts/game_state.gd").new()
	evg.new_game()
	evg.refresh_daily_systems()
	check(evg.event_token_count() == 0 and not evg.can_buy_event("silver_crate"), "без жетонов купить нельзя")
	var ev_goal: String = evg.weekly_event().goal
	evg.track(ev_goal, int(evg.weekly_event().tiers[-1]))
	check(abs(evg.event_token_count() - Defs.EVENT_TOKENS_FULL) <= 1, "за всё задание недели — ~300 жетонов")
	var ev_mod: String = evg.weekly_mod()
	check(evg.buy_event("trophy") and evg.trophy_level(ev_mod) == 1, "трофей куплен")
	check(not evg.can_buy_event("trophy"), "трофей — один раз за неделю")
	check(evg.trophy_bonus(ev_mod) > 1.0, "трофей даёт бонус")
	var ev_cr: int = evg.crates.silver
	check(evg.buy_event("silver_crate") and evg.crates.silver == ev_cr + 1, "серебряный ящик за жетоны")
	evg.pearls = 100000
	var ev_p1: int = evg.event_cache_price()
	var ev_t0: int = evg.event_token_count()
	check(evg.buy_event_cache() and evg.event_token_count() == ev_t0 + Defs.EVENT_CACHE_TOKENS, "жетоны за жемчуг")
	check(evg.event_cache_price() == ev_p1 * 2, "жетоны за жемчуг дорожают вдвое")
	var ev_t1: int = evg.event_token_count()
	evg.grant({"event_pass": true}, "t")
	check(evg.event_pass_active() and evg.event_token_count() == ev_t1 * 2, "пропуск события удваивает жетоны")
	evg.weekly_week = -5
	evg.refresh_daily_systems()
	check(evg.event_token_count() == 0 and evg.trophy_level(ev_mod) == 1, "жетоны сгорают, трофей остаётся")
	evg.free()

	# черты характера
	var tr_tg = load("res://scripts/game_state.gd").new()
	tr_tg.traits_enabled = true
	tr_tg.new_game()
	var tr_tc: Dictionary = tr_tg.colonists[0]
	tr_tc.traits = []
	var tr_luck0: int = tr_tg.stat(tr_tc, "luck")
	var tr_prot0: float = tr_tg.protection(tr_tc)
	tr_tc.traits = ["lucky", "brave"]
	check(tr_tg.stat(tr_tc, "luck") == tr_luck0 + 3, "везунчик: +3 удачи")
	check(tr_tg.protection(tr_tc) > tr_prot0, "храбрец: меньше урона")
	var tr_trm: Dictionary = tr_tg.get_room(tr_tc.room) if tr_tc.room >= 0 else tr_tg.find_room_of_type("reactor")
	tr_tc.room = tr_trm.id
	tr_tc.traits = []
	var tr_pw0: float = tr_tg.room_power(tr_trm)
	tr_tc.traits = ["lazy"]
	check(tr_tg.room_power(tr_trm) < tr_pw0, "лентяй работает медленнее")
	var tr_ta: Dictionary = tr_tg._make_colonist()
	var tr_tb: Dictionary = tr_tg._make_colonist()
	tr_ta.traits = ["genius", "cheerful"]
	tr_tb.traits = ["tough"]
	var tr_kids_ok := true
	for i in 30:
		var tr_kt: Array = tr_tg._inherit_traits(tr_ta, tr_tb)
		if tr_kt.size() > 2:
			tr_kids_ok = false
		for tt in tr_kt:
			if not tt in Defs.TRAITS:
				tr_kids_ok = false
	check(tr_kids_ok, "дети наследуют не больше двух черт")
	tr_tg.traits_enabled = false
	tr_tg.free()

	# таинственный незнакомец
	var sg = load("res://scripts/game_state.gd").new()
	sg.new_game()
	while sg.colonists.size() < 6:
		sg.colonists.append(sg._make_colonist())
	sg.stranger_timer = 0.0
	sg.simulate(1.0, false)
	check(not sg.stranger.is_empty(), "незнакомец появился")
	var got_s: Dictionary = sg.catch_stranger()
	check(not got_s.is_empty() and sg.stranger.is_empty(), "поймали незнакомца — награда")
	sg.stranger_timer = 0.0
	sg.simulate(1.0, false)
	sg.clock_offset += 10.0
	sg.simulate(1.0, false)
	check(sg.stranger.is_empty(), "незнакомец ушёл, если не успели")
	sg.stranger_timer = 0.0
	sg.simulate(1.0, true)
	check(sg.stranger.is_empty(), "вне игры незнакомец не приходит")
	sg.clock_offset -= 10.0
	sg.free()

	# крафт по чертежам
	var cg = load("res://scripts/game_state.gd").new()
	cg.new_game()
	var cws: Dictionary = cg._add_room("workshop", 3, 1)
	cg.colonists[0].room = cws.id
	check("spear:common" in cg.blueprints, "стартовые чертежи есть")
	check(not cg.can_craft(cws, "spear:common"), "без материалов крафт нельзя")
	for m in Defs.recipe("spear:common"):
		cg.add_material(m, int(Defs.recipe("spear:common")[m]))
	cg.pearls = 1000
	check(cg.start_craft(cws, "spear:common"), "крафт начался")
	check(cg.pearls == 700 and int(cg.materials.get("shell", 0)) == 0, "материалы и жемчуг списаны")
	check(not cg.start_craft(cws, "spear:common"), "мастерская занята")
	var items_n: int = cg.items.size()
	cg.clock_offset += 3600.0
	check(cg.craft_ready(cws), "вещь готова")
	var made: Dictionary = cg.claim_craft(cws)
	check(cg.items.size() == items_n + 1 and made.base == "spear" and made.rarity == "common", "получили костяное копьё")
	check(not cg.can_craft(cws, "trident:rare"), "без чертежа нельзя")
	check("Blueprint" in cg.learn_blueprint("trident:rare") or "trident:rare" in cg.blueprints, "чертёж выучен")
	var lg := Defs.recipe("abyss_armor:legendary")
	check(lg.has("abyss_pearl") and lg.has("kraken_ink"), "легендарный рецепт требует глубинных материалов")
	cg.clock_offset -= 3600.0
	cg.free()

	# исследование как в Fallout: без таймера, игрок сам отзывает
	var xg = load("res://scripts/game_state.gd").new()
	xg.new_game()
	xg.set_difficulty("normal")
	var x_exd: Dictionary = xg._add_room("dock", 3, 1)
	var x_c0: Dictionary = xg.colonists[0]
	var x_c1: Dictionary = xg.colonists[1]
	x_c0.health = 100.0
	x_c1.health = 100.0
	check(xg.launch_exploration(x_exd.id, 0, [x_c0.id, x_c1.id], true), "исследование началось")
	var x_xe: Dictionary = xg.expedition_at(x_exd.id)
	check(xg.is_exploring(x_xe) and not xg.expedition_done(x_xe), "отряд снаружи, таймера нет")
	var x_off0: float = xg.clock_offset
	xg.clock_offset += 3600.0
	xg._tick_explorations()
	check(x_xe.events.size() >= 10, "за час в лесу водорослей ~20 событий (%d)" % x_xe.events.size())
	xg.recall_exploration(x_xe)
	check(x_xe.state == "return" and absf(float(x_xe.end) - xg.now() - 1800.0) < 1.0, "обратный путь — половина времени")
	var x_ev_n: int = x_xe.events.size()
	xg.clock_offset += 600.0
	xg._tick_explorations()
	check(x_xe.events.size() == x_ev_n, "на обратном пути событий нет")
	xg.clock_offset += 1300.0
	check(xg.expedition_done(x_xe), "отряд вернулся")
	var x_pearls0: int = xg.pearls
	xg.claim_expedition(x_xe)
	check(xg.expeditions.is_empty() and x_c0.room == -1, "добыча забрана, отряд дома")
	check(xg.pearls >= x_pearls0, "жемчуг из исследования")
	# автовозврат при тяжёлом ранении
	x_c0.health = 30.0
	xg.launch_exploration(x_exd.id, 4, [x_c0.id], true)
	var x_xe2: Dictionary = xg.expedition_at(x_exd.id)
	xg.clock_offset += 6 * 3600.0
	xg._tick_explorations()
	check(not x_xe2 in xg.expeditions or x_xe2.state == "return", "раненый — отряд сам повернул домой")
	if x_xe2 in xg.expeditions:
		xg.expeditions.erase(x_xe2)
	# без автовозврата в глубине можно погибнуть
	var x_c2: Dictionary = xg.colonists[2]
	x_c2.health = 20.0
	x_c2.room = -1
	xg.launch_exploration(x_exd.id, 4, [x_c2.id], false)
	xg.clock_offset += 12 * 3600.0
	xg._tick_explorations()
	check(xg.expedition_at(x_exd.id).is_empty() and xg.fallen.size() >= 1, "отряд погиб снаружи, тело можно оживить")
	xg.clock_offset = x_off0
	xg.free()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.SAVE_PATH))
	g.free(); g2.free(); g3.free()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)

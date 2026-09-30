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
	g.rng.seed = 1
	g.new_game()
	check(g.rooms.size() == 6, "стартовая база из 6 отсеков")
	check(g.colonists.size() == 4, "4 стартовых колониста")

	check(g.can_build_at("living", 6, 2) == false, "нельзя строить без соединения")
	check(g.can_build_at("elevator", 5, 2), "лифт под лифтом")
	check(g.build("elevator", 5, 2), "строим лифт")
	check(g.can_build_at("living", 6, 2), "жилой отсек рядом с лифтом")
	var pearls_before: int = g.pearls
	check(g.build("living", 6, 2), "строим жилой отсек")
	check(g.pearls == pearls_before - 100, "жемчуг списан")
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
	check(not g.assign(free, g.find_room_of_type("living")), "в жилом отсеке не работают")

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
	check(eco.pearls == pd + 100 and not eco.daily_available(), "награда дня 1 получена, повторно нельзя")
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
	check(ex.quests.size() == 3, "3 ежедневных задания")
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
	check(ex2.season_xp == 250 and ex2.season_pass and ex2.quests.size() == 3, "сезон и задания сохраняются")
	ex.free(); ex2.free()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(g.SAVE_PATH))
	g.free(); g2.free(); g3.free()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)

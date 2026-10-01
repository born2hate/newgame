extends SceneTree
## Симулятор экономики: бот «играет» неделю и печатает, как растёт колония.
## godot --headless --path . --script res://tools/economy_sim.gd -- [free|ads|starter] [дни]
## Режим игры: сессии по SESSION_MIN минут SESSIONS_PER_DAY раз в день, остальное — офлайн.

const SESSION_MIN := 12
const SESSIONS_PER_DAY := 4

var g
var profile := "free"
var earned := {"pearls": 0, "crystals": 0}
var ads_watched := 0
var starve := 0
var src := {"collect": 0, "manage": 0, "sim": 0}
var popsrc := {"offline": 0, "sim": 0, "manage": 0, "session_start": 0}
var csrc := {}
var _c0 := 0

func _cs() -> void:
	_c0 = g.crystals

func _ce(key: String) -> void:
	if g.crystals > _c0:
		csrc[key] = csrc.get(key, 0) + g.crystals - _c0
	_c0 = g.crystals

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	profile = args[0] if args.size() > 0 else "free"
	var days := int(args[1]) if args.size() > 1 else 7
	g = load("res://scripts/game_state.gd").new()
	g.rng.seed = 42
	seed(42)
	g.new_game()
	g.set_difficulty("normal")
	g.mode_chosen = true
	g.tutorial_done = true
	if profile == "starter":
		g.grant(load("res://scripts/store.gd").IAP[0].reward, "")
	print("profile=%s  sessions=%d×%d min/day" % [profile, SESSIONS_PER_DAY, SESSION_MIN])
	print("day  pop  kids  rooms  lvl  colLv  pearls  cryst  items  story  earned_p  ads  starv")
	var gap := 86400.0 / SESSIONS_PER_DAY - SESSION_MIN * 60.0
	for d in days:
		for s in SESSIONS_PER_DAY:
			_session()
			var pb: int = g.pearls
			var popb: int = g.colonists.size()
			g.clock_offset += gap
			g._apply_offline(gap)
			popsrc.offline += g.colonists.size() - popb
			if OS.get_cmdline_user_args().has("debug"):
				print("  offline +%d pearls, pop %d -> %d, cap %d, radio %.1f, arr_speed %.2f" % [g.pearls - pb, popb, g.colonists.size(), g.population_cap(), g.type_power("radio"), g.arrival_speed()])
		var lv := 0
		for c in g.colonists:
			lv += int(c.level)
		var kids: int = g.colonists.filter(func(c): return c.get("child", false)).size()
		print("%3d  %3d  %4d  %5d  %3.1f  %5d  %6d  %5d  %5d  %5d  %8d  %3d  %4d" % [d + 1, g.colonists.size(), kids, g.rooms.size(),
			float(lv) / maxf(1, g.colonists.size()), g.colony_level, g.pearls, g.crystals, g.items.size(),
			g.story_index, earned.pearls, ads_watched, starve])
	var have := {}
	for r in g.rooms:
		have[r.type] = have.get(r.type, 0) + 1
	print("rooms: ", have)
	var lv := {}
	for r in g.rooms:
		lv[r.level] = lv.get(r.level, 0) + 1
	print("room levels: ", lv)
	print("pearl sources: ", src)
	print("crystal sources: ", csrc)
	print("pop sources: ", popsrc, " births ", g.stats.get("birth", 0))
	quit()

func _session() -> void:
	g.refresh_daily_systems()
	_cs()
	if g.daily_available():
		g.claim_daily()
	_ce("daily")
	var ads: bool = profile != "free"
	if ads and g.free_crate_ready() and g.ads_left() > 0:
		g.register_ad()
		g.claim_free_crate()
		ads_watched += 1
	_ce("free_crate")
	if ads and not g.boost_active() and g.ads_left() > 0:
		g.register_ad()
		g.start_boost()
		ads_watched += 1
	var pc: int = g.pearls
	_cs()
	for t in g.crates.keys():
		while g.crates[t] > 0:
			g.open_crate(t)
	_ce("crates")
	if OS.get_cmdline_user_args().has("debug") and g.pearls - pc > 1000:
		print("  crates/daily +%d" % (g.pearls - pc))
	var steps: int = SESSION_MIN * 60
	for i in steps:
		var p0: int = g.pearls
		var n0: int = g.colonists.size()
		g.clock_offset += 1.0
		_cs()
		g.simulate(1.0, false)
		_ce("sim(boss/raid/offline)")
		src.sim += maxi(0, g.pearls - p0)
		popsrc.sim += g.colonists.size() - n0
		var p1: int = g.pearls
		if g.resources.oxygen <= 0.0 or g.resources.food <= 0.0:
			starve += 1
		# игрок нажимает на готовые отсеки примерно раз в 4 секунды
		if i % 4 == 0:
			_cs()
			for r in g.rooms:
				if r.ready:
					g.collect(r)
			_ce("collect(deep)")
		src.collect += maxi(0, g.pearls - p1)
		var p2: int = g.pearls
		var n2: int = g.colonists.size()
		if i % 15 == 0:
			_manage(ads)
		popsrc.manage += g.colonists.size() - n2
		src.manage += maxi(0, g.pearls - p2)
		earned.pearls += maxi(0, g.pearls - p0)

func _manage(ads: bool) -> void:
	# аварии и налёт — отправляем свободных и ближайших
	for r in g.rooms:
		if r.incident > 0.0:
			for c in g.colonists:
				if not c.get("child", false) and c.room != g.ON_EXPEDITION and g.responders(r).size() < 3:
					g.send_help(c, r)
	_cs()
	for q in g.quests:
		g.claim_quest(q)
	_ce("quests")
	if g.story_ready():
		g.claim_story()
	_ce("story")
	for a in Defs.ACHIEVEMENTS:
		if g.achievement_ready(a):
			g.claim_achievement(a)
	_ce("achievements")
	for t in g.season_tier():
		g.claim_season(t, false)
	_ce("season")
	_cs()
	for i in range(g.fallen.size() - 1, -1, -1):
		g.revive(g.fallen[i])
	for b in g.raider_bodies.duplicate():
		g.loot_raider(b)
	_ce("raider_bodies")
	if not g.trader.is_empty():
		for i in g.trader.offers.size():
			if g.can_trade(i) and g.trader.offers[i].give.has("food"):
				g.trade(i)
	# исследования
	if g.research_current.is_empty():
		for rd in Defs.RESEARCH:
			if g.research_available(rd.id) and g.science >= rd.cost:
				g.start_research(rd.id)
				break
	# экспедиции
	for r in g.rooms:
		if r.type != "dock":
			continue
		var e: Dictionary = g.expedition_at(r.id)
		if not e.is_empty():
			if g.expedition_done(e):
				_cs()
				g.claim_expedition(e)
				_ce("expeditions")
			elif ads and not e.get("ad_used", false) and g.ads_left() > 0:
				g.register_ad()
				g.cut_expedition(e, 1800.0)
				ads_watched += 1
			continue
		var crew: Array = g.available_crew().filter(func(c): return c.room == -1 or c.health > 70.0)
		if crew.size() >= 4:
			crew.sort_custom(func(a, b): return g.stat(a, "str") > g.stat(b, "str"))
			var zone := 0
			for z in Defs.ZONES.size():
				if g.zone_unlocked(z) and g.expedition_chance(z, [crew[0].id, crew[1].id]) >= 0.8:
					zone = z
			g.launch_expedition(r.id, zone, [crew[0].id, crew[1].id])
	_staff()
	_build()

func _staff() -> void:
	# пара в жилом отсеке, если есть место для ребёнка
	if g.colonists.size() < g.population_cap():
		for r in g.rooms:
			if r.type == "living" and g.workers_in(r).size() < 2:
				var idle: Array = g.colonists.filter(func(c): return c.room == -1 and not c.get("child", false) and c.get("help", -1) == -1)
				if idle.is_empty():
					idle = g.colonists.filter(func(c): return not c.get("child", false) and c.room >= 0 and g.get_room(c.room).type in ["reactor", "farm", "oxygen"] and g.workers_in(g.get_room(c.room)).size() > 1)
				if not idle.is_empty():
					g.assign(idle[0], r)
				break
	for c in g.colonists:
		if c.room != -1 or c.get("child", false) or c.get("help", -1) != -1:
			continue
		var best: Dictionary = g.best_room_for(c)
		if not best.is_empty():
			g.assign(c, best)
			continue
		for r in g.rooms:
			if g.slots(r) > g.workers_in(r).size() and Defs.ROOMS[r.type].has("stat"):
				g.assign(c, r)
				break

func _rate(res: String) -> float:
	var t := 0.0
	for r in g.rooms:
		var def: Dictionary = Defs.ROOMS[r.type]
		if def.get("produces", "") == res:
			var ct: float = g.cycle_time(r)
			if ct < INF:
				t += g.production_amount(r) / ct
	return t

func _staffed(t: String) -> bool:
	for r in g.rooms:
		if r.type == t and g.workers_in(r).size() < g.slots(r):
			return false
	return true

func _build() -> void:
	var need := ""
	var pop: int = g.colonists.size()
	var use_o2: float = g.O2_PER_COLONIST * pop
	var use_food: float = g.FOOD_PER_COLONIST * pop
	if pop >= g.population_cap() - 1 and pop < g.MAX_POP:
		need = "living"
	elif _rate("oxygen") < use_o2 * 1.3 and _staffed("oxygen"):
		need = "oxygen"
	elif _rate("food") < use_food * 1.3 and _staffed("farm"):
		need = "farm"
	elif g.resources.energy < 30.0 and _staffed("reactor"):
		need = "reactor"
	elif g.is_unlocked("pearl") and g.count_of("pearl") < 2:
		need = "pearl"
	else:
		for t in ["dock", "lab", "storage", "pearl", "medbay", "radio", "kitchen", "gym", "school", "lounge", "workshop", "armory", "aquarium", "turbine", "observatory"]:
			if g.is_unlocked(t) and g.count_of(t) == 0:
				need = t
				break
		if need == "" and g.is_unlocked("pearl") and g.count_of("pearl") < 3:
			need = "pearl"
	if OS.get_cmdline_user_args().has("debug2"):
		print("need=", need, " unlocked=", g.is_unlocked(need) if need != "" else false, " cost=", g.build_cost(need) if need != "" else 0, " spots=", g.build_spots(need).size() if need != "" else 0, " pearls=", g.pearls)
	if need != "" and g.is_unlocked(need):
		var cost: int = g.build_cost(need)
		if g.pearls >= cost:
			var spots: Array = g.build_spots(need)
			if not spots.is_empty():
				g.build(need, spots[0].x, spots[0].y)
				return
			# мест нет — лифт на этаж ниже
			var el: Array = g.build_spots("elevator")
			el.sort_custom(func(a, b): return a.y > b.y)
			if not el.is_empty() and g.pearls >= g.build_cost("elevator"):
				g.build("elevator", el[0].x, el[0].y)
			elif el.is_empty() and g.research_current.is_empty():
				# глубже — нужна исследованная зона
				for rd in Defs.RESEARCH:
					if rd.id.begins_with("deep") and g.research_available(rd.id) and g.science >= rd.cost:
						g.start_research(rd.id)
		return
	# иначе улучшаем самое дешёвое
	var cheapest := {}
	for r in g.rooms:
		if r.level < Defs.MAX_LEVEL and Defs.ROOMS[r.type].get("buildable", false) and r.type != "elevator" and g.colony_level >= int(Defs.LEVEL_GATE.get(r.level + 1, 0)):
			if cheapest.is_empty() or g.upgrade_cost(r) < g.upgrade_cost(cheapest):
				cheapest = r
	if not cheapest.is_empty() and g.pearls >= g.upgrade_cost(cheapest):
		g.upgrade(cheapest)

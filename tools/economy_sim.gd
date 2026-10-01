extends SceneTree
## Симулятор экономики: бот «играет» неделю и печатает, как растёт колония.
## godot --headless --path . --script res://tools/economy_sim.gd -- [free|ads|starter] [дни]
## Режим игры: сессии по SESSION_MIN минут SESSIONS_PER_DAY раз в день, остальное — офлайн.

var session_left := 9999
var SESSION_MIN := 12
var SESSIONS_PER_DAY := 4
var spend := {}
var starve_res := {"oxygen": 0, "food": 0, "energy0": 0}

func _spend(key: String, before: int) -> void:
	if g.pearls < before:
		spend[key] = spend.get(key, 0) + before - g.pearls

var g
var profile := "free"
var earned := {"pearls": 0, "crystals": 0}
var ads_watched := 0
var starve := 0
var src := {"collect": 0, "manage": 0, "sim": 0}
var popsrc := {"offline": 0, "sim": 0, "manage": 0, "session_start": 0}
var csrc := {}
var psrc := {}
var _p0 := 0
var isrc := {}
var ksrc := {}
var _c0 := 0
var _i0 := 0
var _k0 := 0
var idle_day := 0
var idle_min := 0
var dead_day := 0
var trace_s := 0
var trace_left := 16

func _cheapest_action() -> String:
	var best := ""
	var bc := 999999
	for t in Defs.ROOMS:
		if Defs.ROOMS[t].get("buildable", false) and g.is_unlocked(t) and t != "elevator" and g.build_cost(t) < bc:
			bc = g.build_cost(t)
			best = "build %s %d" % [t, bc]
	for r in g.rooms:
		if _can_up(r) and g.upgrade_cost(r) < bc:
			bc = g.upgrade_cost(r)
			best = "up %s %d" % [r.type, bc]
	return best
var idle_total := []

func _crates_total() -> int:
	var n := 0
	for t in g.crates:
		n += int(g.crates[t])
	return n

func _cs() -> void:
	_p0 = g.pearls
	_c0 = g.crystals
	_i0 = g.items.size()
	_k0 = _crates_total() + int(g.stats.get("crate", 0))

func _ce(key: String) -> void:
	if g.pearls > _p0:
		psrc[key] = psrc.get(key, 0) + g.pearls - _p0
	if g.crystals > _c0:
		csrc[key] = csrc.get(key, 0) + g.crystals - _c0
	if g.items.size() > _i0:
		isrc[key] = isrc.get(key, 0) + g.items.size() - _i0
	var k := _crates_total() + int(g.stats.get("crate", 0))
	if k > _k0:
		ksrc[key] = ksrc.get(key, 0) + k - _k0
	_cs()

## Есть ли сейчас у игрока хоть какое-то дело.
func _has_something_to_do() -> bool:
	for r in g.rooms:
		if r.ready:
			return true
	if g.quests_ready() > 0 or g.story_ready() or g.achievements_ready() > 0:
		return true
	for r in g.rooms:
		if r.type == "dock":
			var e: Dictionary = g.expedition_at(r.id)
			if e.is_empty() and g.available_crew().size() >= 2:
				return true
			if not e.is_empty() and g.expedition_done(e):
				return true
	if g.can_start_any_research():
		return true
	for t in Defs.ROOMS:
		if Defs.ROOMS[t].get("buildable", false) and g.is_unlocked(t) and g.pearls >= g.build_cost(t) and not g.build_spots(t).is_empty():
			return true
	for r in g.rooms:
		if r.level < Defs.MAX_LEVEL and Defs.ROOMS[r.type].get("buildable", false) and r.type != "elevator" and g.colony_level >= int(Defs.LEVEL_GATE.get(r.level + 1, 0)) and g.pearls >= g.upgrade_cost(r):
			return true
	return false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	profile = args[0] if args.size() > 0 else "free"
	var days := int(args[1]) if args.size() > 1 else 7
	for a in args:
		# s=2x5 — 2 захода по 5 минут в день
		if a.begins_with("s="):
			var parts: PackedStringArray = a.trim_prefix("s=").split("x")
			SESSIONS_PER_DAY = int(parts[0])
			SESSION_MIN = int(parts[1])
	g = load("res://scripts/game_state.gd").new()
	g.rng.seed = 42
	seed(42)
	g.new_game()
	g.set_difficulty("normal")
	g.mode_chosen = true
	g.tutorial_done = true
	# как в туториале: собрать реактор и построить жилой отсек
	var lsp: Array = g.build_spots("living")
	g.build("living", lsp[0].x, lsp[0].y)
	if profile == "starter":
		g.grant(load("res://scripts/store.gd").IAP[0].reward, "")
	print("profile=%s  sessions=%d×%d min/day" % [profile, SESSIONS_PER_DAY, SESSION_MIN])
	print("day  pop  kids  rooms  lvl  colLv  pearls  cryst  items  story  earned_p  ads  starv  dead%")
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
		print("%3d  %3d  %4d  %5d  %3.1f  %5d  %6d  %5d  %5d  %5d  %8d  %3d  %4d  %4.0f" % [d + 1, g.colonists.size(), kids, g.rooms.size(),
			float(lv) / maxf(1, g.colonists.size()), g.colony_level, g.pearls, g.crystals, g.items.size(),
			g.story_index, earned.pearls, ads_watched, starve, 100.0 * dead_day / (SESSIONS_PER_DAY * SESSION_MIN)])
		idle_day = 0
		dead_day = 0
		if OS.get_cmdline_user_args().has("res"):
			var pf := []
			for r in g.rooms:
				if r.type == "pearl":
					pf.append("L%d w%d ct%.0f %s" % [r.level, g.workers_in(r).size(), g.cycle_time(r), "dmg" if r.get("damaged", false) else ""])
			print("   E%.0f O%.0f F%.0f cap%.0f  pearl farms: %s" % [g.resources.energy, g.resources.oxygen, g.resources.food, g.storage_cap(), pf])
	var have := {}
	for r in g.rooms:
		have[r.type] = have.get(r.type, 0) + 1
	print("rooms: ", have)
	var lv := {}
	for r in g.rooms:
		lv[r.level] = lv.get(r.level, 0) + 1
	print("room levels: ", lv)
	print("pearl sources: ", src)
	print("pearl by source: ", psrc)
	print("pearl spent on: ", spend)
	print("materials: ", g.materials, " blueprints: ", g.blueprints.size(), " crafted: ", g.stats.get("craft", 0))
	var dc := {}
	for k in g.stats:
		if String(k).begins_with("death_"):
			dc[k] = g.stats[k]
	print("deaths: ", g.stats.get("deaths", 0), " ", dc, "  starve secs: ", starve_res)
	print("crystal sources: ", csrc)
	print("item sources: ", isrc)
	print("crate sources: ", ksrc)
	print("pop sources: ", popsrc, " births ", g.stats.get("birth", 0))
	quit()

func _session() -> void:
	trace_s += 1
	if trace_s > 1:
		trace_left -= 0
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
	# вернулись в игру — отзываем исследователей
	for e in g.expeditions.duplicate():
		if g.is_exploring(e):
			g.recall_exploration(e)
	for i in steps:
		session_left = steps - i
		var p0: int = g.pearls
		var n0: int = g.colonists.size()
		g.clock_offset += 1.0
		_cs()
		g.simulate(1.0, false)
		_ce("sim(boss/raid/offline)")
		src.sim += maxi(0, g.pearls - p0)
		popsrc.sim += g.colonists.size() - n0
		var idle_now := not _has_something_to_do()
		if idle_now:
			idle_day += 1
			idle_min += 1
		if i % 60 == 59:
			if idle_min >= 45:
				dead_day += 1
		if OS.get_cmdline_user_args().has("trace") and i % 60 == 59 and g.stats.get("collect", 0) < 2000 and trace_left > 0:
			var st: Dictionary = g.story_current()
			print("  t%02d:%02d  pearls %4d  sci %3d  pop %2d/%2d  idle %2ds  ch%d %s %d/%d  cheapest %s" % [trace_s, i / 60, g.pearls, g.science, g.colonists.size(), g.population_cap(), idle_min, g.story_index, st.goal[0] if not st.is_empty() else "-", g.story_progress(), st.goal[1] if not st.is_empty() else 0, _cheapest_action()])
			pass
		if i % 60 == 59:
			idle_min = 0
		var p1: int = g.pearls
		if g.resources.oxygen <= 0.0 or g.resources.food <= 0.0:
			starve += 1
			if g.resources.oxygen <= 0.0:
				starve_res.oxygen += 1
			if g.resources.food <= 0.0:
				starve_res.food += 1
		if g.resources.energy <= 0.0:
			starve_res.energy0 += 1
		# игрок нажимает на готовые отсеки примерно раз в 4 секунды
		if i % 4 == 0:
			_cs()
			for r in g.rooms:
				if r.ready:
					g.collect(r)
			_ce("collect")
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
	var pb: int = g.pearls
	for i in range(g.fallen.size() - 1, -1, -1):
		g.revive(g.fallen[i])
	_spend("revive", pb)
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
		var crew: Array = g.available_crew().filter(func(c): return c.health > 70.0)
		# перед уходом из игры — отправить исследовать до следующего захода
		if session_left < 60 and crew.size() >= 4 and not OS.get_cmdline_user_args().has("noexplore"):
			crew.sort_custom(func(a, b): return g.stat(a, "str") > g.stat(b, "str"))
			var ez := 0
			for z in Defs.ZONES.size():
				if g.zone_unlocked(z) and g.expedition_chance(z, [crew[0].id, crew[1].id]) >= 1.0:
					ez = z
			g.launch_exploration(r.id, ez, [crew[0].id, crew[1].id], true)
			continue
		if crew.size() >= 4:
			crew.sort_custom(func(a, b): return g.stat(a, "str") > g.stat(b, "str"))
			var zone := 0
			for z in Defs.ZONES.size():
				if g.zone_unlocked(z) and g.expedition_chance(z, [crew[0].id, crew[1].id]) >= 0.8 and g.expedition_at_risk(z, [crew[0].id, crew[1].id]).is_empty():
					zone = z
			g.launch_expedition(r.id, zone, [crew[0].id, crew[1].id])
	# мастерская: забрать готовое и начать лучшее, на что хватает
	for r in g.rooms:
		if r.type != "workshop":
			continue
		if g.craft_ready(r):
			g.claim_craft(r)
		if g.craft_job(r).is_empty():
			var best := ""
			for key in g.blueprints:
				if g.can_craft(r, key) and (best == "" or Defs.RARITIES.find(key.split(":")[1]) > Defs.RARITIES.find(best.split(":")[1])):
					best = key
			if best != "":
				var pc0: int = g.pearls
				g.start_craft(r, best)
				_spend("craft", pc0)
	_staff()
	var pb2: int = g.pearls
	var nb: int = int(g.stats.get("build", 0))
	_build()
	_spend("build" if int(g.stats.get("build", 0)) > nb else "upgrade", pb2)

const STAFF_ORDER := ["reactor", "oxygen", "farm", "pearl", "lab", "radio", "living", "medbay", "kitchen", "workshop", "gym", "school", "lounge", "armory"]

## Как живой игрок: сначала по одному человеку в важные отсеки, потом по второму и т. д.
## Уже работающих не трогаем без нужды (перевод сбрасывает опыт).
func _staff() -> void:
	var adults: Array = g.colonists.filter(func(c): return not c.get("child", false) and c.room != g.ON_EXPEDITION and c.get("help", -1) == -1)
	var want := {}
	var left := adults.size()
	var pass_n := 1
	while left > 0 and pass_n <= 6:
		for t in STAFF_ORDER:
			for r in g.rooms:
				if left <= 0:
					break
				if r.type != t or g.slots(r) < pass_n:
					continue
				# жилой отсек — только пара, и только если есть место для ребёнка
				if t == "living" and (pass_n > 2 or g.colonists.size() >= g.population_cap()):
					continue
				want[r.id] = want.get(r.id, 0) + 1
				left -= 1
		pass_n += 1
	# снимаем лишних
	for r in g.rooms:
		var ws: Array = g.workers_in(r)
		var extra: int = ws.size() - int(want.get(r.id, 0))
		for i in maxi(0, extra):
			ws[i].room = -1
	# расставляем свободных
	for c in adults:
		if c.room != -1:
			continue
		var best := {}
		var best_score := -1.0
		for r in g.rooms:
			var need: int = int(want.get(r.id, 0)) - g.workers_in(r).size()
			if need <= 0:
				continue
			var st: String = Defs.ROOMS[r.type].get("stat", "")
			var score: float = 1.0 + (g.stat(c, st) if st != "" else 0.0) + need * 0.1
			if score > best_score:
				best_score = score
				best = r
		if not best.is_empty():
			g.assign(c, best)

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

func _use(res: String) -> float:
	var pop: int = g.colonists.size()
	match res:
		"oxygen":
			return g.O2_PER_COLONIST * pop
		"food":
			return g.FOOD_PER_COLONIST * pop
		"energy":
			var e := 0.0
			for r in g.rooms:
				e += Defs.ROOMS[r.type].energy / g.PACE * r.level * r.size * (0.6 if g.has_research("fusion_core") else 1.0)
			return e
	return 0.0

const RES_ROOM := {"energy": "reactor", "oxygen": "oxygen", "food": "farm"}

func _try_build(type: String) -> bool:
	if not g.is_unlocked(type) or g.pearls < g.build_cost(type):
		return false
	var spots: Array = g.build_spots(type)
	if not spots.is_empty():
		return g.build(type, spots[0].x, spots[0].y)
	# мест нет — лифт на этаж ниже
	var el: Array = g.build_spots("elevator")
	el.sort_custom(func(a, b): return a.y > b.y)
	if not el.is_empty() and g.pearls >= g.build_cost("elevator"):
		g.build("elevator", el[0].x, el[0].y)
	elif el.is_empty() and g.research_current.is_empty():
		for rd in Defs.RESEARCH:
			if rd.id.begins_with("deep") and g.research_available(rd.id) and g.science >= rd.cost:
				g.start_research(rd.id)
	return false

func _can_up(r: Dictionary) -> bool:
	return r.level < Defs.MAX_LEVEL and Defs.ROOMS[r.type].get("buildable", false) and r.type != "elevator" and g.colony_level >= int(Defs.LEVEL_GATE.get(r.level + 1, 0))

func _build() -> void:
	# сюжет: копать вглубь, когда глава просит
	var st: Dictionary = g.story_current()
	if not st.is_empty() and st.goal[0] == "depth" and g.max_row() + 1 < int(st.goal[1]):
		var nr: String = g.next_depth_research()
		var needs_res: bool = nr != "" and g.max_row() + 1 >= Defs.DEPTH_ZONES[1].from and not g.has_research(nr)
		if needs_res:
			if g.research_current.is_empty() and g.science >= Defs.RESEARCH.filter(func(rd): return rd.id == nr)[0].cost:
				g.start_research(nr)
		else:
			var el: Array = g.build_spots("elevator")
			el.sort_custom(func(a, b): return a.y > b.y)
			if not el.is_empty() and g.pearls >= g.build_cost("elevator"):
				g.build("elevator", el[0].x, el[0].y)
				return
	# 1) нехватка воздуха / еды / энергии — сначала улучшить, потом строить новый
	for res in ["oxygen", "food", "energy"]:
		var unstaffed := false
		for r in g.rooms:
			if r.type == RES_ROOM[res] and g.workers_in(r).is_empty():
				unstaffed = true
		if unstaffed:
			continue
		if _rate(res) < _use(res) * 1.25:
			var cheapest := {}
			for r in g.rooms:
				if r.type == RES_ROOM[res] and _can_up(r) and (cheapest.is_empty() or g.upgrade_cost(r) < g.upgrade_cost(cheapest)):
					cheapest = r
			var bc: int = g.build_cost(RES_ROOM[res])
			if not cheapest.is_empty() and g.upgrade_cost(cheapest) <= bc:
				if g.pearls >= g.upgrade_cost(cheapest):
					g.upgrade(cheapest)
				return
			_try_build(RES_ROOM[res])
			return
	# сюжет просит улучшить отсек
	if not st.is_empty() and st.goal[0] == "upgrade":
		var ch := {}
		for r in g.rooms:
			if _can_up(r) and (ch.is_empty() or g.upgrade_cost(r) < g.upgrade_cost(ch)):
				ch = r
		if not ch.is_empty() and g.pearls >= g.upgrade_cost(ch):
			g.upgrade(ch)
		return
	# 2) жильё
	var pop: int = g.colonists.size()
	if pop >= g.population_cap() - 1 and pop < g.MAX_POP:
		_try_build("living")
		return
	# 3) новые отсеки по одному
	if g.is_unlocked("pearl") and g.count_of("pearl") < 1:
		_try_build("pearl")
		return
	for t in ["dock", "lab", "radio", "storage", "medbay", "kitchen", "gym", "school", "lounge", "workshop", "armory", "aquarium", "turbine", "observatory"]:
		if g.is_unlocked(t) and g.count_of(t) == 0:
			_try_build(t)
			return
	if g.is_unlocked("pearl") and g.count_of("pearl") < mini(3, 1 + g.colonists.size() / 8):
		_try_build("pearl")
		return
	# 4) иначе улучшаем самое дешёвое
	var cheapest2 := {}
	for r in g.rooms:
		if _can_up(r) and (cheapest2.is_empty() or g.upgrade_cost(r) < g.upgrade_cost(cheapest2)):
			cheapest2 = r
	if not cheapest2.is_empty() and g.pearls >= g.upgrade_cost(cheapest2):
		g.upgrade(cheapest2)

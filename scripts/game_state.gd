extends Node
## Состояние колонии: ресурсы, комнаты, колонисты, симуляция и сохранения.

signal changed                          # что-то изменилось — перерисовать UI
signal message(text: String)            # всплывающее сообщение
signal floating_text(room_id: int, text: String, color: Color)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const ARRIVAL_INTERVAL := 75.0
const MAX_OFFLINE := 8.0 * 3600.0
const MAX_OFFLINE_PREMIUM := 16.0 * 3600.0
const O2_PER_COLONIST := 0.07
const FOOD_PER_COLONIST := 0.05

var resources := {}
var pearls := 0
var rooms: Array = []
var colonists: Array = []
var next_id := 1
var arrival_timer := 0.0
var autosave_timer := 0.0
var rng := RandomNumberGenerator.new()

# премиум-экономика
signal rewards_granted(title: String, lines: Array)
signal event(name: String)
signal banner(icon: String, title: String, text: String)   # яркое уведомление с картинкой
const FREE_CRATE_COOLDOWN := 4.0 * 3600.0
const BOOST_DURATION := 30.0 * 60.0
var crystals := 0
var crates := {"common": 0, "silver": 0, "gold": 0}
var premium := false
var no_ads := false
var pet := ""
const PET_BONUS := 0.1
var owned_products: Array = []
var boost_until := 0.0
var free_crate_at := 0.0
var daily_day := -1
var daily_streak := 0

# экспедиции, задания, сезон
const ON_EXPEDITION := -2
var expeditions: Array = []
var quests: Array = []
var quest_day := -1
var season_start := -1
var season_xp := 0
var season_pass := false
var season_claimed_free: Array = []
var season_claimed_premium: Array = []

func _ready() -> void:
	rng.randomize()
	if not load_game():
		new_game()
	refresh_daily_systems()

func _process(delta: float) -> void:
	simulate(delta, false)
	autosave_timer += delta
	if autosave_timer > 15.0:
		autosave_timer = 0.0
		refresh_daily_systems()
		save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()

# ---------------------------------------------------------------- новая игра

func new_game() -> void:
	resources = {"energy": 60.0, "oxygen": 60.0, "food": 60.0}
	pearls = 300
	crystals = 25
	crates = {"common": 1, "silver": 0, "gold": 0}
	premium = false
	no_ads = false
	pet = ""
	owned_products = []
	boost_until = 0.0
	free_crate_at = 0.0
	daily_day = -1
	daily_streak = 0
	expeditions = []
	quests = []
	quest_day = -1
	season_start = -1
	season_xp = 0
	season_pass = false
	season_claimed_free = []
	season_claimed_premium = []
	science = 0
	research_done = []
	research_current = {}
	items = []
	stats = {}
	achievements_claimed = {}
	story_index = 0
	story_count = 0
	weekly_week = -1
	weekly_progress = 0
	weekly_claimed = []
	trader = {}
	tutorial_done = false
	difficulty = "normal"
	mode_chosen = false
	rooms = []
	colonists = []
	next_id = 1
	arrival_timer = 0.0
	_add_room("reactor", 1, 0).progress = 0.93
	_add_room("airlock", 3, 0)
	_add_room("elevator", 5, 0)
	_add_room("oxygen", 6, 0)
	_add_room("elevator", 5, 1)
	_add_room("farm", 6, 1)
	for i in 4:
		colonists.append(_make_colonist())
	# распределим стартовых колонистов по комнатам
	auto_assign(colonists[0], find_room_of_type("reactor"))
	auto_assign(colonists[1], find_room_of_type("oxygen"))
	auto_assign(colonists[2], find_room_of_type("farm"))
	changed.emit()

func _add_room(type: String, col: int, row: int) -> Dictionary:
	var r := {
		"id": next_id, "type": type, "col": col, "row": row, "level": 1,
		"progress": 0.0, "ready": false, "incident": 0.0, "heat": 0.0, "hazard": "", "spread": 0.0, "size": 1,
	}
	next_id += 1
	rooms.append(r)
	return r

func _make_colonist() -> Dictionary:
	var c := {
		"id": next_id,
		"name": "%s %s" % [Defs.FIRST_NAMES.pick_random(), Defs.LAST_NAMES.pick_random()],
		"str": rng.randi_range(1, 4), "tech": rng.randi_range(1, 4), "bio": rng.randi_range(1, 4),
		"level": 1, "xp": 0.0, "health": 100.0, "room": -1, "help": -1, "suit_item": -1, "tool_item": -1, "armor_item": -1,
		"suit": rng.randi_range(0, 5),
	}
	next_id += 1
	return c

# ---------------------------------------------------------------- запросы

func get_room(id: int) -> Dictionary:
	for r in rooms:
		if r.id == id:
			return r
	return {}

func get_colonist(id: int) -> Dictionary:
	for c in colonists:
		if c.id == id:
			return c
	return {}

func find_room_of_type(type: String) -> Dictionary:
	for r in rooms:
		if r.type == type:
			return r
	return {}

func room_at(col: int, row: int) -> Dictionary:
	for r in rooms:
		if r.row == row and col >= r.col and col < r.col + room_w(r):
			return r
	return {}

## Ширина отсека в клетках с учётом объединения (1×, 2×, 3×).
func room_w(r: Dictionary) -> int:
	return Defs.room_width(r.type) * int(r.get("size", 1))

func slots(r: Dictionary) -> int:
	var base: int = Defs.ROOMS[r.type].get("slots", 0)
	if base == 0:
		return 0
	return base * int(r.get("size", 1)) + r.level - 1

func workers_in(room: Dictionary) -> Array:
	var out := []
	for c in colonists:
		if c.room == room.id:
			out.append(c)
	return out

func population_cap() -> int:
	var cap := 6
	for r in rooms:
		if r.type == "living":
			cap += Defs.ROOMS.living.capacity * r.level * r.size
	return cap

func storage_cap() -> float:
	var cap := 120.0
	for r in rooms:
		if r.type == "storage":
			cap += Defs.ROOMS.storage.storage * r.level * r.size
	return cap * (1.5 if has_research("storage_compression") else 1.0)

func count_of(type: String) -> int:
	var n := 0
	for r in rooms:
		if r.type == type:
			n += 1
	return n

func build_cost(type: String) -> int:
	var base: int = Defs.ROOMS[type].cost
	return int(base * (1.0 + 0.35 * count_of(type)))

func is_unlocked(type: String) -> bool:
	return colonists.size() >= Defs.ROOMS[type].get("unlock_pop", 0)

func max_row() -> int:
	var m := 0
	for r in rooms:
		m = max(m, r.row)
	return m

func can_build_at(type: String, col: int, row: int) -> bool:
	var w := Defs.room_width(type)
	if col < 0 or col + w > Defs.GRID_COLS or row < 0 or row >= Defs.MAX_DEPTH:
		return false
	if not zone_unlocked_row(row):
		return false
	for i in w:
		if not room_at(col + i, row).is_empty():
			return false
	# соединение: сосед слева/справа на том же уровне
	if not room_at(col - 1, row).is_empty() or not room_at(col + w, row).is_empty():
		return true
	# лифт соединяется с лифтом сверху/снизу
	if type == "elevator":
		for dr in [-1, 1]:
			var n := room_at(col, row + dr)
			if not n.is_empty() and n.type == "elevator":
				return true
	return false

## Все клетки, куда можно поставить отсек, ближние к верху — первыми.
func build_spots(type: String) -> Array:
	var out := []
	for row in Defs.MAX_DEPTH:
		for col in Defs.GRID_COLS:
			if can_build_at(type, col, row):
				out.append(Vector2i(col, row))
	return out

## Эффективность комнаты: сумма нужной характеристики рабочих с учётом здоровья.
func room_power(room: Dictionary) -> float:
	var def: Dictionary = Defs.ROOMS[room.type]
	if not def.has("stat"):
		return 0.0
	var total := 0.0
	for c in workers_in(room):
		total += stat(c, def.stat) * (0.4 + 0.6 * c.health / 100.0)
	return total

func cycle_time(room: Dictionary) -> float:
	var def: Dictionary = Defs.ROOMS[room.type]
	var power := room_power(room)
	if power <= 0.0:
		return INF
	return def.cycle / (power / 5.0)

func production_amount(room: Dictionary) -> float:
	var def: Dictionary = Defs.ROOMS[room.type]
	var res: String = def.get("produces", "")
	var m: float = 1.0 + depth_zone(room.row).bonus
	match res:
		"energy": m *= 1.2 if has_research("efficient_reactors") else 1.0
		"food":
			m *= 1.2 if has_research("hydroponics") else 1.0
			m *= 1.5 if weekly_mod() == "harvest" else 1.0
		"oxygen": m *= 1.2 if has_research("electrolysis") else 1.0
		"pearls":
			m *= 1.4 if has_research("pearl_cultivation") else 1.0
			m *= 1.5 if weekly_mod() == "pearl_week" else 1.0
	if res == "pearls":
		m *= mode().reward
	return def.amount * (1.0 + 0.6 * (room.level - 1)) * room.size * m

func rush_chance(room: Dictionary) -> float:
	return clampf(0.8 - room.heat * 0.15, 0.2, 0.8)

# ---------------------------------------------------------------- симуляция

func simulate(delta: float, offline: bool) -> void:
	var cap := storage_cap()
	# расход
	var energy_use := 0.0
	for r in rooms:
		energy_use += Defs.ROOMS[r.type].energy * r.level * r.size * (0.6 if has_research("fusion_core") else 1.0)
	resources.energy = maxf(0.0, resources.energy - energy_use * delta)
	var pop := colonists.size()
	var consume: float = mode().consume
	resources.oxygen = maxf(0.0, resources.oxygen - O2_PER_COLONIST * pop * delta * consume)
	resources.food = maxf(0.0, resources.food - FOOD_PER_COLONIST * pop * delta * consume)
	var powered: bool = resources.energy > 0.0
	var starving: bool = resources.oxygen <= 0.0 or resources.food <= 0.0

	# комнаты
	for r in rooms:
		var def: Dictionary = Defs.ROOMS[r.type]
		r.heat = maxf(0.0, r.heat - delta / 60.0)
		if r.incident > 0.0:
			_tick_hazard(r, delta, offline)
			continue
		if def.has("produces") and not r.ready:
			var t := cycle_time(r)
			if t < INF:
				var speed := 1.0 if (powered or def.produces == "energy") else 0.25
				r.progress += delta * speed / t
				if r.progress >= 1.0:
					r.progress = 1.0
					r.ready = true
					if has_research("auto_collectors"):
						collect(r, offline)

	# колонисты
	var heal_rate := 0.3
	for r in rooms:
		if Defs.ROOMS[r.type].get("heal", false) and r.incident <= 0.0:
			heal_rate += room_power(r) * 0.1 * r.level
	if has_research("medical_ai"):
		heal_rate *= 3.0
	var xp_mult := 1.5 if has_research("training_programs") else 1.0
	for c in colonists:
		if starving and not offline and mode().hunger:
			c.health = maxf(health_floor(), c.health - 1.5 * delta * mode().damage)
		elif not starving:
			c.health = minf(100.0, c.health + heal_rate * delta)
		if c.room >= 0:
			c.xp += delta * xp_mult
			if c.xp >= _xp_needed(c):
				_level_up(c)

	if not offline:
		_check_deaths()

	# случайные инциденты (только в игре, не офлайн)
	if not offline and colonists.size() >= 5:
		incident_timer -= delta
		if incident_timer <= 0.0:
			var mult := (1.0 / 0.7 if has_research("reinforced_hull") else 1.0) * (0.6 if weekly_mod() == "tide" else 1.0)
			incident_timer = rng.randf_range(150.0, 300.0) * mult * mode().incidents
			_spawn_random_incident()
	if not offline and colonists.size() >= 6:
		trader_timer -= delta * (2.0 if has_research("trader_beacon") else 1.0)
		if trader_timer <= 0.0:
			trader_timer = rng.randf_range(420.0, 720.0)
			_spawn_trader()
	if not trader.is_empty() and now() > float(trader.until):
		trader = {}
		changed.emit()
	if not research_current.is_empty() and now() >= float(research_current.end):
		_finish_research(offline)

	# новые колонисты
	if colonists.size() < population_cap():
		arrival_timer += delta
		if arrival_timer >= ARRIVAL_INTERVAL:
			arrival_timer = 0.0
			var c := _make_colonist()
			if has_research("legendary_signal") and rng.randf() < 0.1:
				for k in ["str", "tech", "bio"]:
					c[k] = rng.randi_range(4, 7)
				c["rarity"] = "rare"
			colonists.append(c)
			if not offline:
				banner.emit("suit_%d" % c.suit, tr("New colonist arrived: %s") % "", c.name)
				event.emit("arrive")
			changed.emit()
	for k in resources:
		resources[k] = minf(resources[k], cap)

func _xp_needed(c: Dictionary) -> float:
	return 90.0 * c.level

func _level_up(c: Dictionary) -> void:
	c.xp = 0.0
	c.level += 1
	track("level_up")
	var room := get_room(c.room)
	var stat: String = Defs.ROOMS[room.type].get("stat", "") if not room.is_empty() else ""
	if stat == "":
		stat = ["str", "tech", "bio"].pick_random()
	c[stat] = mini(10, c[stat] + 1)
	pearls += 15
	banner.emit("suit_%d" % c.suit, tr("Level %d") % c.level, tr("%s reached level %d! %s +1") % [c.name, c.level, tr(Defs.STATS[stat])])
	changed.emit()

func seconds_until_arrival() -> float:
	if colonists.size() >= population_cap():
		return -1.0
	return ARRIVAL_INTERVAL - arrival_timer

# ---------------------------------------------------------------- действия

func build(type: String, col: int, row: int) -> bool:
	var cost := build_cost(type)
	if pearls < cost:
		message.emit(tr("Not enough pearls"))
		event.emit("error")
		return false
	if not can_build_at(type, col, row):
		return false
	pearls -= cost
	var r := _add_room(type, col, row)
	r = _try_merge(r)
	track("build")
	track("build_" + type)
	floating_text.emit(r.id, "[pearls]-%d" % cost, Defs.RESOURCES.pearls.color)
	changed.emit()
	return true

## Отсек рядом с таким же (тот же тип и уровень) сливается в широкую комнату до 3×.
func _try_merge(r: Dictionary) -> Dictionary:
	if r.type in ["elevator", "airlock", "dock"]:
		return r
	var w := Defs.room_width(r.type)
	for n in [room_at(r.col - 1, r.row), room_at(r.col + w, r.row)]:
		if n.is_empty() or n.type != r.type or n.level != r.level or n.size >= 3 or n.incident > 0.0:
			continue
		rooms.erase(r)
		n.size += 1
		n.col = mini(n.col, r.col)
		message.emit(tr("Rooms merged: %s %d×") % [tr(Defs.ROOMS[n.type].name), n.size])
		_fix_orphans()
		return n
	return r

func upgrade_cost(room: Dictionary) -> int:
	return Defs.upgrade_cost(room.type, room.level) * int(room.size)

func upgrade(room: Dictionary) -> void:
	if room.level >= Defs.MAX_LEVEL:
		return
	var cost := upgrade_cost(room)
	if pearls < cost:
		message.emit(tr("Not enough pearls"))
		return
	pearls -= cost
	room.level += 1
	track("upgrade")
	message.emit(tr("%s upgraded to level %d") % [Defs.ROOMS[room.type].name, room.level])
	changed.emit()

func collect(room: Dictionary, silent := false) -> void:
	if not room.ready:
		return
	var def: Dictionary = Defs.ROOMS[room.type]
	var amount := production_amount(room) * (2.0 if boost_active() else 1.0) * (1.0 + (PET_BONUS if pet != "" else 0.0))
	var res: String = def.produces
	if res == "pearls":
		pearls += int(amount)
	elif res == "science":
		science += int(amount)
	else:
		resources[res] = minf(storage_cap(), resources[res] + amount)
	var bonus: int = 1 + room.level
	pearls += bonus
	room.ready = false
	room.progress = 0.0
	var zone := depth_zone(room.row)
	if zone.crystal_chance > 0.0 and rng.randf() < zone.crystal_chance:
		var cr := rng.randi_range(1, 3)
		crystals += cr
		if not silent:
			floating_text.emit(room.id, "[crystals]+%d" % cr, Defs.RESOURCES.crystals.color)
	if silent:
		stats["collect"] = stats.get("collect", 0) + 1
		return
	floating_text.emit(room.id, "[%s]+%d" % [res, int(amount)], Defs.RESOURCES[res].color)
	track("collect_" + res, int(amount))
	track("collect")
	changed.emit()

func collect_all() -> int:
	var n := 0
	for r in rooms:
		if r.ready:
			collect(r)
			n += 1
	return n

## Ускорение: мгновенно завершить цикл, но есть шанс аварии.
func rush(room: Dictionary) -> void:
	if room.ready or room.incident > 0.0 or not Defs.ROOMS[room.type].has("produces"):
		return
	if workers_in(room).is_empty():
		message.emit(tr("Nobody is working in this room"))
		return
	var chance := rush_chance(room)
	room.heat += 1.0
	track("rush")
	if rng.randf() < chance:
		room.progress = 1.0
		room.ready = true
		pearls += 10
		floating_text.emit(room.id, "[pearls]+10", Color(0.6, 1.0, 0.7))
	else:
		room.progress = 0.0
		var res: String = Defs.ROOMS[room.type].produces
		if resources.has(res):
			resources[res] = maxf(0.0, resources[res] - 15.0)
		floating_text.emit(room.id, tr("HULL BREACH!"), Color(1.0, 0.3, 0.3))
		start_hazard(room, "flood")
	changed.emit()

func assign(colonist: Dictionary, room: Dictionary) -> bool:
	if colonist.room == ON_EXPEDITION:
		message.emit(tr("%s is away on an expedition") % colonist.name)
		return false
	if room.is_empty() or room.type == "airlock":
		colonist.room = -1
		changed.emit()
		return true
	var room_slots := slots(room)
	if room_slots == 0:
		message.emit(tr("Nobody can work here"))
		return false
	if colonist.room == room.id:
		return true
	if workers_in(room).size() >= room_slots:
		message.emit(tr("All slots are taken"))
		return false
	colonist.room = room.id
	colonist.help = -1
	colonist.xp = 0.0
	track("assign")
	changed.emit()
	return true

func auto_assign(colonist: Dictionary, room: Dictionary) -> void:
	if not room.is_empty():
		assign(colonist, room)

# ---------------------------------------------------------------- премиум-экономика

static func now() -> float:
	return Time.get_unix_time_from_system()

## Premium включает отключение рекламы.
func ads_removed() -> bool:
	return premium or no_ads

func boost_active() -> bool:
	return now() < boost_until

func boost_left() -> float:
	return maxf(0.0, boost_until - now())

func start_boost() -> void:
	boost_until = maxf(boost_until, now()) + BOOST_DURATION
	message.emit(tr("Double collection active for 30 minutes!"))
	changed.emit()

func spend_crystals(n: int) -> bool:
	if crystals < n:
		message.emit(tr("Not enough crystals"))
		event.emit("error")
		return false
	crystals -= n
	changed.emit()
	return true

## Цена безопасного ускорения: 1 кристалл за каждые 20 секунд оставшегося цикла.
func safe_rush_cost(room: Dictionary) -> int:
	var t := cycle_time(room)
	if t == INF:
		return -1
	return clampi(ceili((1.0 - room.progress) * t / 20.0), 1, 60)

func rush_safe(room: Dictionary) -> void:
	if not crystal_rush_allowed():
		return
	if room.ready or room.incident > 0.0 or not Defs.ROOMS[room.type].has("produces"):
		return
	var cost := safe_rush_cost(room)
	if cost < 0:
		message.emit(tr("Nobody is working in this room"))
		return
	if not spend_crystals(cost):
		return
	room.progress = 1.0
	room.ready = true
	floating_text.emit(room.id, tr("Done!"), Color(0.6, 0.9, 1.0))
	changed.emit()

## Выдать награду. reward: {pearls, crystals, crates: {type: n}, colonist: rarity, premium}.
func grant(reward: Dictionary, title: String) -> void:
	var lines := _pending_lines.duplicate()
	_pending_lines = []
	if reward.has("pearls"):
		pearls += int(reward.pearls)
		lines.append("[pearls]" + tr("+%d pearls") % int(reward.pearls))
	if reward.has("crystals"):
		crystals += int(reward.crystals)
		lines.append("[crystals]" + tr("+%d crystals") % int(reward.crystals))
	for k in reward.get("crates", {}):
		crates[k] += int(reward.crates[k])
		lines.append("[crate_%s]+%d %s" % [k, int(reward.crates[k]), tr(Defs.CRATES[k].name)])
	if reward.has("colonist"):
		lines.append("[colonist]" + _grant_colonist(reward.colonist))
	if reward.has("item"):
		var it := add_item(reward.item)
		lines.append("[item_%s]" % it.base + tr("New gear: %s") % item_name(it))
	if reward.has("pet"):
		pet = reward.pet
		lines.append("[pet]" + tr("Nemo the clownfish joined you! +10% to all collections"))
	if reward.get("no_ads", false):
		no_ads = true
		lines.append(tr("Ads removed. Rewards are now instant!"))
	if reward.get("season_pass", false):
		season_pass = true
		lines.append(tr("Season Pass unlocked!"))
	if reward.get("premium", false):
		premium = true
		lines.append(tr("Premium unlocked!"))
		lines.append("[captain]" + _grant_captain())
	changed.emit()
	rewards_granted.emit(title, lines)

func _grant_colonist(rarity: String) -> String:
	if colonists.size() >= population_cap():
		pearls += 300
		return tr("No room for a new colonist: +300 pearls instead")
	var c := _make_colonist()
	var lo := 4 if rarity == "rare" else 7
	var hi := 7 if rarity == "rare" else 10
	for k in ["str", "tech", "bio"]:
		c[k] = rng.randi_range(lo, hi)
	c["rarity"] = rarity
	colonists.append(c)
	return tr("%s colonist: %s") % [tr(rarity.capitalize()), c.name]

## Капитан — особый колонист за Premium (приходит сверх лимита жилья).
func _grant_captain() -> String:
	var c := _make_colonist()
	c.name = "Captain " + c.name.split(" ")[1]
	c.suit = Art.CAPTAIN_SUIT
	c["rarity"] = "legendary"
	for k in ["str", "tech", "bio"]:
		c[k] = rng.randi_range(6, 8)
	colonists.append(c)
	return tr("%s joined your colony!") % c.name

func crate_odds(type: String) -> Array:
	var table: Array = Defs.CRATES[type].table
	var total := 0.0
	for e in table:
		total += e[0]
	var out := []
	for e in table:
		out.append([e[1], e[0] / total])
	return out

func open_crate(type: String) -> void:
	if crates.get(type, 0) <= 0:
		return
	crates[type] -= 1
	track("crate")
	var def: Dictionary = Defs.CRATES[type]
	var reward := {"pearls": 0, "crystals": 0}
	var extra := []
	var kinds := []
	if def.has("guaranteed"):
		kinds.append(def.guaranteed)
	for i in def.rolls:
		kinds.append(_roll(def.table))
	for k in kinds:
		var e := _entry(def.table, k)
		match k:
			"pearls":
				reward.pearls += rng.randi_range(e[2], e[3])
			"crystals":
				reward.crystals += rng.randi_range(e[2], e[3])
			"resources":
				var amt := rng.randi_range(e[2], e[3])
				for r in resources:
					resources[r] = minf(storage_cap(), resources[r] + amt)
				extra.append("[food]" + tr("+%d energy, oxygen and food") % amt)
			"colonist_rare":
				extra.append("[colonist]" + _grant_colonist("rare"))
			"colonist_legendary":
				extra.append("[colonist]" + _grant_colonist("legendary"))
	if reward.pearls == 0:
		reward.erase("pearls")
	if reward.crystals == 0:
		reward.erase("crystals")
	var lines := []
	if reward.has("pearls"):
		pearls += reward.pearls
		lines.append("[pearls]" + tr("+%d pearls") % reward.pearls)
	if reward.has("crystals"):
		crystals += reward.crystals
		lines.append("[crystals]" + tr("+%d crystals") % reward.crystals)
	if type != "common" or rng.randf() < 0.3:
		var rar := "common"
		if type == "gold":
			rar = "legendary" if rng.randf() < 0.25 else "rare"
		elif type == "silver":
			rar = "rare" if rng.randf() < 0.5 else "common"
		var gi := add_item(rar)
		lines.append("[item_%s]" % gi.base + tr("New gear: %s") % item_name(gi))
	lines.append_array(extra)
	changed.emit()
	rewards_granted.emit(tr(def.name), lines)

func _roll(table: Array) -> String:
	var total := 0.0
	for e in table:
		total += e[0]
	var x := rng.randf() * total
	for e in table:
		x -= e[0]
		if x <= 0.0:
			return e[1]
	return table[0][1]

func _entry(table: Array, kind: String) -> Array:
	for e in table:
		if e[1] == kind:
			return e
	return [0, kind, 1, 1]

func free_crate_ready() -> bool:
	return now() >= free_crate_at

func free_crate_left() -> float:
	return maxf(0.0, free_crate_at - now())

func claim_free_crate() -> void:
	if not free_crate_ready():
		return
	free_crate_at = now() + FREE_CRATE_COOLDOWN * (0.5 if premium else 1.0)
	crates.common += 1
	open_crate("common")

static func today() -> int:
	return int(now() / 86400.0)

func daily_available() -> bool:
	return daily_day < today()

## Номер дня (0..6), который будет выдан при следующем получении.
func daily_next_index() -> int:
	var streak := daily_streak + 1 if daily_day == today() - 1 else 1
	if daily_day == today():
		streak = daily_streak
	return (streak - 1) % Defs.DAILY.size()

func claim_daily() -> void:
	if not daily_available():
		return
	daily_streak = daily_streak + 1 if daily_day == today() - 1 else 1
	daily_day = today()
	var idx := (daily_streak - 1) % Defs.DAILY.size()
	grant(Defs.DAILY[idx], tr("Daily reward, day %d") % (idx + 1))

# ---------------------------------------------------------------- экспедиции

func expedition_at(dock_id: int) -> Dictionary:
	for e in expeditions:
		if e.dock == dock_id:
			return e
	return {}

func expedition_done(e: Dictionary) -> bool:
	return now() >= float(e.end)

func expedition_progress(e: Dictionary) -> float:
	return clampf((now() - float(e.start)) / maxf(1.0, float(e.end) - float(e.start)), 0.0, 1.0)

func available_crew() -> Array:
	return colonists.filter(func(c): return c.room != ON_EXPEDITION)

func crew_power(ids: Array) -> float:
	var p := 0.0
	for id in ids:
		var c := get_colonist(id)
		if not c.is_empty():
			p += (stat(c, "str") + stat(c, "tech") + stat(c, "bio")) * (0.5 + 0.5 * c.health / 100.0)
	return p

func expedition_chance(zone_idx: int, ids: Array) -> float:
	var zone: Dictionary = Defs.ZONES[zone_idx]
	return clampf(crew_power(ids) / zone.power, 0.3, 1.5)

func zone_unlocked(zone_idx: int) -> bool:
	return colonists.size() >= Defs.ZONES[zone_idx].unlock_pop

func launch_expedition(dock_id: int, zone_idx: int, ids: Array) -> bool:
	if not expedition_at(dock_id).is_empty() or ids.is_empty() or ids.size() > 3:
		return false
	var zone: Dictionary = Defs.ZONES[zone_idx]
	var f := expedition_chance(zone_idx, ids)
	var loot_mult: float = (1.25 if has_research("sonar_mapping") else 1.0) * (1.5 if weekly_mod() == "explorers" else 1.0) * mode().reward
	var names := []
	for id in ids:
		names.append(get_colonist(id).name.split(" ")[0])
	# исход определяется сразу — так он одинаков и онлайн, и офлайн
	var loot := {}
	var L: Dictionary = zone.loot
	if L.has("pearls"):
		loot.pearls = int(rng.randi_range(L.pearls[0], L.pearls[1]) * f * loot_mult)
	if L.has("crystals"):
		loot.crystals = int(rng.randi_range(L.crystals[0], L.crystals[1]) * f * loot_mult)
	if L.has("resources"):
		loot.resources = int(rng.randi_range(L.resources[0], L.resources[1]) * f * loot_mult)
	if rng.randf() < 0.25 + 0.1 * zone_idx:
		var roll := rng.randf()
		var rarity := "common"
		if roll < 0.04 * zone_idx:
			rarity = "legendary"
		elif roll < 0.12 + 0.12 * zone_idx:
			rarity = "rare"
		loot.item = rarity
	if L.has("crate") and rng.randf() < 0.3 + 0.4 * f:
		loot.crates = {L.crate: 1}
	if L.has("survivor") and rng.randf() < L.survivor * f:
		loot.colonist = "rare"
	var events := []
	var damage := {}
	var n := clampi(3 + zone.minutes / 20, 3, 10)
	for i in n:
		var who: String = names.pick_random()
		var roll := rng.randf()
		var text := ""
		if roll < zone.danger * (1.3 - 0.5 * f):
			var victim: int = ids.pick_random()
			damage[str(victim)] = damage.get(str(victim), 0) + rng.randi_range(8, 25)
			who = get_colonist(victim).name.split(" ")[0]
			text = Defs.LOG_DANGER.pick_random()
		elif roll < 0.45:
			text = Defs.LOG_FIND.pick_random()
		elif roll < 0.75:
			text = Defs.LOG_ZONE[zone.id].pick_random()
		else:
			text = Defs.LOG_CALM.pick_random()
		events.append({"at": (i + 1.0) / (n + 1.0), "text": tr(text).replace("{n}", who)})
	for id in ids:
		get_colonist(id).room = ON_EXPEDITION
		get_colonist(id).help = -1
	var start := now()
	expeditions.append({
		"id": next_id, "dock": dock_id, "zone": zone_idx, "crew": ids.duplicate(),
		"start": start, "end": start + zone.minutes * 60.0 * (0.7 if has_research("bathyscaphe_engines") else 1.0),
		"events": events, "loot": loot, "damage": damage,
	})
	next_id += 1
	track("expedition")
	track("expedition_" + zone.id)
	message.emit(tr("The bathyscaphe departs for %s!") % tr(zone.name))
	changed.emit()
	save_game()
	return true

func visible_log(e: Dictionary) -> Array:
	var p := expedition_progress(e)
	return e.events.filter(func(ev): return ev.at <= p).map(func(ev): return ev.text)

func finish_cost(e: Dictionary) -> int:
	return maxi(1, ceili((float(e.end) - now()) / 120.0))

func finish_expedition_now(e: Dictionary) -> void:
	if not crystal_rush_allowed():
		return
	if expedition_done(e) or not spend_crystals(finish_cost(e)):
		return
	e.end = now()
	changed.emit()

func cut_expedition(e: Dictionary, seconds: float) -> void:
	e.end = maxf(now(), float(e.end) - seconds)
	changed.emit()

func claim_expedition(e: Dictionary) -> void:
	if not expedition_done(e):
		return
	expeditions.erase(e)
	var zone: Dictionary = Defs.ZONES[e.zone]
	var lines := []
	var loot: Dictionary = e.loot
	if loot.get("resources", 0) > 0:
		for r in resources:
			resources[r] = minf(storage_cap(), resources[r] + loot.resources)
		lines.append("[food]" + tr("+%d energy, oxygen and food") % loot.resources)
	for id in e.crew:
		var c := get_colonist(id)
		if c.is_empty():
			continue
		c.room = -1
		c.health = maxf(health_floor(), c.health - e.damage.get(str(id), 0) * (1.0 - protection(c)) * mode().damage)
		c.xp += zone.minutes * 4.0
		while c.xp >= _xp_needed(c):
			c.xp -= _xp_needed(c)
			var keep: float = c.xp
			_level_up(c)
			c.xp = keep
	stats["expedition_done"] = stats.get("expedition_done", 0) + 1
	var reward := loot.duplicate()
	reward.erase("resources")
	if reward.get("pearls", 0) <= 0: reward.erase("pearls")
	if reward.get("crystals", 0) <= 0: reward.erase("crystals")
	var title := tr("%s: expedition complete") % tr(zone.name)
	if reward.is_empty():
		changed.emit()
		rewards_granted.emit(title, lines if not lines.is_empty() else [tr("The crew came back empty-handed.")])
	else:
		# grant сам покажет окно; строки про ресурсы добавим в начало
		_pending_lines = lines
		grant(reward, title)
	save_game()

var _pending_lines: Array = []

# ---------------------------------------------------------------- инциденты

const HAZARDS := {
	"fire": {"label": "FIRE", "msg": "Fire in %s!", "damage": 1.6},
	"flood": {"label": "FLOOD", "msg": "Flooding in %s!", "damage": 1.2},
	"creature": {"label": "ATTACK", "msg": "Creature attack in %s!", "damage": 2.4},
}
var incident_timer := 200.0

# прогрессия: наука, исследования, снаряжение, сюжет, достижения, события, торговцы
var science := 0
var research_done: Array = []
var research_current := {}
var items: Array = []
var stats := {}
var achievements_claimed := {}
var story_index := 0
var story_count := 0
var weekly_week := -1
var weekly_progress := 0
var weekly_claimed: Array = []
var trader := {}
var trader_timer := 300.0
var tutorial_done := false
var difficulty := "normal"
var mode_chosen := true

func can_have_hazard(room: Dictionary) -> bool:
	return not room.is_empty() and room.type != "elevator" and room.type != "airlock"

func start_hazard(room: Dictionary, kind: String, hp := 100.0) -> void:
	if not can_have_hazard(room) or room.incident > 0.0:
		return
	room.hazard = kind
	room.incident = hp
	room.spread = 0.0
	message.emit(tr(HAZARDS[kind].msg) % tr(Defs.ROOMS[room.type].name))
	event.emit("incident")
	changed.emit()

func _spawn_random_incident() -> void:
	var candidates := rooms.filter(func(r): return can_have_hazard(r) and r.incident <= 0.0)
	if candidates.is_empty():
		return
	# глубокие зоны опаснее: выше шанс, что беда случится там
	var weights := candidates.map(func(r): return depth_zone(r.row).danger)
	var total := 0.0
	for wv in weights:
		total += wv
	var pick := rng.randf() * total
	var room: Dictionary = candidates[0]
	for i in candidates.size():
		pick -= weights[i]
		if pick <= 0.0:
			room = candidates[i]
			break
	var kinds := ["fire", "flood"]
	if room.row >= 5 or weekly_mod() == "tide":
		kinds.append("creature")
	if room.row >= 1:
		kinds.append("flood")
	if colonists.size() >= 8 and (room.row >= 2 or room.type == "dock"):
		kinds.append("creature")
	start_hazard(room, kinds.pick_random())

## Кто борется с бедой: рабочие отсека и прибежавшие на помощь.
func responders(room: Dictionary) -> Array:
	return colonists.filter(func(c): return (c.room == room.id or c.help == room.id) and c.room != ON_EXPEDITION)

func hazard_power(room: Dictionary) -> float:
	var p := 0.0
	for c in responders(room):
		p += (stat(c, "str") + stat(c, "tech") + stat(c, "bio")) / 3.0 * (0.4 + 0.6 * c.health / 100.0)
	return p

func send_help(colonist: Dictionary, room: Dictionary) -> void:
	if colonist.room == ON_EXPEDITION or room.incident <= 0.0:
		return
	colonist.help = room.id
	changed.emit()

func _tick_hazard(r: Dictionary, delta: float, offline: bool) -> void:
	if offline:
		r.incident = maxf(0.0, r.incident - 5.0 * delta)
	else:
		var crew := responders(r)
		if crew.is_empty():
			r.incident = minf(100.0, r.incident + 1.5 * delta)
		else:
			r.incident -= hazard_power(r) * 1.6 * delta * (2.0 if has_research("fire_suppression") else 1.0) / depth_zone(r.row).danger
			var dmg: float = HAZARDS[r.hazard].damage * delta
			for c in crew:
				c.health = maxf(health_floor(), c.health - dmg * (1.0 - protection(c)) * mode().damage)
		r.spread += delta
		if r.spread > 20.0 and r.incident > 60.0:
			r.spread = 0.0
			_spread_hazard(r)
	if r.incident <= 0.0:
		_resolve_hazard(r, offline)

func _spread_hazard(r: Dictionary) -> void:
	var w := Defs.room_width(r.type)
	var near := []
	for n in [room_at(r.col - 1, r.row), room_at(r.col + w, r.row)]:
		if can_have_hazard(n) and n.incident <= 0.0:
			near.append(n)
	if near.is_empty():
		return
	var target: Dictionary = near.pick_random()
	start_hazard(target, r.hazard, 50.0)
	message.emit(tr("Incident spread to %s!") % tr(Defs.ROOMS[target.type].name))

func _resolve_hazard(r: Dictionary, offline: bool) -> void:
	var crew := responders(r)
	r.incident = 0.0
	r.hazard = ""
	for c in colonists:
		if c.help == r.id:
			c.help = -1
	if offline:
		return
	var reward: int = int((10 + 10 * r.level) * (2 if weekly_mod() == "tide" else 1) * mode().reward)
	pearls += reward
	for c in crew:
		c.xp += 20.0
	floating_text.emit(r.id, "[pearls]+%d" % reward, Color(0.6, 1.0, 0.7))
	message.emit(tr("%s is under control!") % tr(Defs.ROOMS[r.type].name))
	track("incident_resolved")
	changed.emit()

# ---------------------------------------------------------------- глубина

func depth_zone(row: int) -> Dictionary:
	var z: Dictionary = Defs.DEPTH_ZONES[0]
	for d in Defs.DEPTH_ZONES:
		if row >= d.from:
			z = d
	return z

func zone_unlocked_row(row: int) -> bool:
	var need: String = depth_zone(row).research
	return need == "" or has_research(need)

# ---------------------------------------------------------------- исследования

func has_research(id: String) -> bool:
	return id in research_done

func research_def(id: String) -> Dictionary:
	for r in Defs.RESEARCH:
		if r.id == id:
			return r
	return {}

func research_available(id: String) -> bool:
	if has_research(id):
		return false
	for req in research_def(id).req:
		if not has_research(req):
			return false
	return true

func start_research(id: String) -> bool:
	var d := research_def(id)
	if not research_current.is_empty() or not research_available(id):
		return false
	if science < d.cost:
		message.emit(tr("Not enough science"))
		event.emit("error")
		return false
	science -= d.cost
	research_current = {"id": id, "start": now(), "end": now() + d.minutes * 60.0}
	changed.emit()
	return true

func research_left() -> float:
	return maxf(0.0, float(research_current.get("end", 0.0)) - now())

func research_finish_cost() -> int:
	return maxi(1, ceili(research_left() / 60.0))

func finish_research_now() -> void:
	if not crystal_rush_allowed():
		return
	if research_current.is_empty() or not spend_crystals(research_finish_cost()):
		return
	research_current.end = now()
	_finish_research(false)

func _finish_research(offline: bool) -> void:
	var id: String = research_current.id
	research_current = {}
	research_done.append(id)
	stats["research"] = stats.get("research", 0) + 1
	if story_index < Defs.STORY.size() and Defs.STORY[story_index].goal[0] == "research":
		story_count += 1
	if not offline:
		event.emit("upgrade")
		rewards_granted.emit(tr("Research complete!"), [tr(research_def(id).name), tr(research_def(id).desc)])
	changed.emit()

# ---------------------------------------------------------------- снаряжение

func item_base(it: Dictionary) -> Dictionary:
	for b in Defs.ITEMS:
		if b.id == it.base:
			return b
	return Defs.ITEMS[0]

func item_name(it: Dictionary) -> String:
	return "%s %s" % [tr(Defs.ITEM_RARITY[it.rarity].name), tr(item_base(it).name)]

func item_bonus(it: Dictionary) -> int:
	var b := item_base(it)
	var bonus: int = Defs.ITEM_RARITY[it.rarity].bonus
	# универсальный костюм даёт меньше, но ко всем навыкам
	return maxi(1, bonus - 1) if b.stats.size() > 1 else bonus

func add_item(rarity: String, base_id := "") -> Dictionary:
	var base: Dictionary = Defs.ITEMS.pick_random()
	if base_id != "":
		for b in Defs.ITEMS:
			if b.id == base_id:
				base = b
	var it := {"uid": next_id, "base": base.id, "rarity": rarity}
	next_id += 1
	items.append(it)
	return it

func get_item(uid: int) -> Dictionary:
	for it in items:
		if it.uid == uid:
			return it
	return {}

func item_owner(uid: int) -> Dictionary:
	for c in colonists:
		if c.suit_item == uid or c.tool_item == uid or c.get("armor_item", -1) == uid:
			return c
	return {}

## Навык с учётом снаряжения.
func stat(c: Dictionary, k: String) -> int:
	var v: int = c[k]
	for slot in ["suit_item", "tool_item"]:
		var uid: int = c.get(slot, -1)
		if uid != -1:
			var it := get_item(uid)
			if not it.is_empty() and k in item_base(it).stats:
				v += item_bonus(it)
	return v

## Доля урона, которую гасит броня (15% / 30% / 50%).
const ARMOR_PROTECTION := {"common": 0.15, "rare": 0.3, "legendary": 0.5}

func protection(c: Dictionary) -> float:
	var uid: int = c.get("armor_item", -1)
	if uid == -1:
		return 0.0
	var it := get_item(uid)
	return 0.0 if it.is_empty() else ARMOR_PROTECTION[it.rarity]

func equip(c: Dictionary, uid: int) -> void:
	var it := get_item(uid)
	if it.is_empty():
		return
	var owner := item_owner(uid)
	if not owner.is_empty():
		owner[item_base(it).kind + "_item"] = -1
	c[item_base(it).kind + "_item"] = uid
	changed.emit()

func unequip(c: Dictionary, kind: String) -> void:
	c[kind + "_item"] = -1
	changed.emit()

# ---------------------------------------------------------------- сюжет, достижения, события

func story_current() -> Dictionary:
	return Defs.STORY[story_index] if story_index < Defs.STORY.size() else {}

func story_progress() -> int:
	var st := story_current()
	if st.is_empty():
		return 0
	match st.goal[0]:
		"population":
			return colonists.size()
		"depth":
			return max_row() + 1
	return story_count

func story_ready() -> bool:
	var st := story_current()
	return not st.is_empty() and story_progress() >= st.goal[1]

func claim_story() -> void:
	if not story_ready():
		return
	var st := story_current()
	story_index += 1
	story_count = 0
	grant(st.reward, tr(st.title))

func stat_value(key: String) -> int:
	match key:
		"population":
			return colonists.size()
		"survival_pop":
			return colonists.size() if difficulty == "survival" else 0
		"depth":
			return max_row() + 1
	return stats.get(key, 0)

func achievement_tier(a: Dictionary) -> int:
	return int(achievements_claimed.get(a.id, 0))

func achievement_ready(a: Dictionary) -> bool:
	var t := achievement_tier(a)
	return t < a.tiers.size() and stat_value(a.stat) >= a.tiers[t]

func achievements_ready() -> int:
	return Defs.ACHIEVEMENTS.filter(func(a): return achievement_ready(a)).size()

func claim_achievement(a: Dictionary) -> void:
	if not achievement_ready(a):
		return
	var t := achievement_tier(a)
	achievements_claimed[a.id] = t + 1
	grant({"crystals": a.reward[t]}, tr("Achievement: %s") % tr(a.name))

func weekly_event() -> Dictionary:
	return Defs.WEEKLY[int(now() / 604800.0) % Defs.WEEKLY.size()]

func weekly_mod() -> String:
	return weekly_event().mod

func weekly_days_left() -> int:
	return 7 - int(fmod(now(), 604800.0) / 86400.0)

func claim_weekly(tier: int) -> void:
	var ev := weekly_event()
	if tier in weekly_claimed or weekly_progress < ev.tiers[tier]:
		return
	weekly_claimed.append(tier)
	grant(Defs.WEEKLY_REWARDS[tier], tr("%s reward") % tr(ev.name))

# ---------------------------------------------------------------- пузыри с сокровищами и торговцы

func pop_bubble(rich: bool) -> Dictionary:
	stats["bubble"] = stats.get("bubble", 0) + 1
	event.emit("bubble")
	if rich:
		var cr := rng.randi_range(2, 5)
		crystals += cr
		changed.emit()
		return {"text": "[crystals]+%d" % cr, "color": Defs.RESOURCES.crystals.color}
	var p := rng.randi_range(15, 45) + max_row() * 3
	pearls += p
	changed.emit()
	return {"text": "[pearls]+%d" % p, "color": Defs.RESOURCES.pearls.color}

func _spawn_trader() -> void:
	var offers := []
	var pool := [
		{"text": "Trade %d food for %d pearls", "give": {"food": 80}, "get": {"pearls": 220}},
		{"text": "Trade %d energy for %d pearls", "give": {"energy": 80}, "get": {"pearls": 220}},
		{"text": "Buy rare gear for %d pearls", "give": {"pearls": 600}, "get": {"item": "rare"}},
		{"text": "Buy a Silver Crate for %d pearls", "give": {"pearls": 900}, "get": {"crates": {"silver": 1}}},
		{"text": "Buy %d science for %d pearls", "give": {"pearls": 250}, "get": {"science": 40}},
		{"text": "Buy legendary gear for %d crystals", "give": {"crystals": 60}, "get": {"item": "legendary"}},
	]
	pool.shuffle()
	for i in 3:
		offers.append(pool[i])
	trader = {"until": now() + 300.0, "offers": offers, "bought": []}
	banner.emit("trader", tr("Wandering Trader"), tr("A wandering trader has arrived at the airlock!"))
	event.emit("arrive")
	changed.emit()

func trade(idx: int) -> bool:
	if trader.is_empty() or idx in trader.bought:
		return false
	var o: Dictionary = trader.offers[idx]
	for k in o.give:
		var have: float = pearls if k == "pearls" else (crystals if k == "crystals" else resources.get(k, 0.0))
		if have < o.give[k]:
			message.emit(tr("Not enough resources"))
			event.emit("error")
			return false
	for k in o.give:
		if k == "pearls":
			pearls -= o.give[k]
		elif k == "crystals":
			crystals -= o.give[k]
		else:
			resources[k] -= o.give[k]
	trader.bought.append(idx)
	var g: Dictionary = o.get.duplicate()
	if g.has("science"):
		science += g.science
		g.erase("science")
		if g.is_empty():
			banner.emit("science", tr("Deal!"), "+%d %s" % [o.get.science, tr("Science")])
			event.emit("collect_energy")
			changed.emit()
			return true
	grant(g, tr("Deal!"))
	return true

# ---------------------------------------------------------------- прокачка колонистов

func best_stat(c: Dictionary) -> String:
	var best := "str"
	for k in ["tech", "bio"]:
		if c[k] > c[best]:
			best = k
	return best

func best_job_type(c: Dictionary) -> String:
	var stat := best_stat(c)
	for type in ["reactor", "oxygen", "farm"]:
		if Defs.ROOMS[type].stat == stat:
			return type
	return "farm"

func best_room_for(c: Dictionary) -> Dictionary:
	var stat := best_stat(c)
	var best := {}
	for r in rooms:
		var def: Dictionary = Defs.ROOMS[r.type]
		if def.get("stat", "") != stat or not def.has("produces"):
			continue
		if r.id != c.room and workers_in(r).size() >= slots(r):
			continue
		if best.is_empty() or r.level > best.level:
			best = r
	return best

func train_cost(c: Dictionary, stat: String) -> int:
	return 5 + c[stat] * 5

func train(c: Dictionary, stat: String) -> bool:
	if c[stat] >= 10 or not spend_crystals(train_cost(c, stat)):
		return false
	c[stat] += 1
	message.emit(tr("Trained! %s +1") % tr(Defs.STATS[stat]))
	event.emit("level_up")
	changed.emit()
	return true

func heal_cost(c: Dictionary) -> int:
	return maxi(1, ceili((100.0 - c.health) / 20.0))

func heal(c: Dictionary) -> void:
	if c.health >= 100.0 or not spend_crystals(heal_cost(c)):
		return
	c.health = 100.0
	message.emit(tr("Fully healed"))
	changed.emit()

# ---------------------------------------------------------------- задания и сезон

func refresh_daily_systems() -> void:
	if quest_day != today():
		quest_day = today()
		quests = []
		var pool := range(Defs.QUEST_POOL.size())
		pool.shuffle()
		for i in Defs.QUESTS_PER_DAY:
			var q: Dictionary = Defs.QUEST_POOL[pool[i]]
			quests.append({
				"event": q.event, "text": q.text, "target": rng.randi_range(q.target[0], q.target[1]),
				"progress": 0, "reward": q.reward, "xp": q.xp, "claimed": false,
			})
	var week := int(now() / 604800.0)
	if weekly_week != week:
		weekly_week = week
		weekly_progress = 0
		weekly_claimed = []
	if season_start < 0 or today() - season_start >= Defs.SEASON_DAYS:
		season_start = today()
		season_xp = 0
		season_pass = false
		season_claimed_free = []
		season_claimed_premium = []

func track(ev: String, amount := 1) -> void:
	event.emit(ev)
	stats[ev] = stats.get(ev, 0) + amount
	if story_index < Defs.STORY.size() and Defs.STORY[story_index].goal[0] == ev:
		story_count += amount
	if weekly_event().goal == ev:
		weekly_progress += amount
	for q in quests:
		if q.event == ev and not q.claimed and q.progress < q.target:
			q.progress = mini(q.target, q.progress + amount)
			if q.progress >= q.target:
				banner.emit("tasks", tr("Task complete!"), tr(q.text) % q.target)
				event.emit("upgrade")

func quests_ready() -> int:
	return quests.filter(func(q): return q.progress >= q.target and not q.claimed).size()

func claim_quest(q: Dictionary) -> void:
	if q.claimed or q.progress < q.target:
		return
	q.claimed = true
	season_xp += q.xp
	grant(q.reward, tr("Task complete!"))

func season_tier() -> int:
	return mini(season_xp / Defs.SEASON_XP_PER_TIER, Defs.SEASON_TIERS.size())

func season_days_left() -> int:
	return maxi(0, Defs.SEASON_DAYS - (today() - season_start))

func season_claimable() -> int:
	var n := 0
	for i in season_tier():
		if not i in season_claimed_free:
			n += 1
		if season_pass and not i in season_claimed_premium:
			n += 1
	return n

func claim_season(tier: int, premium_track: bool) -> void:
	if tier >= season_tier():
		return
	var claimed: Array = season_claimed_premium if premium_track else season_claimed_free
	if tier in claimed or (premium_track and not season_pass):
		return
	claimed.append(tier)
	var key := "premium" if premium_track else "free"
	grant(Defs.SEASON_TIERS[tier][key], tr("Season reward, tier %d") % (tier + 1))

# ---------------------------------------------------------------- сохранения

func save_game() -> void:
	var data := {
		"version": SAVE_VERSION, "time": Time.get_unix_time_from_system(),
		"resources": resources, "pearls": pearls, "rooms": rooms,
		"colonists": colonists, "next_id": next_id, "arrival_timer": arrival_timer,
		"meta": {
			"crystals": crystals, "crates": crates, "premium": premium, "no_ads": no_ads, "pet": pet, "owned": owned_products,
			"boost_until": boost_until, "free_crate_at": free_crate_at,
			"daily_day": daily_day, "daily_streak": daily_streak,
			"expeditions": expeditions, "quests": quests, "quest_day": quest_day,
			"season_start": season_start, "season_xp": season_xp, "season_pass": season_pass,
			"season_claimed_free": season_claimed_free, "season_claimed_premium": season_claimed_premium,
			"science": science, "research_done": research_done, "research_current": research_current,
			"items": items, "stats": stats, "achievements_claimed": achievements_claimed,
			"story_index": story_index, "story_count": story_count, "weekly_week": weekly_week,
			"weekly_progress": weekly_progress, "weekly_claimed": weekly_claimed, "trader": trader,
			"tutorial_done": tutorial_done, "difficulty": difficulty, "mode_chosen": mode_chosen,
		},
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return false
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY or data.get("version", 0) != SAVE_VERSION:
		return false
	resources = data.resources
	pearls = int(data.pearls)
	rooms = data.rooms
	colonists = data.colonists
	next_id = int(data.next_id)
	arrival_timer = data.arrival_timer
	var meta: Dictionary = data.get("meta", {})
	crystals = int(meta.get("crystals", 25))
	crates = {"common": 0, "silver": 0, "gold": 0}
	for k in meta.get("crates", {}):
		crates[k] = int(meta.crates[k])
	premium = bool(meta.get("premium", false))
	no_ads = bool(meta.get("no_ads", false))
	pet = str(meta.get("pet", ""))
	owned_products = meta.get("owned", [])
	boost_until = float(meta.get("boost_until", 0.0))
	free_crate_at = float(meta.get("free_crate_at", 0.0))
	daily_day = int(meta.get("daily_day", -1))
	daily_streak = int(meta.get("daily_streak", 0))
	expeditions = meta.get("expeditions", [])
	for e in expeditions:
		for k in ["id", "dock", "zone"]:
			e[k] = int(e[k])
		var crew := []
		for cid in e.crew:
			crew.append(int(cid))
		e.crew = crew
	quests = meta.get("quests", [])
	for q in quests:
		q.target = int(q.target)
		q.progress = int(q.progress)
		q.xp = int(q.xp)
	quest_day = int(meta.get("quest_day", -1))
	season_start = int(meta.get("season_start", -1))
	season_xp = int(meta.get("season_xp", 0))
	season_pass = bool(meta.get("season_pass", false))
	season_claimed_free = meta.get("season_claimed_free", []).map(func(v): return int(v))
	season_claimed_premium = meta.get("season_claimed_premium", []).map(func(v): return int(v))
	science = int(meta.get("science", 0))
	research_done = meta.get("research_done", [])
	research_current = meta.get("research_current", {})
	items = meta.get("items", [])
	for it in items:
		it.uid = int(it.uid)
	stats = {}
	var st: Dictionary = meta.get("stats", {})
	for k in st:
		stats[k] = int(st[k])
	achievements_claimed = {}
	var ac: Dictionary = meta.get("achievements_claimed", {})
	for k in ac:
		achievements_claimed[k] = int(ac[k])
	story_index = int(meta.get("story_index", 0))
	story_count = int(meta.get("story_count", 0))
	weekly_week = int(meta.get("weekly_week", -1))
	weekly_progress = int(meta.get("weekly_progress", 0))
	weekly_claimed = meta.get("weekly_claimed", []).map(func(v): return int(v))
	trader = meta.get("trader", {})
	tutorial_done = bool(meta.get("tutorial_done", true))
	difficulty = str(meta.get("difficulty", "normal"))
	mode_chosen = bool(meta.get("mode_chosen", true))
	# JSON хранит числа как float — вернём целые поля
	for r in rooms:
		for k in ["id", "col", "row", "level"]:
			r[k] = int(r[k])
		if not r.has("hazard"):
			r["hazard"] = "flood" if r.incident > 0.0 else ""
		r["spread"] = float(r.get("spread", 0.0))
		r["size"] = int(r.get("size", 1))
	for c in colonists:
		c["help"] = c.get("help", -1)
		c["suit_item"] = c.get("suit_item", -1)
		c["tool_item"] = c.get("tool_item", -1)
		c["armor_item"] = c.get("armor_item", -1)
		for k in ["id", "str", "tech", "bio", "level", "room", "suit", "help", "suit_item", "tool_item", "armor_item"]:
			c[k] = int(c[k])
	_fix_orphans()
	_apply_offline(Time.get_unix_time_from_system() - float(data.time))
	return true

func _apply_offline(elapsed: float) -> void:
	elapsed = clampf(elapsed, 0.0, MAX_OFFLINE_PREMIUM if premium else MAX_OFFLINE)
	if elapsed < 30.0:
		return
	var before := colonists.size()
	var steps := int(elapsed)
	for i in steps:
		simulate(1.0, true)
	var ready := 0
	for r in rooms:
		if r.ready:
			ready += 1
	var text := tr("While you were away (%s): %d rooms ready") % [_fmt_time(elapsed), ready]
	if colonists.size() > before:
		text += tr(", %d new colonists") % (colonists.size() - before)
	call_deferred("emit_signal", "message", text)

# ---------------------------------------------------------------- сложность

func mode() -> Dictionary:
	return Defs.DIFFICULTY.get(difficulty, Defs.DIFFICULTY.normal)

func set_difficulty(d: String) -> void:
	difficulty = d
	mode_chosen = true
	changed.emit()
	save_game()

func crystal_rush_allowed() -> bool:
	return mode().crystal_rush

## В Выживании здоровье может упасть до нуля.
func health_floor() -> float:
	return 0.0 if mode().permadeath else 10.0

func _check_deaths() -> void:
	if not mode().permadeath:
		return
	for c in colonists.duplicate():
		if c.health <= 0.0 and c.room != ON_EXPEDITION:
			colonists.erase(c)
			stats["deaths"] = stats.get("deaths", 0) + 1
			message.emit(tr("%s has died. The colony mourns.") % c.name)
			event.emit("breach")
			changed.emit()

## Колонисты, чей отсек исчез, возвращаются в шлюз.
func _fix_orphans() -> void:
	for c in colonists:
		if c.room >= 0 and get_room(c.room).is_empty():
			c.room = -1
		if c.get("help", -1) >= 0 and get_room(c.help).is_empty():
			c.help = -1

func reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	new_game()

static func _fmt_time(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%dh %dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm" % (s / 60)
	return "%ds" % s

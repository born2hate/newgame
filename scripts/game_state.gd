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
const FREE_CRATE_COOLDOWN := 4.0 * 3600.0
const BOOST_DURATION := 30.0 * 60.0
var crystals := 0
var crates := {"common": 0, "silver": 0, "gold": 0}
var premium := false
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
	rooms = []
	colonists = []
	next_id = 1
	arrival_timer = 0.0
	_add_room("reactor", 1, 0)
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
		"progress": 0.0, "ready": false, "incident": 0.0, "heat": 0.0,
	}
	next_id += 1
	rooms.append(r)
	return r

func _make_colonist() -> Dictionary:
	var c := {
		"id": next_id,
		"name": "%s %s" % [Defs.FIRST_NAMES.pick_random(), Defs.LAST_NAMES.pick_random()],
		"str": rng.randi_range(1, 4), "tech": rng.randi_range(1, 4), "bio": rng.randi_range(1, 4),
		"level": 1, "xp": 0.0, "health": 100.0, "room": -1,
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
		if r.row == row and col >= r.col and col < r.col + Defs.room_width(r.type):
			return r
	return {}

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
			cap += Defs.ROOMS.living.capacity * r.level
	return cap

func storage_cap() -> float:
	var cap := 120.0
	for r in rooms:
		if r.type == "storage":
			cap += Defs.ROOMS.storage.storage * r.level
	return cap

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

## Эффективность комнаты: сумма нужной характеристики рабочих с учётом здоровья.
func room_power(room: Dictionary) -> float:
	var def: Dictionary = Defs.ROOMS[room.type]
	if not def.has("stat"):
		return 0.0
	var total := 0.0
	for c in workers_in(room):
		total += c[def.stat] * (0.4 + 0.6 * c.health / 100.0)
	return total

func cycle_time(room: Dictionary) -> float:
	var def: Dictionary = Defs.ROOMS[room.type]
	var power := room_power(room)
	if power <= 0.0:
		return INF
	return def.cycle / (power / 5.0)

func production_amount(room: Dictionary) -> float:
	var def: Dictionary = Defs.ROOMS[room.type]
	return def.amount * (1.0 + 0.6 * (room.level - 1))

func rush_chance(room: Dictionary) -> float:
	return clampf(0.8 - room.heat * 0.15, 0.2, 0.8)

# ---------------------------------------------------------------- симуляция

func simulate(delta: float, offline: bool) -> void:
	var cap := storage_cap()
	# расход
	var energy_use := 0.0
	for r in rooms:
		energy_use += Defs.ROOMS[r.type].energy * r.level
	resources.energy = maxf(0.0, resources.energy - energy_use * delta)
	var pop := colonists.size()
	resources.oxygen = maxf(0.0, resources.oxygen - O2_PER_COLONIST * pop * delta)
	resources.food = maxf(0.0, resources.food - FOOD_PER_COLONIST * pop * delta)
	var powered: bool = resources.energy > 0.0
	var starving: bool = resources.oxygen <= 0.0 or resources.food <= 0.0

	# комнаты
	for r in rooms:
		var def: Dictionary = Defs.ROOMS[r.type]
		r.heat = maxf(0.0, r.heat - delta / 60.0)
		if r.incident > 0.0:
			r.incident = maxf(0.0, r.incident - delta)
			continue
		if def.has("produces") and not r.ready:
			var t := cycle_time(r)
			if t < INF:
				var speed := 1.0 if (powered or def.produces == "energy") else 0.25
				r.progress += delta * speed / t
				if r.progress >= 1.0:
					r.progress = 1.0
					r.ready = true

	# колонисты
	var heal_rate := 0.3
	for r in rooms:
		if Defs.ROOMS[r.type].get("heal", false) and r.incident <= 0.0:
			heal_rate += room_power(r) * 0.1 * r.level
	for c in colonists:
		if starving and not offline:
			c.health = maxf(10.0, c.health - 1.5 * delta)
		elif not starving:
			c.health = minf(100.0, c.health + heal_rate * delta)
		if c.room != -1:
			c.xp += delta
			if c.xp >= _xp_needed(c):
				_level_up(c)

	# новые колонисты
	if colonists.size() < population_cap():
		arrival_timer += delta
		if arrival_timer >= ARRIVAL_INTERVAL:
			arrival_timer = 0.0
			var c := _make_colonist()
			colonists.append(c)
			if not offline:
				message.emit(tr("New colonist arrived: %s") % c.name)
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
	message.emit(tr("%s reached level %d! %s +1") % [c.name, c.level, Defs.STATS[stat]])
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
		return false
	if not can_build_at(type, col, row):
		return false
	pearls -= cost
	var r := _add_room(type, col, row)
	track("build")
	floating_text.emit(r.id, "-%d P" % cost, Defs.RESOURCES.pearls.color)
	changed.emit()
	return true

func upgrade(room: Dictionary) -> void:
	if room.level >= Defs.MAX_LEVEL:
		return
	var cost := Defs.upgrade_cost(room.type, room.level)
	if pearls < cost:
		message.emit(tr("Not enough pearls"))
		return
	pearls -= cost
	room.level += 1
	track("upgrade")
	message.emit(tr("%s upgraded to level %d") % [Defs.ROOMS[room.type].name, room.level])
	changed.emit()

func collect(room: Dictionary) -> void:
	if not room.ready:
		return
	var def: Dictionary = Defs.ROOMS[room.type]
	var amount := production_amount(room) * (2.0 if boost_active() else 1.0)
	var res: String = def.produces
	if res == "pearls":
		pearls += int(amount)
	else:
		resources[res] = minf(storage_cap(), resources[res] + amount)
	var bonus: int = 1 + room.level
	pearls += bonus
	room.ready = false
	room.progress = 0.0
	floating_text.emit(room.id, "+%d %s" % [int(amount), Defs.RESOURCES[res].short], Defs.RESOURCES[res].color)
	track("collect_" + res, int(amount))
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
		floating_text.emit(room.id, tr("Success! +10 P"), Color(0.6, 1.0, 0.7))
	else:
		room.progress = 0.0
		room.incident = 12.0
		for c in workers_in(room):
			c.health = maxf(10.0, c.health - 25.0)
		var res: String = Defs.ROOMS[room.type].produces
		if resources.has(res):
			resources[res] = maxf(0.0, resources[res] - 15.0)
		floating_text.emit(room.id, tr("HULL BREACH!"), Color(1.0, 0.3, 0.3))
		message.emit(tr("Breach in %s! Repairs take 12s") % Defs.ROOMS[room.type].name)
	changed.emit()

func assign(colonist: Dictionary, room: Dictionary) -> bool:
	if colonist.room == ON_EXPEDITION:
		message.emit(tr("%s is away on an expedition") % colonist.name)
		return false
	if room.is_empty() or room.type == "airlock":
		colonist.room = -1
		changed.emit()
		return true
	var slots := Defs.room_slots(room.type, room.level)
	if slots == 0:
		message.emit(tr("Nobody can work here"))
		return false
	if colonist.room == room.id:
		return true
	if workers_in(room).size() >= slots:
		message.emit(tr("All slots are taken"))
		return false
	colonist.room = room.id
	colonist.xp = 0.0
	changed.emit()
	return true

func auto_assign(colonist: Dictionary, room: Dictionary) -> void:
	if not room.is_empty():
		assign(colonist, room)

# ---------------------------------------------------------------- премиум-экономика

static func now() -> float:
	return Time.get_unix_time_from_system()

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
		lines.append(tr("+%d pearls") % int(reward.pearls))
	if reward.has("crystals"):
		crystals += int(reward.crystals)
		lines.append(tr("+%d crystals") % int(reward.crystals))
	for k in reward.get("crates", {}):
		crates[k] += int(reward.crates[k])
		lines.append("+%d %s" % [int(reward.crates[k]), tr(Defs.CRATES[k].name)])
	if reward.has("colonist"):
		lines.append(_grant_colonist(reward.colonist))
	if reward.get("season_pass", false):
		season_pass = true
		lines.append(tr("Season Pass unlocked!"))
	if reward.get("premium", false):
		premium = true
		lines.append(tr("Premium unlocked!"))
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
				extra.append(tr("+%d energy, oxygen and food") % amt)
			"colonist_rare":
				extra.append(_grant_colonist("rare"))
			"colonist_legendary":
				extra.append(_grant_colonist("legendary"))
	if reward.pearls == 0:
		reward.erase("pearls")
	if reward.crystals == 0:
		reward.erase("crystals")
	var lines := []
	if reward.has("pearls"):
		pearls += reward.pearls
		lines.append(tr("+%d pearls") % reward.pearls)
	if reward.has("crystals"):
		crystals += reward.crystals
		lines.append(tr("+%d crystals") % reward.crystals)
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
			p += (c.str + c.tech + c.bio) * (0.5 + 0.5 * c.health / 100.0)
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
	var names := []
	for id in ids:
		names.append(get_colonist(id).name.split(" ")[0])
	# исход определяется сразу — так он одинаков и онлайн, и офлайн
	var loot := {}
	var L: Dictionary = zone.loot
	if L.has("pearls"):
		loot.pearls = int(rng.randi_range(L.pearls[0], L.pearls[1]) * f)
	if L.has("crystals"):
		loot.crystals = int(rng.randi_range(L.crystals[0], L.crystals[1]) * f)
	if L.has("resources"):
		loot.resources = int(rng.randi_range(L.resources[0], L.resources[1]) * f)
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
		elif roll < 0.65:
			text = Defs.LOG_FIND.pick_random()
		else:
			text = Defs.LOG_CALM.pick_random()
		events.append({"at": (i + 1.0) / (n + 1.0), "text": tr(text).replace("{n}", who)})
	for id in ids:
		get_colonist(id).room = ON_EXPEDITION
	var start := now()
	expeditions.append({
		"id": next_id, "dock": dock_id, "zone": zone_idx, "crew": ids.duplicate(),
		"start": start, "end": start + zone.minutes * 60.0,
		"events": events, "loot": loot, "damage": damage,
	})
	next_id += 1
	track("expedition")
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
		lines.append(tr("+%d energy, oxygen and food") % loot.resources)
	for id in e.crew:
		var c := get_colonist(id)
		if c.is_empty():
			continue
		c.room = -1
		c.health = maxf(10.0, c.health - e.damage.get(str(id), 0))
		c.xp += zone.minutes * 4.0
		while c.xp >= _xp_needed(c):
			c.xp -= _xp_needed(c)
			var keep: float = c.xp
			_level_up(c)
			c.xp = keep
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
	if season_start < 0 or today() - season_start >= Defs.SEASON_DAYS:
		season_start = today()
		season_xp = 0
		season_pass = false
		season_claimed_free = []
		season_claimed_premium = []

func track(event: String, amount := 1) -> void:
	for q in quests:
		if q.event == event and not q.claimed and q.progress < q.target:
			q.progress = mini(q.target, q.progress + amount)
			if q.progress >= q.target:
				message.emit(tr("Task complete: %s") % (tr(q.text) % q.target))

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
			"crystals": crystals, "crates": crates, "premium": premium, "owned": owned_products,
			"boost_until": boost_until, "free_crate_at": free_crate_at,
			"daily_day": daily_day, "daily_streak": daily_streak,
			"expeditions": expeditions, "quests": quests, "quest_day": quest_day,
			"season_start": season_start, "season_xp": season_xp, "season_pass": season_pass,
			"season_claimed_free": season_claimed_free, "season_claimed_premium": season_claimed_premium,
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
	# JSON хранит числа как float — вернём целые поля
	for r in rooms:
		for k in ["id", "col", "row", "level"]:
			r[k] = int(r[k])
	for c in colonists:
		for k in ["id", "str", "tech", "bio", "level", "room", "suit"]:
			c[k] = int(c[k])
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

extends Node
## Состояние колонии: ресурсы, комнаты, колонисты, симуляция и сохранения.

signal changed                          # что-то изменилось — перерисовать UI
signal message(text: String)            # всплывающее сообщение
signal floating_text(room_id: int, text: String, color: Color)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const ARRIVAL_INTERVAL := 180.0
const MAX_OFFLINE := 8.0 * 3600.0
const MAX_OFFLINE_PREMIUM := 16.0 * 3600.0
## Темп игры: всё рассчитано на спокойные заходы по несколько минут.
const PACE := 3.0
const O2_PER_COLONIST := 0.07 / PACE
const FOOD_PER_COLONIST := 0.05 / PACE
## Сколько секунд нужно работнику спортзала/школы/комнаты отдыха на +1 к навыку (1 уровень).
const TRAIN_TIME := 1800.0
const NATURAL_POP := 8
const MAX_POP := 100
## Дети: сколько секунд «ухаживания» в жилом отсеке (при силе обаяния 10) и сколько растёт ребёнок.
const BREED_TIME := 14400.0
const GROW_TIME := 21600.0
## Комбо-сбор: окно между сборами и множитель.
const COMBO_WINDOW := 2.5
var combo := 0
var combo_until := 0.0
## Уровень колонии: опыт за всё, что происходит в колонии.
var colony_level := 1
var colony_xp := 0
const COLONY_XP := {"collect": 2, "build": 25, "upgrade": 20, "expedition_done": 30, "incident_resolved": 15,
	"raid_won": 60, "research": 40, "level_up": 5, "craft": 15, "trade": 10, "birth": 40, "bubble": 3}
signal colony_level_up(level: int)
signal combo_changed(count: int, mult: float)
signal collected(room_id: int, res: String, amount: int)

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
var pets_owned: Array = []

func has_pet(id: String) -> bool:
	return pet == id

## Новый питомец (если уже есть все — немного кристаллов).
func grant_pet(id := "") -> String:
	var free: Array = Defs.PETS.keys().filter(func(k): return not k in pets_owned)
	if free.is_empty():
		crystals += 10
		return tr("+%d crystals") % 10
	if id == "" or id in pets_owned:
		id = free.pick_random()
	pets_owned.append(id)
	if pet == "":
		pet = id
	return tr("New pet: %s! %s") % [tr(Defs.PETS[id].name), tr(Defs.PETS[id].desc)]

func set_pet(id: String) -> void:
	if id in pets_owned:
		pet = id
		changed.emit()
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

var _paused_at := 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()
		_paused_at = Time.get_unix_time_from_system()
	elif what == NOTIFICATION_APPLICATION_RESUMED and _paused_at > 0.0:
		# свернули и вернулись, не закрывая игру — досчитываем время отсутствия
		var away := Time.get_unix_time_from_system() - _paused_at
		_paused_at = 0.0
		_apply_offline(away)

# ---------------------------------------------------------------- новая игра

func new_game() -> void:
	resources = {"energy": 60.0, "oxygen": 60.0, "food": 60.0}
	pearls = 250
	crystals = 25
	crates = {"common": 1, "silver": 0, "gold": 0}
	premium = false
	no_ads = false
	pet = ""
	pets_owned = []
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
	fallen = []
	colony_level = 1
	colony_xp = 0
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
		"end": rng.randi_range(1, 4), "cha": rng.randi_range(1, 4), "luck": rng.randi_range(1, 4),
		"mood": 70.0, "train": 0.0,
		"level": 1, "xp": 0.0, "health": 100.0, "room": -1, "help": -1, "suit_item": -1, "tool_item": -1, "armor_item": -1, "weapon_item": -1,
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
		if c.room == room.id and not c.get("child", false):
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
	# дороже каждый следующий такой же и, понемногу, каждый отсек вообще
	var total := rooms.filter(func(r): return r.type != "elevator" and r.type != "airlock").size()
	return int(base * (1.0 + 0.6 * count_of(type)) * (1.0 + 0.04 * total))

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
	if row < int(Defs.ROOMS[type].get("min_row", 0)):
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
		total += stat(c, def.stat) * (0.4 + 0.6 * c.health / 100.0) * mood_factor(c)
	return total

## Настроение 0..100 меняет скорость работы от ×0.7 до ×1.2.
func mood_factor(c: Dictionary) -> float:
	return 0.7 + 0.5 * float(c.get("mood", 70.0)) / 100.0

## Общая прибавка к настроению от кухонь, комнат отдыха и аквариумов (до +40).
func mood_bonus() -> float:
	var b := 0.0
	for r in rooms:
		b += float(Defs.ROOMS[r.type].get("mood", 0)) * r.level * r.size
	if has_pet("angel"):
		b += 10.0
	return minf(40.0, b)

## Сила всех отсеков типа (для пассивных эффектов: радио, оружейная).
func type_power(type: String) -> float:
	var p := 0.0
	for r in rooms:
		if r.type == type and r.incident <= 0.0:
			p += room_power(r) * (1.0 + 0.25 * (r.level - 1))
	return p

## Прибавка к жемчугу от аквариумов.
func pearl_bonus() -> float:
	var b := 0.0
	for r in rooms:
		b += float(Defs.ROOMS[r.type].get("pearl_bonus", 0.0)) * r.level * r.size
	return b

## Скидка у торговца за обаяние лучшего колониста (до 30%).
func trade_discount() -> float:
	var best := 0
	for c in colonists:
		if c.room != ON_EXPEDITION:
			best = maxi(best, stat(c, "cha"))
	return minf(0.3, best * 0.03)

## Как в Fallout: пока колония маленькая, люди сами приходят к шлюзу,
## потом — редко; основной приток даёт радиорубка (и дети).
func arrival_speed() -> float:
	# первые NATURAL_POP человек приходят сами (каждые ARRIVAL_INTERVAL с), дальше — только по радио:
	# сила радиорубки 10 ≈ один человек в час
	var base := 1.0 if colonists.size() < NATURAL_POP else 0.0
	var rp := type_power("radio")
	# сила 10 ≈ один человек в 2 часа, дальше с убывающей отдачей
	var per_hour := 0.5 * pow(rp / 10.0, 0.6) if rp > 0.0 else 0.0
	return base + per_hour * ARRIVAL_INTERVAL / 3600.0

func armory_bonus() -> float:
	return (1.0 + type_power("armory") * 0.04) * (1.25 if has_pet("puffer") else 1.0)

## Шанс удвоить сбор: удача работников отсека.
func luck_chance(room: Dictionary) -> float:
	var l := 0.0
	for c in workers_in(room):
		l += stat(c, "luck")
	return minf(0.4, l * 0.015)

## Время до следующего +1 в тренировочном отсеке (для этого уровня).
func train_time(room: Dictionary) -> float:
	return TRAIN_TIME / (1.0 + 0.5 * (room.level - 1))

## Строка о пассивном эффекте отсека для карточки (пустая, если эффекта нет).
func room_effect(r: Dictionary) -> String:
	var def: Dictionary = Defs.ROOMS[r.type]
	var parts := []
	if def.has("train"):
		var names: Array = def.train.map(func(k): return tr(Defs.STATS[k]))
		parts.append(tr("Trains: %s · +1 every %s of work") % [", ".join(names), tr("%d min") % ceili(train_time(r) / 60.0)])
	if def.get("mood", 0) > 0:
		parts.append(tr("Mood +%d for everyone") % (int(def.mood) * r.level * r.size))
	if def.get("xp_bonus", 0.0) > 0.0:
		parts.append(tr("Colonist XP +%d%%") % int(def.xp_bonus * r.level * r.size * 100))
	if def.get("pearl_bonus", 0.0) > 0.0:
		parts.append(tr("Pearls +%d%%") % int(def.pearl_bonus * r.level * r.size * 100))
	match r.type:
		"radio":
			parts.append(tr("New colonists arrive %d%% faster") % int((arrival_speed() - 1.0) * 100))
		"armory":
			parts.append(tr("Fighting incidents +%d%%") % int((armory_bonus() - 1.0) * 100))
	return "\n".join(parts)

func cycle_time(room: Dictionary) -> float:
	var def: Dictionary = Defs.ROOMS[room.type]
	var power := room_power(room)
	if def.has("auto"):
		power = float(def.auto)
	# аварийный режим: без людей и без энергии реактор всё равно медленно работает
	if power <= 0.0 and room.type == "reactor" and resources.get("energy", 0.0) < 10.0:
		power = 2.0
	if power <= 0.0:
		return INF
	# убывающая отдача: вдвое сильнее команда — примерно в 1.5 раза быстрее
	# и потолок ×3 — иначе прокачанные отсеки печатают ресурсы без меры
	var t: float = def.cycle * PACE / minf(3.0, pow(power / 5.0, 0.6))
	return t * (2.0 if room.get("damaged", false) else 1.0)

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
		m *= mode().reward * (1.0 + pearl_bonus())
	if res == "gear":
		return 1.0
	if res == "pearls":
		# жемчуг — валюта: уровни и объединение дают меньше, чем у ресурсов
		return def.amount * (1.0 + 0.3 * (room.level - 1)) * (1.0 + 0.7 * (room.size - 1)) * m
	return def.amount * (1.0 + 0.6 * (room.level - 1)) * room.size * m

func rush_chance(room: Dictionary) -> float:
	return clampf(0.8 - room.heat * 0.15 + (0.15 if has_pet("parrot") else 0.0), 0.2, 0.95)

# ---------------------------------------------------------------- симуляция

func simulate(delta: float, offline: bool) -> void:
	var cap := storage_cap()
	# расход
	var energy_use := 0.0
	for r in rooms:
		energy_use += Defs.ROOMS[r.type].energy / PACE * r.level * r.size * (0.6 if has_research("fusion_core") else 1.0)
	resources.energy = maxf(0.0, resources.energy - energy_use * delta)
	var pop := colonists.size()
	var consume: float = mode().consume * (OFFLINE_CONSUME if offline else 1.0)
	resources.oxygen = maxf(0.0, resources.oxygen - O2_PER_COLONIST * pop * delta * consume)
	resources.food = maxf(0.0, resources.food - FOOD_PER_COLONIST * pop * delta * consume)
	var powered: bool = resources.energy > 0.0
	var starving: bool = resources.oxygen <= 0.0 or resources.food <= 0.0

	# комнаты
	for r in rooms:
		var def: Dictionary = Defs.ROOMS[r.type]
		r.heat = maxf(0.0, r.heat - delta / 60.0)
		if r.incident > 0.0:
			if r.hazard == "raid":
				continue
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
					if has_research("auto_collectors") and not offline and def.produces in ["energy", "oxygen", "food"]:
						# автосбор только базовых ресурсов, только в игре и вполовину — жемчуг и науку собираем сами
						r.ready = false
						r.progress = 0.0
						resources[def.produces] = minf(storage_cap(), resources[def.produces] + production_amount(r) * 0.5)

	# колонисты
	var heal_rate := 0.3
	for r in rooms:
		if Defs.ROOMS[r.type].get("heal", false) and r.incident <= 0.0:
			heal_rate += room_power(r) * 0.1 * r.level
	if has_research("medical_ai"):
		heal_rate *= 3.0
	if has_pet("tang"):
		heal_rate *= 1.5
	var xp_mult := 1.5 if has_research("training_programs") else 1.0
	for r in rooms:
		xp_mult += float(Defs.ROOMS[r.type].get("xp_bonus", 0.0)) * r.level * r.size
	var mood_target := 60.0 + mood_bonus() - (35.0 if starving else 0.0) - (15.0 if not powered else 0.0)
	_tick_family(delta, offline)
	if colonists.size() > int(stats.get("max_pop", 0)):
		stats["max_pop"] = colonists.size()
	if not stats.has("founded"):
		stats["founded"] = today()
	for c in colonists:
		var mt := mood_target
		var here := get_room(c.room) if c.room >= 0 else {}
		if not here.is_empty() and here.incident > 0.0:
			mt -= 20.0
		if c.room == -1:
			mt -= 10.0
		c["mood"] = clampf(float(c.get("mood", 70.0)) + (clampf(mt, 0.0, 100.0) - float(c.get("mood", 70.0))) * minf(1.0, delta / 90.0), 0.0, 100.0)
		if not here.is_empty() and here.incident <= 0.0 and powered and Defs.ROOMS[here.type].has("train"):
			_tick_training(c, here, delta, offline)
		if starving and not offline and mode().hunger:
			c.health = maxf(health_floor(), c.health - 0.35 * delta * mode().damage)
		elif not starving and c.health > 0.0:
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
			incident_timer = rng.randf_range(300.0, 540.0) * mult * mode().incidents
			_spawn_random_incident()
	if not offline:
		_tick_raid(delta)
		_tick_boss(delta)
	if not offline and colonists.size() >= 6:
		trader_timer -= delta * (2.0 if has_research("trader_beacon") else 1.0) * (1.0 + type_power("radio") * 0.03)
		if trader_timer <= 0.0:
			trader_timer = rng.randf_range(420.0, 720.0)
			_spawn_trader()
	if not trader.is_empty() and now() > float(trader.until):
		trader = {}
		changed.emit()
	if not research_current.is_empty() and now() >= float(research_current.end):
		_finish_research(offline)

	# новые колонисты
	var at_base0 := colonists.filter(func(c): return c.room != ON_EXPEDITION).size()
	if colonists.size() < population_cap() and colonists.size() < MAX_POP and (arrival_speed() > 0.0 or at_base0 == 0):
		# если на базе никого не осталось — помощь приходит быстрее
		var at_base := colonists.filter(func(c): return c.room != ON_EXPEDITION).size()
		# база пуста (все в экспедиции или погибли) — кто-нибудь всё равно придёт, чтобы не застрять
		var spd := maxf(arrival_speed(), 1.0) if at_base == 0 else arrival_speed()
		arrival_timer += delta * (4.0 if at_base == 0 else (2.0 if at_base <= 2 else 1.0)) * spd
		if arrival_timer >= ARRIVAL_INTERVAL:
			arrival_timer = 0.0
			var c := _make_colonist()
			for k in ["oxygen", "food", "energy"]:
				resources[k] = minf(storage_cap(), resources[k] + 25.0)
			if has_research("legendary_signal") and rng.randf() < 0.1:
				for k in Defs.ALL_STATS:
					c[k] = rng.randi_range(4, 7)
				c["rarity"] = "rare"
			colonists.append(c)
			if not offline:
				banner.emit("suit_%d" % c.suit, tr("New colonist arrived: %s") % "", c.name)
				event.emit("arrive")
			changed.emit()
	for k in resources:
		resources[k] = minf(resources[k], cap)

## Дети: двое в жилом отсеке со временем заводят ребёнка (быстрее с обаянием и настроением),
## ребёнок растёт и становится колонистом со статами родителей.
func _tick_family(delta: float, offline: bool) -> void:
	for c in colonists:
		if c.get("child", false):
			c["grow"] = float(c.get("grow", GROW_TIME)) - delta
			if c.grow <= 0.0:
				c.erase("child")
				c.erase("grow")
				c.room = -1
				if not offline:
					banner.emit("suit_%d" % c.suit, tr("All grown up!"), tr("%s is ready to work.") % c.name)
				changed.emit()
	for r in rooms:
		if not Defs.ROOMS[r.type].get("breeds", false) or r.incident > 0.0:
			continue
		var pair := workers_in(r)
		if pair.size() < 2 or colonists.size() >= mini(population_cap(), MAX_POP):
			r.progress = 0.0
			continue
		var cha := 0.0
		var mood := 0.0
		for c in pair.slice(0, 2):
			cha += stat(c, "cha")
			mood += float(c.get("mood", 70.0))
		r.progress += delta * (0.4 + cha / 20.0) * (0.5 + mood / 200.0) / BREED_TIME
		if r.progress >= 1.0:
			r.progress = 0.0
			_birth(r, pair[0], pair[1], offline)

func _birth(r: Dictionary, a: Dictionary, b: Dictionary, offline: bool) -> void:
	var kid := _make_colonist()
	for k in Defs.ALL_STATS:
		kid[k] = clampi(int(round((int(a[k]) + int(b[k])) / 2.0)) + rng.randi_range(-1, 1), 1, 10)
	kid.name = "%s %s" % [Defs.FIRST_NAMES.pick_random(), a.name.split(" ")[-1]]
	kid["child"] = true
	kid["grow"] = GROW_TIME
	kid.room = r.id
	colonists.append(kid)
	track("birth")
	if not offline:
		banner.emit("suit_%d" % kid.suit, tr("A child is born!"), tr("%s and %s welcome %s.") % [a.name.split(" ")[0], b.name.split(" ")[0], kid.name.split(" ")[0]])
		event.emit("arrive")
	changed.emit()

func _tick_training(c: Dictionary, room: Dictionary, delta: float, offline: bool) -> void:
	var opts: Array = Defs.ROOMS[room.type].train.filter(func(k): return c[k] < 10)
	if opts.is_empty():
		return
	c["train"] = float(c.get("train", 0.0)) + delta * mood_factor(c)
	if c.train < train_time(room):
		return
	c.train = 0.0
	opts.sort_custom(func(a, b): return c[a] < c[b])
	var k: String = opts[0]
	c[k] += 1
	track("level_up")
	if not offline:
		floating_text.emit(room.id, "%s +1" % tr(Defs.STATS[k]), Defs.STAT_COLORS[k])
		event.emit("level_up")
	changed.emit()

func _xp_needed(c: Dictionary) -> float:
	# каждый следующий уровень заметно дольше: 10 мин, 40 мин, 1.5 ч, 2.7 ч, 4 ч…
	return 600.0 * c.level * c.level

func _level_up(c: Dictionary) -> void:
	c.xp = 0.0
	c.level += 1
	track("level_up")
	var room := get_room(c.room)
	var stat: String = Defs.ROOMS[room.type].get("stat", "") if not room.is_empty() else ""
	if not room.is_empty() and Defs.ROOMS[room.type].has("train"):
		stat = Defs.ROOMS[room.type].train.pick_random()
	if stat == "":
		stat = Defs.ALL_STATS.pick_random()
	c[stat] = mini(10, c[stat] + 1)
	pearls += 5
	banner.emit("suit_%d" % c.suit, tr("Level %d") % c.level, tr("%s reached level %d! %s +1") % [c.name, c.level, tr(Defs.STATS[stat])])
	changed.emit()

func seconds_until_arrival() -> float:
	if colonists.size() >= population_cap() or arrival_speed() <= 0.0:
		return -1.0
	return (ARRIVAL_INTERVAL - arrival_timer) / arrival_speed()

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

## Ремонт сломанного отсека: четверть цены стройки, мастерская делает вдвое дешевле.
func repair_cost(room: Dictionary) -> int:
	var c := int(Defs.ROOMS[room.type].cost * 0.25 * room.level * room.size)
	if count_of("workshop") > 0:
		c = c / 2
	return maxi(10, c)

func repair(room: Dictionary) -> bool:
	if not room.get("damaged", false):
		return false
	var c := repair_cost(room)
	if pearls < c:
		message.emit(tr("Not enough pearls"))
		event.emit("error")
		return false
	pearls -= c
	room.erase("damaged")
	track("repair")
	message.emit(tr("%s repaired!") % tr(Defs.ROOMS[room.type].name))
	event.emit("upgrade")
	changed.emit()
	return true

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

## combo_ok — сбор нажатием на отсек (растит комбо); «Собрать всё» комбо не даёт.
func collect(room: Dictionary, silent := false, combo_ok := true) -> void:
	if not room.ready:
		return
	var def: Dictionary = Defs.ROOMS[room.type]
	var res: String = def.produces
	if res == "gear":
		_collect_gear(room, silent)
		return
	# ×2 за рекламу — только на базовые ресурсы, валюту (жемчуг, наука) не удваивает
	var boosted: bool = boost_active() and res in ["energy", "oxygen", "food"]
	var amount := production_amount(room) * (2.0 if boosted else 1.0) * (1.0 + (PET_BONUS if has_pet("clownfish") else 0.0))
	if not silent and combo_ok:
		# собираешь подряд — растёт множитель (до +50%), на жемчуг не действует
		var tnow := Time.get_ticks_msec() / 1000.0
		combo = combo + 1 if tnow < combo_until else 1
		combo_until = tnow + COMBO_WINDOW
		if res != "pearls":
			amount *= combo_mult()
		combo_changed.emit(combo, combo_mult())
	var lucky := rng.randf() < luck_chance(room)
	if lucky:
		amount *= 2.0
		if not silent:
			floating_text.emit(room.id, tr("Lucky! ×2"), Defs.STAT_COLORS.luck)
	if res == "pearls":
		pearls += int(amount)
	elif res == "science":
		science += int(amount)
	else:
		resources[res] = minf(storage_cap(), resources[res] + amount)
	# немного жемчуга за сбор только с улучшенных отсеков
	pearls += room.level - 1
	room.ready = false
	room.progress = 0.0
	var zone := depth_zone(room.row)
	if zone.crystal_chance > 0.0 and rng.randf() < zone.crystal_chance:
		var cr := 1
		crystals += cr
		if not silent:
			floating_text.emit(room.id, "[crystals]+%d" % cr, Defs.RESOURCES.crystals.color)
	if silent:
		stats["collect"] = stats.get("collect", 0) + 1
		return
	floating_text.emit(room.id, "[%s]+%d" % [res, int(amount)], Defs.RESOURCES[res].color)
	collected.emit(room.id, res, int(amount))
	track("collect_" + res, int(amount))
	track("collect")
	changed.emit()

func _collect_gear(room: Dictionary, silent: bool) -> void:
	room.ready = false
	room.progress = 0.0
	var luck := 0.0
	for c in workers_in(room):
		luck += stat(c, "luck")
	var roll := rng.randf()
	var rarity := "common"
	if roll < 0.04 + 0.005 * luck + 0.02 * (room.level - 1):
		rarity = "legendary"
	elif roll < 0.3 + 0.01 * luck + 0.1 * (room.level - 1):
		rarity = "rare"
	var it := add_item(rarity)
	track("collect")
	track("craft")
	if not silent:
		floating_text.emit(room.id, "[item_%s]+1" % it.base, Defs.ITEM_RARITY[rarity].color)
		banner.emit("item_" + it.base, tr("New gear crafted!"), "%s (%s)" % [item_name(it), tr(rarity.capitalize())])
		event.emit("collect_energy")
	changed.emit()

func collect_all() -> int:
	var n := 0
	for r in rooms:
		if r.ready:
			collect(r, false, false)
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
	if colonist.get("child", false):
		message.emit(tr("%s is a child and can't work yet") % colonist.name)
		return false
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

## Сдвиг часов — только для симулятора экономики (tools/economy_sim.gd).
static var clock_offset := 0.0

static func now() -> float:
	return Time.get_unix_time_from_system() + clock_offset

## Premium включает отключение рекламы.
func ads_removed() -> bool:
	return premium or no_ads

func boost_active() -> bool:
	return now() < boost_until

func boost_left() -> float:
	return maxf(0.0, boost_until - now())

## Реклама за награду: не больше AD_DAILY_LIMIT в день — иначе ресурсы бесконечные.
const AD_DAILY_LIMIT := 12
var ads_day := -1
var ads_count := 0

var pearl_buys := {}
var pearl_buys_day := -1

func pearl_buys_today(id: String) -> int:
	return int(pearl_buys.get(id, 0)) if pearl_buys_day == today() else 0

func note_pearl_buy(id: String) -> void:
	if pearl_buys_day != today():
		pearl_buys_day = today()
		pearl_buys = {}
	pearl_buys[id] = int(pearl_buys.get(id, 0)) + 1

func ads_left() -> int:
	if ads_day != today():
		return AD_DAILY_LIMIT
	return maxi(0, AD_DAILY_LIMIT - ads_count)

func register_ad() -> void:
	if ads_day != today():
		ads_day = today()
		ads_count = 0
	ads_count += 1

func start_boost() -> void:
	# копится не больше чем на 2 часа вперёд
	boost_until = minf(maxf(boost_until, now()) + BOOST_DURATION, now() + 4.0 * BOOST_DURATION)
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
	return clampi(ceili((1.0 - room.progress) * t / 60.0), 1, 60)

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
		var it := add_item(reward.item, reward.get("item_base", ""))
		lines.append("[item_%s]" % it.base + tr("New gear: %s") % item_name(it))
	if reward.has("pet"):
		lines.append("[pet]" + grant_pet(str(reward.pet)))
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
	if colonists.size() >= mini(population_cap(), MAX_POP):
		pearls += 300
		return tr("No room for a new colonist: +300 pearls instead")
	var c := _make_colonist()
	var lo := 4 if rarity == "rare" else 7
	var hi := 7 if rarity == "rare" else 10
	for k in Defs.ALL_STATS:
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
	for k in Defs.ALL_STATS:
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
			"pet":
				extra.append("[pet]" + grant_pet())
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
	return colonists.filter(func(c): return c.room != ON_EXPEDITION and not c.get("child", false))

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
	var loot_mult: float = (1.2 if has_pet("lion") else 1.0) * (1.25 if has_research("sonar_mapping") else 1.0) * (1.5 if weekly_mod() == "explorers" else 1.0) * mode().reward
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
	if rng.randf() < 0.06 + 0.07 * zone_idx:
		var roll := rng.randf()
		var rarity := "common"
		if roll < 0.02 * zone_idx:
			rarity = "legendary"
		elif roll < 0.08 + 0.08 * zone_idx:
			rarity = "rare"
		loot.item = rarity
		# предмет выбираем сразу, чтобы в журнале было видно, что именно нашли
		loot["item_base"] = Defs.ITEMS.pick_random().id
	if L.has("crate") and rng.randf() < 0.15 + 0.3 * f:
		loot.crates = {L.crate: 1}
	if L.has("survivor") and rng.randf() < L.survivor * f:
		loot.colonist = "rare"
	var events := _plan_expedition(zone_idx, ids, f, loot)
	var damage := {}
	for ev in events:
		for k in ev.get("hp", {}):
			damage[k] = damage.get(k, 0) + ev.hp[k]
	# в половине походов — событие с выбором где-то в середине пути
	var choice := {}
	if rng.randf() < 0.5 + 0.1 * zone_idx:
		var ch: Dictionary = Defs.EXP_CHOICES.pick_random()
		choice = {"id": ch.id, "at": rng.randf_range(0.3, 0.7), "pick": ""}
	for id in ids:
		get_colonist(id).room = ON_EXPEDITION
		get_colonist(id).help = -1
	var start := now()
	expeditions.append({
		"id": next_id, "dock": dock_id, "zone": zone_idx, "crew": ids.duplicate(),
		"start": start, "end": start + zone.minutes * 60.0 * (0.7 if has_research("bathyscaphe_engines") else 1.0),
		"events": events, "loot": loot, "damage": damage, "choice": choice,
	})
	next_id += 1
	track("expedition")
	track("expedition_" + zone.id)
	message.emit(tr("The bathyscaphe departs for %s!") % tr(zone.name))
	changed.emit()
	save_game()
	return true

## Расписание экспедиции, как журнал в Fallout: бои с конкретными существами (урон и опыт),
## находки по ходу (жемчуг, кристаллы, снаряжение, ящик), спокойные записи.
## Добыча из loot раскладывается по находкам, так что «налутили уже» всегда сходится с итогом.
func _plan_expedition(zone_idx: int, ids: Array, f: float, loot: Dictionary) -> Array:
	var zone: Dictionary = Defs.ZONES[zone_idx]
	var n := clampi(4 + zone.minutes / 15, 4, 14)
	var kinds := []
	for i in n:
		var roll := rng.randf()
		if roll < zone.danger * 1.1 + 0.12:
			kinds.append("fight")
		elif roll < 0.6:
			kinds.append("find")
		else:
			kinds.append("calm")
	# находок должно хватить на всю добычу
	var drops := []
	for k in ["pearls", "crystals", "resources"]:
		if loot.get(k, 0) > 0:
			drops.append(k)
	for k in ["item", "crates", "colonist"]:
		if loot.has(k):
			drops.append(k)
	var finds := []
	for i in n:
		if kinds[i] == "find":
			finds.append(i)
	var i2 := n - 1
	while finds.size() < mini(drops.size(), n) and i2 >= 0:
		if kinds[i2] != "find":
			kinds[i2] = "find"
			finds.append(i2)
		i2 -= 1
	finds.sort()
	# разложим: редкое — ближе к концу, жемчуг и кристаллы — частями
	var slot_loot := {}
	for idx in finds:
		slot_loot[idx] = {}
	var late: Array = finds.duplicate()
	late.reverse()
	var li := 0
	for k in ["colonist", "crates", "item"]:
		if loot.has(k) and li < late.size():
			slot_loot[late[li]][k] = loot[k]
			if k == "item":
				slot_loot[late[li]]["item_base"] = loot.get("item_base", "")
			li += 1
	for k in ["pearls", "crystals", "resources"]:
		var total: int = loot.get(k, 0)
		if total <= 0 or finds.is_empty():
			continue
		var parts := finds.filter(func(x): return slot_loot[x].is_empty() or rng.randf() < 0.4)
		if parts.is_empty():
			parts = [finds[0]]
		var left := total
		for j in parts.size():
			var part := left if j == parts.size() - 1 else int(total / float(parts.size()) * rng.randf_range(0.6, 1.4))
			part = clampi(part, 0, left)
			left -= part
			if part > 0:
				slot_loot[parts[j]][k] = slot_loot[parts[j]].get(k, 0) + part
	var events := []
	var used := []
	for i in n:
		var at := (i + 1.0) / (n + 1.0)
		var who_id: int = ids.pick_random()
		var who: String = get_colonist(who_id).name.split(" ")[0]
		var ev := {"at": at, "kind": kinds[i], "xp": 0, "hp": {}, "loot": {}}
		match kinds[i]:
			"fight":
				var foe: String = tr(Defs.ENEMIES[zone.id].pick_random())
				var win := rng.randf() < clampf(0.15 + f * 0.85 - zone.danger * 0.25, 0.2, 0.95)
				var dmg := int(rng.randi_range(5, 14) * (1.0 + zone_idx * 0.4) * (1.0 if win else 1.8))
				var xp := (12 + zone_idx * 8) if win else (5 + zone_idx * 4)
				ev.hp = {str(who_id): dmg}
				ev.xp = xp
				ev["won"] = win
				var tpl: String = (Defs.LOG_FIGHT_WIN if win else Defs.LOG_FIGHT_LOSE).pick_random()
				ev.text = tr(tpl).replace("{n}", who).replace("{e}", foe).replace("{h}", str(dmg)).replace("{x}", str(xp))
			"find":
				var got: Dictionary = slot_loot.get(i, {})
				ev.loot = got
				ev.xp = 3
				var lines := []
				for k in got:
					var v := ""
					match k:
						"pearls", "crystals", "resources": v = str(got[k])
						"item":
							var base := {"id": got.get("item_base", ""), "rarity": got[k], "uid": -1, "base": got.get("item_base", "")}
							v = item_name(base) if base.base != "" else tr(Defs.ITEM_RARITY[got[k]].name)
						"item_base": continue
						"crates": v = tr(Defs.CRATES[got[k].keys()[0]].name)
					var key: String = "crate" if k == "crates" else k
					lines.append(tr(Defs.LOG_LOOT[key]).replace("{n}", who).replace("{v}", v))
				if lines.is_empty():
					var zl: Array = Defs.LOG_ZONE[zone.id].filter(func(x): return not x in used)
					var zline: String = zl.pick_random() if not zl.is_empty() else Defs.LOG_CALM.pick_random()
					used.append(zline)
					lines.append(tr(zline).replace("{n}", who))
				ev.text = " ".join(lines)
			_:
				# без повторов: каждая спокойная запись — не больше одного раза за поход
				var pool: Array = (Defs.LOG_ZONE[zone.id] if rng.randf() < 0.6 else Defs.LOG_CALM).filter(func(x): return not x in used)
				if pool.is_empty():
					pool = Defs.LOG_CALM.filter(func(x): return not x in used)
				var line: String = pool.pick_random() if not pool.is_empty() else Defs.LOG_CALM[0]
				used.append(line)
				ev.text = tr(line).replace("{n}", who)
		events.append(ev)
	return events

## Событие с выбором, которое сейчас ждёт решения игрока (или пусто).
func pending_choice(e: Dictionary) -> Dictionary:
	var ch: Dictionary = e.get("choice", {})
	if ch.is_empty() or ch.pick != "" or expedition_progress(e) < float(ch.at):
		return {}
	for d in Defs.EXP_CHOICES:
		if d.id == ch.id:
			return d
	return {}

func resolve_choice(e: Dictionary, risk: bool) -> String:
	var ch: Dictionary = e.get("choice", {})
	if ch.is_empty() or ch.pick != "":
		return ""
	ch.pick = "a" if risk else "b"
	var zone_idx: int = e.zone
	var who_id: int = e.crew.pick_random()
	var who: String = get_colonist(who_id).get("name", "?").split(" ")[0]
	var text := tr("The crew decided to move on.")
	var ev := {"at": expedition_progress(e), "kind": "choice", "xp": 5, "hp": {}, "loot": {}}
	if risk:
		var luck := 0.0
		for id in e.crew:
			luck += stat(get_colonist(id), "luck")
		var ok := rng.randf() < 0.5 + luck * 0.02
		match ch.id:
			"chest", "glow":
				if ok:
					var cr := rng.randi_range(2, 4) + zone_idx * 2
					e.loot["crystals"] = int(e.loot.get("crystals", 0)) + cr
					ev.loot = {"crystals": cr}
					text = tr("{n} took the risk and found {v} crystals!").replace("{n}", who).replace("{v}", str(cr))
				else:
					var dmg := 15 + zone_idx * 6
					e.damage[str(who_id)] = int(e.damage.get(str(who_id), 0)) + dmg
					ev.hp = {str(who_id): dmg}
					text = tr("It was a trap! {n} got hurt. −{h} HP").replace("{n}", who).replace("{h}", str(dmg))
			"stranger":
				if ok:
					e.loot["colonist"] = "rare"
					ev.loot = {"colonist": "rare"}
					text = tr("{n} rescued the stranger — they will join the colony!").replace("{n}", who)
				else:
					var dmg := 18 + zone_idx * 6
					e.damage[str(who_id)] = int(e.damage.get(str(who_id), 0)) + dmg
					ev.hp = {str(who_id): dmg}
					text = tr("It was an ambush! {n} fought free. −{h} HP").replace("{n}", who).replace("{h}", str(dmg))
			"cave":
				if ok:
					var left := float(e.end) - now()
					e.end = now() + left * 0.6
					text = tr("The shortcut worked! The sub will be home sooner.")
				else:
					var dmg := 20 + zone_idx * 6
					e.damage[str(who_id)] = int(e.damage.get(str(who_id), 0)) + dmg
					ev.hp = {str(who_id): dmg}
					text = tr("Something attacked in the cave! {n} was hurt. −{h} HP").replace("{n}", who).replace("{h}", str(dmg))
	ev["text"] = text
	e.events.append(ev)
	e.events.sort_custom(func(x, y): return float(x.at) < float(y.at))
	changed.emit()
	return text

func visible_events(e: Dictionary) -> Array:
	var p := expedition_progress(e)
	return e.events.filter(func(ev): return ev.at <= p)

func visible_log(e: Dictionary) -> Array:
	return visible_events(e).map(func(ev): return ev.text)

## Что уже случилось в экспедиции: опыт, бои, урон по каждому, добыча.
func expedition_so_far(e: Dictionary) -> Dictionary:
	var out := {"xp": 0, "won": 0, "lost": 0, "hp": {}, "loot": {}}
	for ev in visible_events(e):
		out.xp += int(ev.get("xp", 0))
		if ev.get("kind", "") == "fight":
			if ev.get("won", false):
				out.won += 1
			else:
				out.lost += 1
		var hp: Dictionary = ev.get("hp", {})
		for k in hp:
			out.hp[k] = out.hp.get(k, 0) + hp[k]
		var lt: Dictionary = ev.get("loot", {})
		for k in lt:
			if lt[k] is int or lt[k] is float:
				out.loot[k] = out.loot.get(k, 0) + int(lt[k])
			else:
				out.loot[k] = lt[k]
	return out

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
	if e.get("ad_used", false):
		return
	e["ad_used"] = true
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
		if c.health <= 0.0:
			# погиб в походе — тело привозят в док
			c["died_in"] = e.dock
		# опыт: за время в пути и за всё, что случилось в журнале
		c.xp += zone.minutes * 1.0 + expedition_so_far_all(e)
		while c.xp >= _xp_needed(c):
			c.xp -= _xp_needed(c)
			var keep: float = c.xp
			_level_up(c)
			c.xp = keep
	track("expedition_done")
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

## Опыт со всех записей журнала (для выдачи при возвращении).
func expedition_so_far_all(e: Dictionary) -> int:
	var x := 0
	for ev in e.events:
		x += int(ev.get("xp", 0))
	return x

# ---------------------------------------------------------------- инциденты

const HAZARDS := {
	"fire": {"label": "FIRE", "msg": "Fire in %s!", "damage": 1.6},
	"flood": {"label": "FLOOD", "msg": "Flooding in %s!", "damage": 1.2},
	"creature": {"label": "ATTACK", "msg": "Creature attack in %s!", "damage": 2.4},
	"raid": {"label": "PIRATES", "msg": "Pirates in %s!", "damage": 0.0},
}

# ---------------------------------------------------------------- левиафан (босс глубины)
## Раз в несколько часов игры у купола появляется чудовище. Игрок бьёт его нажатиями,
## колонисты помогают сами; чудовище раз в BOSS_ATTACK секунд нападает на случайный отсек.
## Не успели за BOSS_TIME — уплывает. Вне игры не появляется.
const BOSS_MIN_POP := 15
## Виды боссов: картинка art/creatures/boss_<id>.png (пока нет — удильщик), множитель силы.
const BOSSES := [
	{"id": "angler", "name": "Giant Anglerfish", "hp": 1.0},
	{"id": "squid", "name": "Kraken", "hp": 1.25},
	{"id": "serpent", "name": "Sea Serpent", "hp": 1.4},
	{"id": "crab", "name": "Titan Crab", "hp": 1.6},
]
const BOSS_TIME := 150.0
const BOSS_ATTACK := 18.0
var boss := {}
var boss_timer := 5400.0

func boss_tier() -> int:
	return colonists.size() / 10 + colony_level / 5

func start_boss() -> void:
	if not boss.is_empty():
		return
	var tier := boss_tier()
	# чем сильнее колония, тем страшнее гость
	var kind := clampi(rng.randi_range(0, mini(3, tier / 2)), 0, BOSSES.size() - 1)
	var hp := (400.0 + 220.0 * tier) * float(BOSSES[kind].hp)
	boss = {"hp": hp, "max": hp, "until": now() + BOSS_TIME, "attack": BOSS_ATTACK, "tier": tier, "kind": kind}
	banner.emit("leviathan", tr("%s approaches!") % tr(BOSSES[kind].name), tr("Tap the monster to fight it off. Every colonist helps!"))
	event.emit("breach")
	changed.emit()

## Урон от нажатия: растёт с уровнем колонии.
func boss_tap_damage() -> int:
	return int((4 + colony_level / 2) * (1.25 if has_pet("puffer") else 1.0))

func hit_boss() -> int:
	if boss.is_empty():
		return 0
	var d := boss_tap_damage()
	boss.hp = float(boss.hp) - d
	if boss.hp <= 0.0:
		_end_boss(true)
	return d

func _tick_boss(delta: float) -> void:
	if boss.is_empty():
		if colonists.size() >= BOSS_MIN_POP and raid.is_empty():
			boss_timer -= delta
			if boss_timer <= 0.0:
				boss_timer = rng.randf_range(7200.0, 12600.0)
				start_boss()
		return
	# колонисты бьют сами: чем сильнее колония, тем быстрее
	var dps := 0.0
	for c in colonists:
		if not c.get("child", false) and c.room != ON_EXPEDITION:
			dps += fight_power(c) * 0.04
	boss.hp = float(boss.hp) - dps * armory_bonus() * delta
	if boss.hp <= 0.0:
		_end_boss(true)
		return
	boss.attack = float(boss.attack) - delta
	if boss.attack <= 0.0:
		boss.attack = BOSS_ATTACK
		var cand := rooms.filter(func(r): return can_have_hazard(r) and r.incident <= 0.0)
		if not cand.is_empty():
			start_hazard(cand.pick_random(), "creature", 60.0)
	if now() > float(boss.until):
		_end_boss(false)

func _end_boss(won: bool) -> void:
	var tier: int = boss.get("tier", 0) + int(boss.get("kind", 0))
	var bname: String = tr(BOSSES[int(boss.get("kind", 0))].name)
	boss = {}
	if won:
		var r := {"pearls": 300 + 120 * tier, "crystals": 6 + tier}
		if rng.randf() < 0.35:
			r["item"] = "legendary" if rng.randf() < 0.2 else "rare"
		if rng.randf() < 0.25:
			r["crates"] = {"silver": 1}
		track("boss_won")
		add_colony_xp(80)
		grant(r, tr("%s defeated!") % bname)
	else:
		banner.emit("leviathan", tr("%s swam away") % bname, tr("It will be back. Get stronger!"))
	changed.emit()

# ---------------------------------------------------------------- налёты пиратов
## Как рейдеры в Fallout: подлодка причаливает к шлюзу, пираты ломают дверь и идут
## из отсека в отсек. Где нет людей — воруют жемчуг и запасы и идут дальше;
## где есть — дерутся. Вне игры налётов не бывает.
const RAID_MIN_POP := 10
const RAID_STAY := 10.0
var raid := {}
var raid_timer := 900.0
## Тела побеждённых пиратов: лежат RAIDER_BODY_TIME секунд, нажатие — немного добычи.
const RAIDER_BODY_TIME := 600.0
var raider_bodies: Array = []

func raid_tier() -> int:
	return colonists.size() / 10 + max_row() / 4

func start_raid() -> void:
	var al := find_room_of_type("airlock")
	if al.is_empty() or not raid.is_empty() or al.incident > 0.0:
		return
	var tier := raid_tier()
	var n := clampi(2 + tier / 2, 2, 5)
	var raiders := []
	for i in n:
		var hp := 60.0 + 25.0 * tier
		raiders.append({"hp": hp, "max": hp, "kind": rng.randi_range(0, 2)})
	raid = {"raiders": raiders, "room": al.id, "door": 15.0 + 20.0 * al.level, "stay": 0.0,
		"visited": [al.id], "stolen": 0, "atk": 1.0 + 0.35 * tier, "start_n": n}
	al.hazard = "raid"
	al.incident = 100.0
	banner.emit("raid", tr("Pirate raid!"), tr("Pirates are breaking through the airlock door. Drag colonists there to fight!"))
	event.emit("incident")
	changed.emit()

## Обыскать тело пирата: немного жемчуга, иногда запасы, кристалл или простое снаряжение.
func loot_raider(body: Dictionary) -> Dictionary:
	if not body in raider_bodies:
		return {}
	raider_bodies.erase(body)
	var tier: int = body.get("tier", 0)
	var r := {"pearls": rng.randi_range(8, 20) * (1 + tier)}
	var roll := rng.randf()
	if roll < 0.04 + 0.02 * tier:
		r["item"] = "rare" if rng.randf() < 0.15 + 0.05 * tier else "common"
	elif roll < 0.18:
		r["crystals"] = rng.randi_range(1, 1 + tier / 2)
	elif roll < 0.45:
		r["resources"] = rng.randi_range(10, 20) * (1 + tier)
	if r.has("resources"):
		for k in ["energy", "oxygen", "food"]:
			resources[k] = minf(storage_cap(), resources[k] + r.resources)
	pearls += int(r.pearls)
	crystals += int(r.get("crystals", 0))
	if r.has("item"):
		var it := add_item(r.item)
		r["item_base"] = it.base
	track("loot_raider")
	event.emit("bubble")
	changed.emit()
	return r

func _expire_raider_bodies() -> void:
	var t := now()
	for b in raider_bodies.duplicate():
		if t > float(b.until) or get_room(int(b.room)).is_empty():
			raider_bodies.erase(b)

func raid_alive() -> Array:
	return raid.get("raiders", []).filter(func(x): return x.hp > 0.0)

## Сила колониста в бою: сила, выносливость, оружие (через stat) и здоровье.
func fight_power(c: Dictionary) -> float:
	return (stat(c, "str") + stat(c, "end") * 0.5 + 1.0 + weapon_power(c)) * (0.4 + 0.6 * c.health / 100.0)

func _tick_raid(delta: float) -> void:
	if not raider_bodies.is_empty():
		_expire_raider_bodies()
	if raid.is_empty():
		if colonists.size() >= RAID_MIN_POP:
			raid_timer -= delta
			if raid_timer <= 0.0:
				raid_timer = rng.randf_range(1200.0, 2100.0) * mode().incidents
				start_raid()
		return
	var room := get_room(int(raid.room))
	if room.is_empty():
		_end_raid(false)
		return
	var alive := raid_alive()
	var crew := responders(room)
	# бой: люди бьют первого пирата, пираты — случайного из людей
	if not crew.is_empty():
		var dps := 0.0
		for c in crew:
			dps += fight_power(c)
		dps *= 0.45 * armory_bonus()
		var dmg_left := dps * delta
		for rd in alive:
			if dmg_left <= 0.0:
				break
			var take := minf(rd.hp, dmg_left)
			rd.hp -= take
			dmg_left -= take
			if rd.hp <= 0.0:
				raider_bodies.append({"room": room.id, "x": rng.randf_range(0.4, 0.9), "kind": rd.kind,
					"tier": raid_tier(), "until": now() + RAIDER_BODY_TIME, "id": next_id})
				next_id += 1
		alive = raid_alive()
		if alive.is_empty():
			_end_raid(true)
			return
		var victim: Dictionary = crew.pick_random()
		victim.health = maxf(health_floor(), victim.health - float(raid.atk) * alive.size() * delta * (1.0 - protection(victim)) * mode().damage)
		raid.stay = 0.0
	elif raid.door > 0.0:
		pass
	else:
		# никого — воруют и идут дальше
		var steal := mini(pearls, int(ceil(2.0 * alive.size() * delta)))
		pearls -= steal
		raid.stolen = int(raid.stolen) + steal
		for k in ["energy", "oxygen", "food"]:
			resources[k] = maxf(0.0, resources[k] - 0.6 * alive.size() * delta)
		raid.stay = float(raid.stay) + delta
		if raid.stay >= RAID_STAY:
			raid.stay = 0.0
			_raid_move(room)
			return
	if raid.door > 0.0:
		raid.door = maxf(0.0, float(raid.door) - delta * (0.5 + 0.25 * alive.size()))
		if raid.door <= 0.0:
			message.emit(tr("The pirates broke through the door!"))
	_update_raid_bar()

func _update_raid_bar() -> void:
	var room := get_room(int(raid.room))
	var tot := 0.0
	var mx := 0.0
	for rd in raid.raiders:
		tot += maxf(0.0, rd.hp)
		mx += rd.max
	room.incident = maxf(1.0, 100.0 * tot / maxf(1.0, mx))

## Соседи для прохода пиратов: слева/справа на этаже, лифт — вверх/вниз.
func _raid_neighbors(r: Dictionary) -> Array:
	var out := []
	for n in [room_at(r.col - 1, r.row), room_at(r.col + room_w(r), r.row)]:
		if not n.is_empty():
			out.append(n)
	if r.type == "elevator":
		for dr in [-1, 1]:
			var n := room_at(r.col, r.row + dr)
			if not n.is_empty() and n.type == "elevator":
				out.append(n)
	return out

func _raid_move(from: Dictionary) -> void:
	# ближайший ещё не ограбленный отсек — поиском в ширину
	var prev := {from.id: -1}
	var queue := [from]
	var goal := {}
	while not queue.is_empty():
		var cur: Dictionary = queue.pop_front()
		if not cur.id in raid.visited and cur.type != "elevator":
			goal = cur
			break
		for n in _raid_neighbors(cur):
			# через отсеки, где пожар или потоп, пираты не идут
			if not prev.has(n.id) and n.incident <= 0.0:
				prev[n.id] = cur.id
				queue.append(n)
	if goal.is_empty():
		_end_raid(false)
		return
	# шаг к цели: первый отсек на пути
	var step: int = goal.id
	while prev.get(step, -1) != from.id and prev.get(step, -1) != -1:
		step = prev[step]
	var next := get_room(step)
	from.hazard = ""
	from.incident = 0.0
	for c in colonists:
		if c.help == from.id:
			c.help = -1
	_raid_move_into(next)

func _raid_move_into(next: Dictionary) -> void:
	raid.room = next.id
	if not next.id in raid.visited:
		raid.visited.append(next.id)
	next.hazard = "raid"
	_update_raid_bar()
	if next.type != "elevator":
		message.emit(tr(HAZARDS.raid.msg) % tr(Defs.ROOMS[next.type].name))
	changed.emit()

func _end_raid(won: bool) -> void:
	var room := get_room(int(raid.get("room", -1)))
	var crew := responders(room) if not room.is_empty() else []
	if not room.is_empty():
		room.hazard = ""
		room.incident = 0.0
	for c in colonists:
		if not room.is_empty() and c.help == room.id:
			c.help = -1
	var stolen: int = raid.get("stolen", 0)
	var n: int = raid.get("start_n", 2)
	raid = {}
	if won:
		var reward := int((stolen + 40 * n) * mode().reward)
		var r := {"pearls": reward}
		if rng.randf() < 0.25:
			r["item"] = "rare" if rng.randf() < 0.3 else "common"
		for c in crew:
			c.xp += 30.0
		track("raid_won")
		track("incident_resolved")
		grant(r, tr("Raid repelled!"))
	else:
		banner.emit("raid", tr("The pirates got away"), tr("They escaped with %d pearls.") % stolen)
	changed.emit()
var incident_timer := 200.0
## Кто нападает на отсеки (картинки — art/creatures/boss_<id>.png в уменьшенном виде).
const CREATURE_NAMES := {"angler": "Anglerfish", "crab": "Giant Crab", "squid": "Giant Squid", "serpent": "Sea Serpent"}
## Без людей: сколько секунд беда разгорается, как быстро потом гаснет и как часто перекидывается.
const BURN_PEAK := 40.0
const BURN_OUT_RATE := 0.6
const SPREAD_UNATTENDED := 30.0
const BURNED_MSG := {
	"fire": "The fire in %s burned out. Supplies were lost.",
	"flood": "The water in %s drained away. Supplies were lost.",
	"creature": "The creature left %s. Supplies were lost.",
}

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
var colony_lost := false
signal lost
var mode_chosen := true

func can_have_hazard(room: Dictionary) -> bool:
	return not room.is_empty() and room.type != "elevator" and room.type != "airlock"

func start_hazard(room: Dictionary, kind: String, hp := 100.0) -> void:
	if not can_have_hazard(room) or room.incident > 0.0:
		return
	room.hazard = kind
	room.incident = hp
	room.spread = 0.0
	room["burn"] = 0.0
	if kind == "creature":
		# кто именно напал: чем глубже, тем страшнее
		var pool := ["angler", "crab"] if room.row < 5 else (["angler", "crab", "squid"] if room.row < 10 else ["squid", "serpent", "crab"])
		room["creature"] = pool.pick_random()
		message.emit(tr("%s attacks the %s!") % [tr(CREATURE_NAMES[room.creature]), tr(Defs.ROOMS[room.type].name)])
	else:
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
	return colonists.filter(func(c): return (c.room == room.id or c.help == room.id) and c.room != ON_EXPEDITION and not c.get("child", false))

func hazard_power(room: Dictionary) -> float:
	var p := 0.0
	for c in responders(room):
		# с чудовищем помогает оружие
		var wp := weapon_power(c) if room.hazard == "creature" else 0.0
		p += ((stat(c, "str") + stat(c, "tech") + stat(c, "bio")) / 3.0 + wp) * (0.4 + 0.6 * c.health / 100.0)
	return p * armory_bonus()

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
			# как в Fallout: без людей беда разгорается, перекидывается на соседей,
			# а в самом отсеке со временем выгорает сама (но без награды)
			r["burn"] = float(r.get("burn", 0.0)) + delta
			if r.burn < BURN_PEAK:
				r.incident = minf(100.0, r.incident + 2.5 * delta)
			else:
				r.incident -= BURN_OUT_RATE * delta
				if r.incident <= 0.0:
					_resolve_hazard(r, offline, true)
					return
			r.spread += delta
			if r.spread > SPREAD_UNATTENDED and r.incident > 60.0:
				r.spread = 0.0
				_spread_hazard(r)
			return
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
	var w := room_w(r)
	var near := []
	var cand := [room_at(r.col - 1, r.row), room_at(r.col + w, r.row)]
	# и на этаж выше/ниже — по всей ширине отсека
	for dc in w:
		cand.append(room_at(r.col + dc, r.row - 1))
		cand.append(room_at(r.col + dc, r.row + 1))
	for n in cand:
		if can_have_hazard(n) and n.incident <= 0.0 and not n in near:
			near.append(n)
	if near.is_empty():
		return
	var target: Dictionary = near.pick_random()
	start_hazard(target, r.hazard, 50.0)
	message.emit(tr("Incident spread to %s!") % tr(Defs.ROOMS[target.type].name))

func _resolve_hazard(r: Dictionary, offline: bool, burned := false) -> void:
	var crew := responders(r)
	var kind: String = r.hazard
	r.incident = 0.0
	r.hazard = ""
	for c in colonists:
		if c.help == r.id:
			c.help = -1
	if offline:
		return
	if burned:
		# выгорело само: запасы пострадали, а отсек сломан — работает вдвое медленнее до ремонта
		for k in ["energy", "oxygen", "food"]:
			resources[k] = maxf(0.0, resources[k] - 10.0)
		r["damaged"] = true
		message.emit(tr(BURNED_MSG.get(kind, "%s: the danger has passed.")) % tr(Defs.ROOMS[r.type].name))
		changed.emit()
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

## Исследование, которое откроет ближайшую закрытую зону глубины ("" — все открыты).
func next_depth_research() -> String:
	for z in Defs.DEPTH_ZONES:
		if z.research != "" and not has_research(z.research):
			return z.research
	return ""

## Цепочка исследований до цели: сначала то, что можно начать уже сейчас.
func research_path(id: String) -> Array:
	var out := []
	var stack := [id]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		if has_research(cur) or cur in out:
			continue
		out.append(cur)
		for rq in research_def(cur).req:
			stack.append(rq)
	return out

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
	track("research")
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
		if c.suit_item == uid or c.tool_item == uid or c.get("armor_item", -1) == uid or c.get("weapon_item", -1) == uid:
			return c
	return {}

## Навык с учётом снаряжения.
func stat(c: Dictionary, k: String) -> int:
	var v: int = c.get(k, 1)
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
	var p := stat(c, "end") * 0.02
	var uid: int = c.get("armor_item", -1)
	if uid != -1:
		var it := get_item(uid)
		if not it.is_empty():
			p += ARMOR_PROTECTION[it.rarity] + float(item_base(it).get("prot", 0.0))
	return minf(0.8, p)

const WEAPON_RARITY := {"common": 1.0, "rare": 1.6, "legendary": 2.5}

## Сила оружия колониста (0 — без оружия, дерётся кулаками).
func weapon_power(c: Dictionary) -> float:
	var uid: int = c.get("weapon_item", -1)
	if uid == -1:
		return 0.0
	var it := get_item(uid)
	if it.is_empty():
		return 0.0
	return float(item_base(it).get("atk", 0)) * WEAPON_RARITY[it.rarity]

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
	track("bubble")
	if rich:
		var cr := rng.randi_range(1, 2)
		crystals += cr
		changed.emit()
		return {"text": "[crystals]+%d" % cr, "color": Defs.RESOURCES.crystals.color}
	var p := rng.randi_range(8, 20) + max_row() * 2
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

## Цена предложения с учётом скидки за обаяние (скидка только на жемчуг и кристаллы).
func trade_price(o: Dictionary, k: String) -> int:
	var v: int = int(o.give[k])
	if k in ["pearls", "crystals"]:
		return maxi(1, int(round(v * (1.0 - trade_discount()))))
	return v

func can_trade(idx: int) -> bool:
	if trader.is_empty() or idx in trader.bought:
		return false
	var o: Dictionary = trader.offers[idx]
	for k in o.give:
		var have: float = pearls if k == "pearls" else (crystals if k == "crystals" else resources.get(k, 0.0))
		if have < trade_price(o, k):
			return false
	return true

func trade(idx: int) -> bool:
	if trader.is_empty() or idx in trader.bought:
		return false
	var o: Dictionary = trader.offers[idx]
	for k in o.give:
		var have: float = pearls if k == "pearls" else (crystals if k == "crystals" else resources.get(k, 0.0))
		if have < trade_price(o, k):
			message.emit(tr("Not enough resources"))
			event.emit("error")
			return false
	for k in o.give:
		if k == "pearls":
			pearls -= trade_price(o, k)
		elif k == "crystals":
			crystals -= trade_price(o, k)
		else:
			resources[k] -= o.give[k]
	trader.bought.append(idx)
	track("trade")
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
		# только выполнимые задания: для «экспедиций» нужен док, для «крафта» — мастерская и т. д.
		var pool: Array = Defs.QUEST_POOL.filter(func(q): return not q.has("needs") or count_of(q.needs) > 0)
		pool.shuffle()
		# цели растут вместе с колонией
		var scale := 1.0 + colonists.size() / 15.0
		for i in mini(Defs.QUESTS_PER_DAY, pool.size()):
			var q: Dictionary = pool[i]
			var target := rng.randi_range(q.target[0], q.target[1])
			if q.get("scales", false):
				target = int(target * scale)
			quests.append({
				"event": q.event, "text": q.text, "target": target,
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

func colony_xp_needed() -> int:
	return int(120 * pow(colony_level, 1.4))

func add_colony_xp(x: int) -> void:
	colony_xp += x
	while colony_xp >= colony_xp_needed():
		colony_xp -= colony_xp_needed()
		colony_level += 1
		var r := {"pearls": 20 + 10 * colony_level}
		if colony_level % 5 == 0:
			r["crystals"] = 3
		if colony_level % 10 == 0:
			r["crates"] = {"common": 1}
		colony_level_up.emit(colony_level)
		grant(r, tr("Colony level %d!") % colony_level)

## +10% за каждый следующий сбор подряд, максимум +50% — заметно, но экономику не ломает.
func combo_mult() -> float:
	return 1.0 + 0.1 * minf(5.0, float(maxi(0, combo - 1)))

func track(ev: String, amount := 1) -> void:
	event.emit(ev)
	if COLONY_XP.has(ev):
		add_colony_xp(COLONY_XP[ev])
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
			"crystals": crystals, "crates": crates, "premium": premium, "no_ads": no_ads, "pet": pet, "pets_owned": pets_owned, "owned": owned_products,
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
			"fallen": fallen, "colony_level": colony_level, "colony_xp": colony_xp,
			"ads_day": ads_day, "ads_count": ads_count, "pearl_buys": pearl_buys, "pearl_buys_day": pearl_buys_day,
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
	fallen = data.get("meta", {}).get("fallen", [])
	colony_level = int(data.get("meta", {}).get("colony_level", 1))
	colony_xp = int(data.get("meta", {}).get("colony_xp", 0))
	ads_day = int(data.get("meta", {}).get("ads_day", -1))
	ads_count = int(data.get("meta", {}).get("ads_count", 0))
	pearl_buys = data.get("meta", {}).get("pearl_buys", {})
	pearl_buys_day = int(data.get("meta", {}).get("pearl_buys_day", -1))
	# налёт и босс не сохраняются: после перезапуска их уже нет
	raid = {}
	boss = {}
	for r in rooms:
		if r.get("hazard", "") == "raid":
			r.hazard = ""
			r.incident = 0.0
	for fl in fallen:
		fl.room = int(fl.room)
		for k in ["id", "str", "tech", "bio", "end", "cha", "luck", "level", "suit"]:
			if fl.c.has(k):
				fl.c[k] = int(fl.c[k])
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
	pets_owned = meta.get("pets_owned", [])
	if pet != "" and not pet in pets_owned:
		pets_owned.append(pet)
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
		c["weapon_item"] = c.get("weapon_item", -1)
		for k in ["end", "cha", "luck"]:
			if not c.has(k):
				c[k] = rng.randi_range(1, 4)
		c["mood"] = float(c.get("mood", 70.0))
		c["train"] = float(c.get("train", 0.0))
		if c.has("grow"):
			c.grow = float(c.grow)
		for k in ["id", "str", "tech", "bio", "end", "cha", "luck", "level", "room", "suit", "help", "suit_item", "tool_item", "armor_item", "weapon_item"]:
			c[k] = int(c[k])
	_fix_orphans()
	_apply_offline(Time.get_unix_time_from_system() - float(data.time))
	return true

## Как в Fallout: пока игрока нет, отсеки делают цикл и ждут сбора (нажатия),
## а колонисты тратят заметно меньше и запасы не уходят в ноль.
const OFFLINE_CONSUME := 0.25
## Ниже этой доли от запаса на момент выхода ресурс вне игры не опускается.
const OFFLINE_KEEP := 0.35
const OFFLINE_FLOOR := 10.0
const OFFLINE_STEP := 10.0

func _apply_offline(elapsed: float) -> void:
	# пока игрока нет, таймеры павших и тел пиратов стоят на паузе
	var away := maxf(0.0, elapsed)
	for f in fallen:
		f.until = float(f.until) + away
	for b in raider_bodies:
		b.until = float(b.until) + away
	elapsed = clampf(elapsed, 0.0, MAX_OFFLINE_PREMIUM if premium else MAX_OFFLINE)
	if elapsed < 30.0:
		return
	var before := colonists.size()
	var start_res := resources.duplicate()
	# шагами по 10 с: точности хватает, а вход после долгого перерыва не тормозит
	var steps := int(elapsed / OFFLINE_STEP)
	for i in steps:
		simulate(OFFLINE_STEP, true)
		# совсем в ноль за время отсутствия не уходим
		for k in ["energy", "oxygen", "food"]:
			var keep := maxf(float(start_res[k]) * OFFLINE_KEEP, minf(OFFLINE_FLOOR, float(start_res[k])))
			if resources[k] < keep:
				resources[k] = keep
	var parts := []
	for k in ["energy", "oxygen", "food"]:
		var d := int(resources[k] - start_res[k])
		parts.append("%s %s%d" % [tr(Defs.RESOURCES[k].name), "+" if d >= 0 else "", d])
	var ready := rooms.filter(func(r): return r.ready).size()
	var text := tr("While you were away (%s): %s") % [_fmt_time(elapsed), ", ".join(parts)]
	if ready > 0:
		text += ". " + tr("%d rooms are ready, tap them to collect!") % ready
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
	return 0.0 if mode().get("death", mode().permadeath) else 10.0

## Павшие колонисты: тело лежит в отсеке, где погиб. Пока не вышло время,
## его можно оживить за жемчуг (дороже с уровнем), потом — потерян навсегда.
var fallen: Array = []

func _check_deaths() -> void:
	if not mode().get("death", mode().permadeath):
		return
	for c in colonists.duplicate():
		if c.health <= 0.0 and c.room != ON_EXPEDITION:
			var where: int = c.get("died_in", -1)
			if where == -1:
				where = c.help if c.get("help", -1) != -1 else c.room
			c.erase("died_in")
			colonists.erase(c)
			c.room = -1
			c.help = -1
			c.health = 0.0
			fallen.append({"c": c, "room": where, "until": now() + float(mode().revive_window)})
			stats["deaths"] = stats.get("deaths", 0) + 1
			banner.emit("suit_%d" % c.suit, tr("Colonist lost"), tr("%s has died. Revive within %s for %d pearls.") % [c.name, (tr("%d h") % int(float(mode().revive_window) / 3600.0) if float(mode().revive_window) >= 3600.0 else tr("%d min") % int(float(mode().revive_window) / 60.0)), revive_cost(fallen[-1])])
			event.emit("breach")
			changed.emit()
	_expire_fallen()
	if colonists.is_empty() and not colony_lost and (fallen.is_empty() or pearls < _cheapest_revive()):
		colony_lost = true
		lost.emit()

func _expire_fallen() -> void:
	for f in fallen.duplicate():
		if now() > float(f.until):
			fallen.erase(f)
			banner.emit("suit_%d" % f.c.suit, tr("Gone forever"), tr("%s could not be saved.") % f.c.name)
			changed.emit()

func revive_cost(f: Dictionary) -> int:
	return int((100 + 60 * (int(f.c.level) - 1)) * float(mode().get("revive_mult", 1.0)))

func _cheapest_revive() -> int:
	var m := 1 << 30
	for f in fallen:
		m = mini(m, revive_cost(f))
	return m

func revive(f: Dictionary) -> bool:
	if not f in fallen:
		return false
	var cost := revive_cost(f)
	if pearls < cost:
		message.emit(tr("Not enough pearls"))
		event.emit("error")
		return false
	pearls -= cost
	track("revive")
	fallen.erase(f)
	var c: Dictionary = f.c
	c.health = 40.0
	c.room = -1
	colonists.append(c)
	colony_lost = false
	banner.emit("suit_%d" % c.suit, tr("Revived!"), tr("%s is back on their feet.") % c.name)
	event.emit("level_up")
	changed.emit()
	return true

func bury(f: Dictionary) -> void:
	fallen.erase(f)
	changed.emit()

## Колонисты, чей отсек исчез, возвращаются в шлюз.
func _fix_orphans() -> void:
	for c in colonists:
		if c.room >= 0 and get_room(c.room).is_empty():
			c.room = -1
		if c.get("help", -1) >= 0 and get_room(c.help).is_empty():
			c.help = -1

func reset() -> void:
	colony_lost = false
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	new_game()

static func _fmt_time(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%dh %dm" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%dm" % (s / 60)
	return "%ds" % s

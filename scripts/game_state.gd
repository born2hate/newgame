extends Node
## Состояние колонии: ресурсы, комнаты, колонисты, симуляция и сохранения.

signal changed                          # что-то изменилось — перерисовать UI
signal message(text: String)            # всплывающее сообщение
signal floating_text(room_id: int, text: String, color: Color)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const ARRIVAL_INTERVAL := 75.0
const MAX_OFFLINE := 8.0 * 3600.0
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

func _ready() -> void:
	rng.randomize()
	if not load_game():
		new_game()

func _process(delta: float) -> void:
	simulate(delta, false)
	autosave_timer += delta
	if autosave_timer > 15.0:
		autosave_timer = 0.0
		save_game()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_game()

# ---------------------------------------------------------------- новая игра

func new_game() -> void:
	resources = {"energy": 60.0, "oxygen": 60.0, "food": 60.0}
	pearls = 300
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
				message.emit("Прибыл новый колонист: %s" % c.name)
			changed.emit()
	for k in resources:
		resources[k] = minf(resources[k], cap)

func _xp_needed(c: Dictionary) -> float:
	return 90.0 * c.level

func _level_up(c: Dictionary) -> void:
	c.xp = 0.0
	c.level += 1
	var room := get_room(c.room)
	var stat: String = Defs.ROOMS[room.type].get("stat", "") if not room.is_empty() else ""
	if stat == "":
		stat = ["str", "tech", "bio"].pick_random()
	c[stat] = mini(10, c[stat] + 1)
	pearls += 15
	message.emit("%s — уровень %d! %s +1" % [c.name, c.level, Defs.STATS[stat]])
	changed.emit()

func seconds_until_arrival() -> float:
	if colonists.size() >= population_cap():
		return -1.0
	return ARRIVAL_INTERVAL - arrival_timer

# ---------------------------------------------------------------- действия

func build(type: String, col: int, row: int) -> bool:
	var cost := build_cost(type)
	if pearls < cost:
		message.emit("Не хватает жемчуга")
		return false
	if not can_build_at(type, col, row):
		return false
	pearls -= cost
	var r := _add_room(type, col, row)
	floating_text.emit(r.id, "-%d Ж" % cost, Defs.RESOURCES.pearls.color)
	changed.emit()
	return true

func upgrade(room: Dictionary) -> void:
	if room.level >= Defs.MAX_LEVEL:
		return
	var cost := Defs.upgrade_cost(room.type, room.level)
	if pearls < cost:
		message.emit("Не хватает жемчуга")
		return
	pearls -= cost
	room.level += 1
	message.emit("%s улучшен до уровня %d" % [Defs.ROOMS[room.type].name, room.level])
	changed.emit()

func collect(room: Dictionary) -> void:
	if not room.ready:
		return
	var def: Dictionary = Defs.ROOMS[room.type]
	var amount := production_amount(room)
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
		message.emit("В комнате никто не работает")
		return
	var chance := rush_chance(room)
	room.heat += 1.0
	if rng.randf() < chance:
		room.progress = 1.0
		room.ready = true
		pearls += 10
		floating_text.emit(room.id, "Успех! +10 Ж", Color(0.6, 1.0, 0.7))
	else:
		room.progress = 0.0
		room.incident = 12.0
		for c in workers_in(room):
			c.health = maxf(10.0, c.health - 25.0)
		var res: String = Defs.ROOMS[room.type].produces
		if resources.has(res):
			resources[res] = maxf(0.0, resources[res] - 15.0)
		floating_text.emit(room.id, "ПРОБОИНА!", Color(1.0, 0.3, 0.3))
		message.emit("Авария в отсеке «%s»! Ремонт 12 с" % Defs.ROOMS[room.type].name)
	changed.emit()

func assign(colonist: Dictionary, room: Dictionary) -> bool:
	if room.is_empty() or room.type == "airlock":
		colonist.room = -1
		changed.emit()
		return true
	var slots := Defs.room_slots(room.type, room.level)
	if slots == 0:
		message.emit("Здесь нельзя работать")
		return false
	if colonist.room == room.id:
		return true
	if workers_in(room).size() >= slots:
		message.emit("Все места заняты")
		return false
	colonist.room = room.id
	colonist.xp = 0.0
	changed.emit()
	return true

func auto_assign(colonist: Dictionary, room: Dictionary) -> void:
	if not room.is_empty():
		assign(colonist, room)

# ---------------------------------------------------------------- сохранения

func save_game() -> void:
	var data := {
		"version": SAVE_VERSION, "time": Time.get_unix_time_from_system(),
		"resources": resources, "pearls": pearls, "rooms": rooms,
		"colonists": colonists, "next_id": next_id, "arrival_timer": arrival_timer,
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
	elapsed = clampf(elapsed, 0.0, MAX_OFFLINE)
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
	var text := "Пока вас не было (%s): готово отсеков — %d" % [_fmt_time(elapsed), ready]
	if colonists.size() > before:
		text += ", новых колонистов — %d" % (colonists.size() - before)
	call_deferred("emit_signal", "message", text)

func reset() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	new_game()

static func _fmt_time(sec: float) -> String:
	var s := int(sec)
	if s >= 3600:
		return "%d ч %d мин" % [s / 3600, (s % 3600) / 60]
	if s >= 60:
		return "%d мин" % (s / 60)
	return "%d с" % s

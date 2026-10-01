class_name Art
extends RefCounted
## Подгрузка нарисованных ассетов из res://art/. Если файла нет — игра рисует
## процедурную заглушку, поэтому арт можно добавлять по одному файлу.

static var _cache := {}

static func tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_cache[path] = t
	return t

static func room(type: String) -> Texture2D:
	return tex("res://art/rooms/%s.png" % type)

## Картинка конкретного отсека: у некоторых на 3-м уровне своя (living_3.png).
static func room_of(r: Dictionary) -> Texture2D:
	if int(r.get("level", 1)) >= 3:
		var up := tex("res://art/rooms/%s_3.png" % r.type)
		if up:
			return up
	return room(r.type)

## Картинка колониста: у детей — свои (kid_0..2), у взрослых — костюм.
static func colonist(c: Dictionary) -> Texture2D:
	if c.get("child", false):
		var k := tex("res://art/characters/kid_%d.png" % (int(c.id) % 3))
		if k:
			return k
	return diver(int(c.suit))

static func icon(res: String) -> Texture2D:
	return tex("res://art/icons/%s.png" % res)

const CAPTAIN_SUIT := 6

## Стоячая поза: кадр 0 анимации ходьбы.
static func diver(suit: int) -> Texture2D:
	var t := walk(suit, 0)
	return t if t else tex("res://art/characters/diver.png")

## Сколько кадров шага (без стоячего кадра 0 у обычных костюмов).
static func walk_frames(suit: int) -> int:
	return 10 if suit == CAPTAIN_SUIT else 8

static func walk_frame(suit: int, t: float) -> Texture2D:
	var n := walk_frames(suit)
	var i := int(t) % n
	return walk(suit, i if suit == CAPTAIN_SUIT else i + 1)

## Иконка по ключу маркера: pearls, crystals, science, energy, oxygen, food,
## crate_<тип>, item_<предмет>, colonist, captain, pet.
static func marker_icon(key: String) -> Texture2D:
	if key.begins_with("crate_"):
		return tex("res://art/ui/shop/%s.png" % key)
	if key.begins_with("item_"):
		return tex("res://art/items/%s.png" % key.trim_prefix("item_"))
	if key.begins_with("suit_"):
		return walk(int(key.trim_prefix("suit_")), 0)
	if key in ["tasks", "trophy_gold", "gift", "shop", "build", "crew"]:
		return tex("res://art/ui/icons/%s.png" % key)
	match key:
		"colonist": return walk(2, 0)
		"captain": return walk(CAPTAIN_SUIT, 0)
		"pet": return tex("res://art/creatures/clownfish.png")
		"trader": return tex("res://art/creatures/trader_sub.png")
		"raid":
			var ps := tex("res://art/creatures/pirate_sub.png")
			return ps if ps else tex("res://art/creatures/bathyscaphe.png")
	return icon(key)

## Разбирает «[ключ]текст» → [ключ, текст].
static func split_marker(s: String) -> Array:
	if s.begins_with("[") and s.find("]") > 0:
		var e := s.find("]")
		return [s.substr(1, e - 1), s.substr(e + 1)]
	return ["", s]

static func walk(suit: int, frame: int) -> Texture2D:
	return tex("res://art/characters/walk/walk_%d_%d.png" % [suit, frame])

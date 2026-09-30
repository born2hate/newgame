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

static func walk(suit: int, frame: int) -> Texture2D:
	return tex("res://art/characters/walk/walk_%d_%d.png" % [suit, frame])

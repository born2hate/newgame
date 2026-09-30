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

static func diver(suit: int) -> Texture2D:
	var t := tex("res://art/characters/diver_%d.png" % suit)
	return t if t else tex("res://art/characters/diver.png")

static func walk(suit: int, frame: int) -> Texture2D:
	return tex("res://art/characters/walk/walk_%d_%d.png" % [suit, frame])

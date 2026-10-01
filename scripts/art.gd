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
static func colonist(c: Dictionary, resting := false) -> Texture2D:
	if c.get("child", false):
		var k := tex("res://art/characters/kid_%d.png" % (int(c.id) % 3))
		if k:
			return k
	if resting:
		var r := rest(int(c.suit))
		if r:
			return r
	return diver(int(c.suit))

## Без шлема, в комбинезоне — для отдыха (жилой отсек, бар, обзорная палуба).
static func rest(suit: int) -> Texture2D:
	return tex("res://art/characters/rest/rest_%d.png" % suit)

## Картинка питомца: своя pet_<id>.png, если нарисована, иначе рыба из аквариума.
static func pet(id: String) -> Texture2D:
	var own := tex("res://art/creatures/pet_%s.png" % id)
	if own:
		return own
	return tex(Defs.PETS[id].art) if Defs.PETS.has(id) else null

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
## Иконка материала: картинка art/materials/<id>.png, а пока её нет — нарисованный самоцвет.
static func material(id: String) -> Texture2D:
	var t := tex("res://art/materials/%s.png" % id)
	if t:
		return t
	var key := "gen_mat_" + id
	if _cache.has(key):
		return _cache[key]
	var col: Color = Defs.MATERIALS.get(id, {}).get("color", Color.WHITE)
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var p := Vector2(x - 32, y - 34) / 26.0
			# огранённый камень: ромб с бликом и тенью
			var d := absf(p.x) * 0.9 + absf(p.y)
			if d < 1.0:
				var shade := 1.0 - 0.45 * clampf(p.y + 0.3 * p.x, -1.0, 1.0)
				var c := col * shade
				if p.x < -0.1 and p.y < -0.1 and d < 0.55:
					c = c.lerp(Color.WHITE, 0.45)
				c.a = clampf((1.0 - d) * 12.0, 0.0, 1.0)
				img.set_pixel(x, y, c)
			elif d < 1.08:
				img.set_pixel(x, y, Color(0.05, 0.06, 0.1, 0.9))
	var it := ImageTexture.create_from_image(img)
	_cache[key] = it
	return it

## Чертёж: картинка art/ui/blueprint.png или нарисованный синий лист.
static func blueprint() -> Texture2D:
	var t := tex("res://art/ui/blueprint.png")
	if t:
		return t
	if _cache.has("gen_blueprint"):
		return _cache["gen_blueprint"]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			if x >= 8 and x < 56 and y >= 6 and y < 58:
				var c := Color(0.12, 0.35, 0.75)
				if (x - 8) % 8 == 0 or (y - 6) % 8 == 0:
					c = Color(0.35, 0.6, 0.95)
				if (x > 18 and x < 46 and (y == 20 or y == 40)) or (y > 20 and y < 40 and (x == 19 or x == 45)):
					c = Color(0.95, 0.97, 1.0)
				img.set_pixel(x, y, c)
	var it := ImageTexture.create_from_image(img)
	_cache["gen_blueprint"] = it
	return it

static func marker_icon(key: String) -> Texture2D:
	if key.begins_with("mat_"):
		return material(key.trim_prefix("mat_"))
	if key == "blueprint":
		return blueprint()
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
		"pet":
			var gs = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Game")
			var pid: String = str(gs.pet) if gs and str(gs.pet) != "" else "clownfish"
			return pet(pid)
		"trader": return tex("res://art/creatures/trader_sub.png")
		"leviathan": return tex("res://art/creatures/boss_angler.png")
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

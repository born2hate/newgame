extends Node
## Звук и музыка: эффекты по событиям игры, фоновая музыка и шум океана, настройки.

const SETTINGS_PATH := "user://settings.cfg"
## Доступные языки: код → название на самом языке.
const LANGUAGES := {
	"en": "English", "ru": "Русский", "es": "Español", "pt_BR": "Português", "de": "Deutsch",
	"fr": "Français", "it": "Italiano", "tr": "Türkçe", "pl": "Polski", "id": "Bahasa Indonesia",
}
const POOL := 8

## Какой звук играть на событие игры (Game.event).
const EVENT_SFX := {
	"collect_energy": ["collect", 0.9], "collect_oxygen": ["collect", 1.1], "collect_food": ["collect", 1.0],
	"collect_pearls": ["pearls", 1.0], "build": ["build", 1.0], "upgrade": ["upgrade", 1.0],
	"level_up": ["levelup", 1.0], "crate": ["crate", 1.0], "breach": ["alarm", 1.0],
	"arrive": ["arrive", 1.0], "expedition": ["launch", 1.0], "rush": ["bubbles", 1.0],
	"error": ["error", 1.0], "incident": ["alarm", 0.9],
	"boss": ["roar", 1.0], "raid": ["horn", 1.0], "birth": ["birth", 1.0], "repair": ["repair", 1.0],
	"bubble": ["bubbles", 1.2], "stranger": ["arrive", 0.7], "loot_raider": ["pearls", 1.2], "boss_won": ["levelup", 0.8], "raid_won": ["levelup", 0.9],
}

var music_on := true
var sfx_on := true
var language := "en"
var streams := {}
var players: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var ambient: AudioStreamPlayer
## Тревожная тема плавно сменяет обычную, пока идёт налёт или бой с боссом.
var danger: AudioStreamPlayer
var _danger_mix := 0.0
var _next := 0
var _mute_until := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for code in LANGUAGES:
		if code != "en":
			TranslationServer.add_translation(load("res://i18n/%s.gd" % code).make())
	_load_settings()
	for f in DirAccess.get_files_at("res://audio/sfx"):
		if f.ends_with(".ogg") or f.ends_with(".ogg.import"):
			var n := f.get_basename().get_basename() if f.ends_with(".import") else f.get_basename()
			streams[n] = load("res://audio/sfx/%s.ogg" % n)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	music = _looped("res://audio/music/theme.ogg", -8.0)
	ambient = _looped("res://audio/music/ambient.ogg", -10.0)
	danger = _looped("res://audio/music/danger.ogg", -80.0)
	_apply()
	# при загрузке сохранения офлайн-события не озвучиваем
	_mute_until = Time.get_ticks_msec() + 1500
	Game.event.connect(_on_event)
	Game.rewards_granted.connect(func(_t, _l): play("reward"))
	Store.purchase_finished.connect(func(_id, ok): if ok: play("purchase"))

func _process(delta: float) -> void:
	if danger == null:
		return
	var want := 1.0 if (not Game.raid.is_empty() or not Game.boss.is_empty()) and music_on else 0.0
	_danger_mix = move_toward(_danger_mix, want, delta / 1.5)
	if _danger_mix > 0.0 and not danger.playing:
		danger.play()
	elif _danger_mix <= 0.0 and danger.playing:
		danger.stop()
	danger.volume_db = linear_to_db(maxf(0.0001, _danger_mix)) - 7.0
	if music:
		music.volume_db = -8.0 + linear_to_db(maxf(0.0001, 1.0 - _danger_mix))

## Комбо: каждый следующий сбор подряд звучит на полтона выше.
func play_combo(count: int) -> void:
	play("combo", pow(2.0, minf(count - 1, 12) / 12.0))

func _looped(path: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var s = load(path)
	if s is AudioStreamOggVorbis:
		s.loop = true
	p.stream = s
	p.volume_db = db
	add_child(p)
	return p

func play(name: String, pitch := 1.0, db := 0.0) -> void:
	if not sfx_on or not streams.has(name) or Time.get_ticks_msec() < _mute_until:
		return
	var p := players[_next]
	_next = (_next + 1) % POOL
	p.stream = streams[name]
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.volume_db = db
	p.play()

func _on_event(name: String) -> void:
	if EVENT_SFX.has(name):
		play(EVENT_SFX[name][0], EVENT_SFX[name][1])

func set_music(on: bool) -> void:
	music_on = on
	_apply()
	_save_settings()

func set_sfx(on: bool) -> void:
	sfx_on = on
	_apply()
	_save_settings()

## Для скриншотов: --force-lang=en перебивает любые переключения языка.
var forced_lang := ""

func set_language(code: String) -> void:
	if forced_lang != "":
		code = forced_lang
	language = code
	TranslationServer.set_locale(code)
	_save_settings()

func _apply() -> void:
	for p in [music, ambient]:
		if music_on and not p.playing:
			p.play()
		elif not music_on:
			p.stop()
	ambient.volume_db = -10.0 if sfx_on else -80.0

## Красивая графика (свечение, лучи, частицы). На слабых телефонах можно выключить.
var hq_graphics := true
signal graphics_changed

func set_hq_graphics(on: bool) -> void:
	hq_graphics = on
	_save_settings()
	graphics_changed.emit()

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_on = cfg.get_value("audio", "music", true)
		sfx_on = cfg.get_value("audio", "sfx", true)
		language = cfg.get_value("general", "language", "")
		hq_graphics = cfg.get_value("general", "hq_graphics", true)
	if language == "":
		# язык телефона, если он поддерживается
		var loc := OS.get_locale()
		language = "en"
		for code in LANGUAGES:
			if loc == code or loc.begins_with(code.split("_")[0]):
				language = code
	TranslationServer.set_locale(language)

func _save_settings() -> void:
	# сначала читаем файл: там же хранятся другие настройки (уведомления, графика)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("audio", "music", music_on)
	cfg.set_value("audio", "sfx", sfx_on)
	cfg.set_value("general", "language", language)
	cfg.set_value("general", "hq_graphics", hq_graphics)
	cfg.save(SETTINGS_PATH)

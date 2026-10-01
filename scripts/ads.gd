extends RefCounted
## Реклама за награду через AdMob (плагин poing-studios/godot-admob-plugin).
## Классы плагина ищем по имени во время работы, поэтому игра собирается и без него:
## если плагина нет, ready() == false и магазин работает в тестовом режиме.

## Тестовый блок Google; перед релизом заменить на свой из AdMob (Приложения → Блоки рекламы).
const REWARDED_UNIT_ANDROID := "ca-app-pub-3940256099942544/5224354917"

var _classes := {}
var _ad = null
var _loading := false
var _ok := false

func _cls(name: String):
	if _classes.has(name):
		return _classes[name]
	var c = null
	for g in ProjectSettings.get_global_class_list():
		if g["class"] == name:
			c = load(g["path"])
	_classes[name] = c
	return c

func available() -> bool:
	return _cls("MobileAds") != null and _cls("RewardedAdLoader") != null

func init() -> void:
	if not available():
		return
	_cls("MobileAds").initialize()
	_ok = true
	load_ad()

func ready() -> bool:
	return _ok and _ad != null

func load_ad() -> void:
	if not _ok or _loading or _ad != null:
		return
	_loading = true
	var cb = _cls("RewardedAdLoadCallback").new()
	cb.on_ad_loaded = func(ad):
		_ad = ad
		_loading = false
	cb.on_ad_failed_to_load = func(_err):
		_loading = false
	_cls("RewardedAdLoader").new().load(REWARDED_UNIT_ANDROID, _cls("AdRequest").new(), cb)

## Показать рекламу. on_reward — если досмотрел; on_close — когда реклама закрылась (в любом случае).
func show(on_reward: Callable, on_close: Callable) -> bool:
	if not ready():
		return false
	var ad = _ad
	_ad = null
	var fs = _cls("FullScreenContentCallback").new()
	fs.on_ad_dismissed_full_screen_content = func():
		on_close.call()
		ad.destroy()
		load_ad()
	fs.on_ad_failed_to_show_full_screen_content = func(_e):
		on_close.call()
		load_ad()
	ad.full_screen_content_callback = fs
	var listener = _cls("OnUserEarnedRewardListener").new()
	listener.on_user_earned_reward = func(_item): on_reward.call()
	ad.show(listener)
	return true

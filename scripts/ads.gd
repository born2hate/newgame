extends RefCounted
## Реклама за награду через AdMob (плагин poing-studios/godot-admob-plugin).
## Классы плагина ищем по имени во время работы, поэтому игра собирается и без него:
## если плагина нет, ready() == false и магазин работает в тестовом режиме.

## AdMob: приложение Deep Colony и блок рекламы за награду.
## App ID прописывается в настройках AdMob-плагина (AndroidManifest), здесь — для справки.
const APP_ID_ANDROID := "ca-app-pub-3660062326800102~1427937123"
const REWARDED_UNIT_ANDROID := "ca-app-pub-3660062326800102/6501134557"
## Тестовый блок Google: в отладочных сборках, чтобы не накручивать показы своей рекламы.
const REWARDED_UNIT_TEST := "ca-app-pub-3940256099942544/5224354917"

func unit_id() -> String:
	return REWARDED_UNIT_TEST if OS.is_debug_build() else REWARDED_UNIT_ANDROID

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
	# классы плагина есть и в редакторе, а нативная часть — только в Android-сборке
	return Engine.has_singleton("PoingGodotAdMob") and _cls("MobileAds") != null and _cls("RewardedAdLoader") != null

## Согласие на рекламу (GDPR, EEA/UK) через Google UMP: окно из AdMob → Privacy & messaging.
## Рекламу инициализируем после того, как игрок ответил (или окно не требуется).
func init() -> void:
	if not available():
		return
	var ump = _cls("UserMessagingPlatform")
	if ump == null or not Engine.has_singleton("PoingGodotAdMobConsentInformation"):
		_start_ads()
		return
	var params = _cls("ConsentRequestParameters").new()
	params.tag_for_under_age_of_consent = false
	ump.consent_information.update(params, func(): _show_consent_if_required(), func(_err): _start_ads())

func _show_consent_if_required() -> void:
	var ump = _cls("UserMessagingPlatform")
	var info = ump.consent_information
	# ConsentStatus: 2 — REQUIRED
	if info.get_consent_status() == 2 and info.get_is_consent_form_available():
		ump.load_consent_form(func(form): form.show(func(_err): _start_ads()), func(_err): _start_ads())
	else:
		_start_ads()

## Кнопка в настройках: изменить выбор по рекламе (нужна там, где окно согласия обязательно).
func privacy_options_available() -> bool:
	if not available():
		return false
	var ump = _cls("UserMessagingPlatform")
	# ConsentStatus: 1 — NOT_REQUIRED (вне EEA/UK кнопка не нужна)
	return ump != null and ump.consent_information.get_consent_status() > 1 \
		and ump.consent_information.get_is_consent_form_available()

func show_privacy_options() -> void:
	var ump = _cls("UserMessagingPlatform")
	if ump == null:
		return
	ump.load_consent_form(func(form): form.show(func(_err): pass), func(_err): pass)

func _start_ads() -> void:
	if _ok:
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
	_cls("RewardedAdLoader").new().load(unit_id(), _cls("AdRequest").new(), cb)

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

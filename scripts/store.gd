extends Node
## Магазин: товары за реальные деньги и за кристаллы, реклама за награду.
##
## Сейчас работает тестовый режим (DEV_MODE): покупка сразу выдаёт товар, реклама —
## заглушка на 2 секунды. Для релиза сюда подключаются плагины:
##  - Android: GodotGooglePlayBilling (Engine.has_singleton("GodotGooglePlayBilling"))
##  - iOS: InAppStore из godot-ios-plugins (Engine.has_singleton("InAppStore"))
##  - реклама: AdMob-плагин (poing-studios/godot-admob-plugin)

signal ad_started
signal ad_finished
signal purchase_finished(product_id: String, ok: bool)

const DEV_MODE := true

## Товары за реальные деньги. price — строка для показа; в релизе цену берём из стора.
const IAP := [
	{"id": "starter_pack", "title": "Starter Pack", "price": "$1.99", "one_time": true, "banner": "starter",
		"desc": "150 crystals, 1000 pearls, exclusive pet Nemo (+10% collections), 2 Silver Crates and a Rare colonist",
		"reward": {"crystals": 150, "pearls": 1000, "pet": "clownfish", "crates": {"silver": 2}, "colonist": "rare"}},
	{"id": "premium", "title": "Premium", "price": "$4.99", "one_time": true, "banner": "premium",
		"desc": "Golden Captain colonist, rewards without ads, 16h offline income, free crate every 2h, +100 crystals",
		"reward": {"premium": true, "crystals": 100}},
	{"id": "no_ads", "title": "No Ads", "price": "$2.99", "one_time": true,
		"desc": "Get every ad reward instantly, without watching videos. Forever.",
		"reward": {"no_ads": true}},
	{"id": "season_pass", "title": "Season Pass", "price": "$4.99", "banner": "season",
		"desc": "Unlock premium rewards on every season tier: crystals, gold crates and a Legendary colonist",
		"reward": {"season_pass": true}},
	# копилка: кристаллы копятся во время игры, разбить — за деньги (награда считается при покупке)
	{"id": "piggy_bank", "title": "Treasure Piggy Bank", "price": "$2.99", "banner": "piggy",
		"desc": "All the crystals saved up while you play.", "reward": {}},
	# наборы по поводу: появляются после события и действуют 24 часа
	{"id": "offer_hero", "title": "Hero Bundle", "price": "$4.99", "one_time": true,
		"desc": "Legendary Trident, 300 crystals and a Gold Crate. Next time the monster won't get away!",
		"reward": {"item": "legendary", "item_base": "trident", "crystals": 300, "crates": {"gold": 1}}},
	{"id": "offer_builder", "title": "Builder Bundle", "price": "$3.99", "one_time": true,
		"desc": "15,000 pearls, 30 scrap and 15 copper wire for the big builds ahead.",
		"reward": {"pearls": 15000, "materials": {"scrap": 30, "copper": 15}}},
	{"id": "offer_medic", "title": "Medic Bundle", "price": "$1.99", "one_time": true,
		"desc": "The healer pet Tang, 80 crystals and a Silver Crate. Keep everyone alive.",
		"reward": {"pet": "tang", "crystals": 80, "crates": {"silver": 1}}},
	{"id": "crystals_60", "title": "Handful of Crystals", "price": "$0.99", "reward": {"crystals": 60}, "pack": 0},
	{"id": "crystals_330", "title": "Pouch of Crystals", "price": "$4.99", "reward": {"crystals": 330}, "pack": 1},
	{"id": "crystals_700", "title": "Chest of Crystals", "price": "$9.99", "reward": {"crystals": 700}, "pack": 2},
	{"id": "crystals_1500", "title": "Big Chest", "price": "$19.99", "reward": {"crystals": 1500}, "pack": 3},
	{"id": "crystals_4000", "title": "Treasure Hoard", "price": "$49.99", "reward": {"crystals": 4000}, "pack": 4},
	{"id": "crystals_9000", "title": "Abyss Vault", "price": "$99.99", "reward": {"crystals": 9000}, "pack": 5},
]

## Товары за кристаллы.
const CRYSTAL_ITEMS := [
	{"id": "crate_silver", "title": "Silver Crate", "cost": 60, "reward": {"crates": {"silver": 1}}},
	{"id": "crate_gold", "title": "Gold Crate", "cost": 150, "reward": {"crates": {"gold": 1}}},
	{"id": "pearls_500", "title": "500 Pearls", "cost": 30, "reward": {"pearls": 500}},
	{"id": "pearls_2000", "title": "2000 Pearls", "cost": 100, "reward": {"pearls": 2000}},
]

var ad_playing := false

func product(id: String) -> Dictionary:
	for p in IAP:
		if p.id == id:
			return p
	return {}

func is_owned(id: String) -> bool:
	return id in Game.owned_products

func can_buy(id: String) -> bool:
	if id == "piggy_bank":
		return Game.piggy_can_break()
	if id.begins_with("offer_") and not Game.offer_active(id):
		return false
	if id == "season_pass":
		return not Game.season_pass
	if id == "no_ads" and Game.ads_removed():
		return false
	var p := product(id)
	return not p.is_empty() and not (p.get("one_time", false) and is_owned(id))

func purchase(id: String) -> void:
	if not can_buy(id):
		return
	if DEV_MODE:
		_deliver(id)
		return
	# TODO: вызвать биллинг стора; _deliver(id) — по подтверждению покупки.
	purchase_finished.emit(id, false)

func _deliver(id: String) -> void:
	var p := product(id)
	if p.get("one_time", false):
		Game.owned_products.append(id)
	var reward: Dictionary = p.reward
	if id == "piggy_bank":
		reward = {"crystals": Game.break_piggy()}
	if id.begins_with("offer_"):
		Game.close_offer(id)
	Game.grant(reward, tr(p.title))
	Game.save_game()
	purchase_finished.emit(id, true)

## Ящики за жемчуг — дорого, и каждая покупка за день поднимает цену на 50%.
const PEARL_ITEMS := [
	{"id": "pcrate_common", "title": "Supply Crate", "cost": 1500, "reward": {"crates": {"common": 1}}},
	{"id": "pcrate_silver", "title": "Silver Crate", "cost": 5000, "reward": {"crates": {"silver": 1}}},
]

func pearl_price(item: Dictionary) -> int:
	return int(item.cost * (1.0 + 0.5 * Game.pearl_buys_today(item.id)))

func buy_with_pearls(id: String) -> void:
	for item in PEARL_ITEMS:
		if item.id == id:
			var price := pearl_price(item)
			if Game.pearls < price:
				return
			Game.pearls -= price
			Game.note_pearl_buy(id)
			Game.grant(item.reward, tr(item.title))
			Game.save_game()

## Скидка дня: каждый день один товар за кристаллы дешевле на 40%.
func daily_deal_id() -> String:
	return CRYSTAL_ITEMS[Game.today() % CRYSTAL_ITEMS.size()].id

func crystal_price(item: Dictionary) -> int:
	return int(round(item.cost * 0.6)) if item.id == daily_deal_id() else int(item.cost)

func buy_with_crystals(id: String) -> void:
	for item in CRYSTAL_ITEMS:
		if item.id == id and Game.spend_crystals(crystal_price(item)):
			Game.grant(item.reward, tr(item.title))
			Game.save_game()

## Реклама за награду. С Premium награда выдаётся сразу, без показа рекламы.
func show_rewarded(on_reward: Callable) -> void:
	if ad_playing:
		return
	if Game.ads_left() <= 0:
		Game.message.emit(tr("No more videos today. Come back tomorrow!"))
		return
	Game.register_ad()
	if Game.ads_removed():
		on_reward.call()
		return
	ad_playing = true
	ad_started.emit()
	# TODO: показать rewarded-рекламу AdMob; награда — в колбэке on_user_earned_reward.
	await get_tree().create_timer(2.0).timeout
	ad_playing = false
	ad_finished.emit()
	on_reward.call()

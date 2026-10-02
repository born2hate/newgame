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

## Тестовый режим: включается сам, если в сборке нет плагина Google Play Billing.
## Тогда покупка сразу выдаёт товар, реклама — заглушка на 2 секунды.
var DEV_MODE := true

## Google Play Billing (плагин GodotGooglePlayBilling). Цены берём из стора.
var billing: Object = null
var store_prices := {}
## Расходуемые покупки (можно купить снова): после выдачи их «потребляем».
const CONSUMABLE := ["crystals_60", "crystals_330", "crystals_700", "crystals_1500", "crystals_4000", "crystals_9000", "piggy_bank", "season_pass", "event_pass"]

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
	# пропуск события: на текущую неделю, жетонов вдвое больше + золотой ящик сразу
	{"id": "event_pass", "title": "Event Pass", "price": "$2.99",
		"desc": "Double event tokens for this week (including the ones you already have) and a Gold Crate right now.",
		"reward": {"event_pass": true, "crates": {"gold": 1}}},
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

var ads := preload("res://scripts/ads.gd").new()

func _ready() -> void:
	ads.init()
	if Engine.has_singleton("GodotGooglePlayBilling"):
		billing = Engine.get_singleton("GodotGooglePlayBilling")
		DEV_MODE = false
		for pair in [["connected", _on_billing_connected], ["purchases_updated", _on_purchases_updated],
				["purchase_error", _on_purchase_error], ["query_product_details_response", _on_product_details],
				["product_details_query_completed", _on_product_details], ["sku_details_query_completed", _on_product_details],
				["query_purchases_response", _on_query_purchases]]:
			if billing.has_signal(pair[0]):
				billing.connect(pair[0], pair[1])
		if billing.has_method("startConnection"):
			billing.startConnection()

func _on_billing_connected() -> void:
	var ids: Array = IAP.map(func(p): return p.id)
	if billing.has_method("queryProductDetails"):
		billing.queryProductDetails(ids, "inapp")
	elif billing.has_method("querySkuDetails"):
		billing.querySkuDetails(ids, "inapp")
	# восстановить купленное раньше (Premium, без рекламы, наборы) — например, после переустановки
	if billing.has_method("queryPurchases"):
		var r = billing.queryPurchases("inapp")
		if typeof(r) == TYPE_DICTIONARY:
			_on_query_purchases(r)

## Цены из Google Play (в валюте игрока) вместо строк по умолчанию.
func _on_product_details(response) -> void:
	var list: Array = []
	if typeof(response) == TYPE_DICTIONARY:
		list = response.get("product_details", response.get("details", []))
	elif typeof(response) == TYPE_ARRAY:
		list = response
	for d in list:
		var pid: String = str(d.get("product_id", d.get("sku", d.get("id", ""))))
		var price: String = str(d.get("price", d.get("formatted_price", "")))
		if price == "" and d.has("one_time_purchase_offer_details"):
			price = str(d.one_time_purchase_offer_details.get("formatted_price", ""))
		if pid != "" and price != "":
			store_prices[pid] = price

func is_first_pack(id: String) -> bool:
	return not id in Game.packs_bought

func price_of(id: String) -> String:
	return str(store_prices.get(id, product(id).get("price", "")))

func _purchase_list(response) -> Array:
	if typeof(response) == TYPE_DICTIONARY:
		return response.get("purchases", [])
	if typeof(response) == TYPE_ARRAY:
		return response
	return []

func _on_purchases_updated(response) -> void:
	for pu in _purchase_list(response):
		_handle_purchase(pu)

func _on_query_purchases(response) -> void:
	for pu in _purchase_list(response):
		var ids: Array = pu.get("product_ids", [pu.get("product_id", pu.get("sku", ""))])
		for pid in ids:
			# незавершённые покупки и купленное раньше (не расходуемое)
			if not pu.get("is_acknowledged", false) or (not pid in CONSUMABLE and not is_owned(pid)):
				_handle_purchase(pu)
				break

## Покупка подтверждена: выдаём товар, затем потребляем или подтверждаем её в Google Play.
func _handle_purchase(pu: Dictionary) -> void:
	# 1 — PURCHASED (0 — ожидает оплаты, 2 — отложена)
	if int(pu.get("purchase_state", 1)) != 1:
		return
	var token: String = str(pu.get("purchase_token", ""))
	if token != "" and token in Game.purchase_tokens:
		return
	var ids: Array = pu.get("product_ids", [pu.get("product_id", pu.get("sku", ""))])
	for pid in ids:
		if product(pid).is_empty():
			continue
		if not (pid in CONSUMABLE) and is_owned(pid):
			continue
		_deliver(pid)
		if pid in CONSUMABLE:
			if billing.has_method("consumePurchase"):
				billing.consumePurchase(token)
		elif not pu.get("is_acknowledged", false) and billing.has_method("acknowledgePurchase"):
			billing.acknowledgePurchase(token)
	if token != "":
		Game.purchase_tokens.append(token)
		Game.save_game()

func _on_purchase_error(code = 0, message = "") -> void:
	Game.message.emit(tr("Purchase was not completed."))

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
	if id == "event_pass":
		return not Game.event_pass_active()
	if id == "no_ads" and Game.ads_removed():
		return false
	var p := product(id)
	return not p.is_empty() and not (p.get("one_time", false) and is_owned(id))

func purchase(id: String) -> void:
	if not can_buy(id):
		return
	if DEV_MODE or billing == null:
		_deliver(id)
		return
	# товар выдаётся в _handle_purchase, когда Google Play подтвердит оплату
	billing.purchase(id)

func _deliver(id: String) -> void:
	var p := product(id)
	if p.get("one_time", false):
		Game.owned_products.append(id)
	var reward: Dictionary = p.reward.duplicate(true)
	# первая покупка каждого пакета кристаллов — вдвое больше
	if p.has("pack") and is_first_pack(id):
		reward.crystals = int(reward.crystals) * 2
		Game.packs_bought.append(id)
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
	if ads.available() and not Game.ads_removed() and not ads.ready():
		ads.load_ad()
		Game.message.emit(tr("The video is not ready yet. Try again in a moment."))
		return
	Game.register_ad()
	if Game.ads_removed():
		on_reward.call()
		return
	if ads.available():
		# настоящая реклама AdMob
		ad_playing = true
		ad_started.emit()
		var got := [false]
		ads.show(func(): got[0] = true, func():
			ad_playing = false
			ad_finished.emit()
			if got[0]:
				on_reward.call())
		return
	# тестовый режим: заглушка на 2 секунды
	ad_playing = true
	ad_started.emit()
	await get_tree().create_timer(2.0).timeout
	ad_playing = false
	ad_finished.emit()
	on_reward.call()

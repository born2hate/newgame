class_name Defs
extends RefCounted
## Статические данные игры: типы комнат, ресурсы, имена колонистов.

const GRID_COLS := 8
const MAX_DEPTH := 14
const MAX_LEVEL := 3

const RESOURCES := {
	"energy": {"name": "Energy", "short": "E", "color": Color(1.0, 0.82, 0.3)},
	"oxygen": {"name": "Oxygen", "short": "O₂", "color": Color(0.35, 0.92, 1.0)},
	"food": {"name": "Food", "short": "F", "color": Color(0.5, 1.0, 0.55)},
	"pearls": {"name": "Pearls", "short": "P", "color": Color(1.0, 0.75, 0.95)},
	"crystals": {"name": "Crystals", "short": "C", "color": Color(0.55, 0.8, 1.0)},
}

const STATS := {
	"str": "Strength",
	"tech": "Tech",
	"bio": "Biology",
}

## width — ширина в клетках; slots — рабочих мест на 1 уровне;
## produces/stat/amount/cycle — производство; energy — расход энергии в секунду;
## unlock_pop — сколько колонистов нужно для открытия.
const ROOMS := {
	"airlock": {
		"name": "Airlock", "width": 2, "cost": 0, "buildable": false, "slots": 0,
		"energy": 0.0, "color": Color(0.35, 0.4, 0.5), "icon": "⇅",
		"desc": "Colony entrance. New colonists arrive here.",
	},
	"elevator": {
		"name": "Elevator", "width": 1, "cost": 40, "buildable": true, "slots": 0,
		"energy": 0.0, "color": Color(0.25, 0.3, 0.38), "icon": "↕", "unlock_pop": 0,
		"desc": "Connects levels. Build above or below another elevator.",
	},
	"living": {
		"name": "Living Quarters", "width": 2, "cost": 100, "buildable": true, "slots": 0,
		"capacity": 4, "energy": 0.05, "color": Color(0.75, 0.45, 0.9), "icon": "⌂",
		"unlock_pop": 0, "desc": "+4 colonist capacity per level.",
	},
	"reactor": {
		"name": "Reactor", "width": 2, "cost": 100, "buildable": true, "slots": 2,
		"produces": "energy", "stat": "str", "amount": 14.0, "cycle": 20.0,
		"energy": 0.0, "color": Color(1.0, 0.72, 0.2), "icon": "ϟ", "unlock_pop": 0,
		"desc": "Produces energy. Needs Strength.",
	},
	"oxygen": {
		"name": "O₂ Generator", "width": 2, "cost": 100, "buildable": true, "slots": 2,
		"produces": "oxygen", "stat": "tech", "amount": 12.0, "cycle": 20.0,
		"energy": 0.12, "color": Color(0.3, 0.85, 1.0), "icon": "○", "unlock_pop": 0,
		"desc": "Extracts oxygen from seawater. Needs Tech.",
	},
	"farm": {
		"name": "Algae Farm", "width": 2, "cost": 100, "buildable": true, "slots": 2,
		"produces": "food", "stat": "bio", "amount": 12.0, "cycle": 20.0,
		"energy": 0.12, "color": Color(0.4, 0.95, 0.45), "icon": "❦", "unlock_pop": 0,
		"desc": "Grows food. Needs Biology.",
	},
	"storage": {
		"name": "Storage", "width": 2, "cost": 150, "buildable": true, "slots": 0,
		"storage": 60.0, "energy": 0.05, "color": Color(0.6, 0.55, 0.45), "icon": "▦",
		"unlock_pop": 8, "desc": "+60 capacity for every resource per level.",
	},
	"pearl": {
		"name": "Pearl Farm", "width": 2, "cost": 250, "buildable": true, "slots": 2,
		"produces": "pearls", "stat": "bio", "amount": 25.0, "cycle": 45.0,
		"energy": 0.2, "color": Color(1.0, 0.6, 0.9), "icon": "◉", "unlock_pop": 10,
		"desc": "Grows pearls, the colony currency.",
	},
	"dock": {
		"name": "Sub Dock", "width": 2, "cost": 180, "buildable": true, "slots": 0,
		"energy": 0.1, "color": Color(1.0, 0.8, 0.3), "icon": "⚓", "unlock_pop": 5,
		"desc": "Home of a bathyscaphe. Send crews on expeditions for loot.",
	},
	"medbay": {
		"name": "Medbay", "width": 2, "cost": 200, "buildable": true, "slots": 2,
		"stat": "bio", "heal": true, "energy": 0.15, "color": Color(1.0, 0.4, 0.45),
		"icon": "✚", "unlock_pop": 12, "desc": "Heals all colonists. Needs Biology.",
	},
}

## Ящики припасов: rolls — сколько наград, table — [вес, вид, мин, макс].
## Шансы показываются игроку в магазине (требование Apple/Google).
const CRATES := {
	"common": {"name": "Supply Crate", "rolls": 2, "color": Color(0.55, 0.75, 0.9), "table": [
		[50, "pearls", 80, 200], [20, "resources", 40, 80], [15, "crystals", 3, 8],
		[12, "colonist_rare", 1, 1], [3, "colonist_legendary", 1, 1]]},
	"silver": {"name": "Silver Crate", "rolls": 3, "color": Color(0.85, 0.9, 1.0), "table": [
		[40, "pearls", 200, 450], [20, "resources", 80, 150], [18, "crystals", 8, 20],
		[17, "colonist_rare", 1, 1], [5, "colonist_legendary", 1, 1]]},
	"gold": {"name": "Gold Crate", "rolls": 4, "color": Color(1.0, 0.8, 0.3), "guaranteed": "colonist_rare", "table": [
		[35, "pearls", 400, 900], [20, "resources", 150, 250], [22, "crystals", 20, 45],
		[15, "colonist_rare", 1, 1], [8, "colonist_legendary", 1, 1]]},
}

## Ежедневные награды: 7-дневный цикл, серия сбрасывается при пропуске дня.
const DAILY := [
	{"pearls": 100}, {"pearls": 200}, {"crystals": 5}, {"pearls": 350},
	{"crates": {"common": 1}}, {"crystals": 15}, {"crates": {"silver": 1}},
]

## Зоны экспедиций. danger — риск потерь здоровья, power — рекомендуемая сила экипажа
## (сумма всех характеристик). loot — [мин, макс] на каждую награду.
const ZONES := [
	{"id": "kelp", "name": "Kelp Forest", "minutes": 10, "danger": 0.1, "power": 10, "unlock_pop": 0,
		"desc": "Calm and shallow. A good first trip.",
		"loot": {"pearls": [60, 140], "resources": [20, 50]}},
	{"id": "reef", "name": "Coral Reef", "minutes": 30, "danger": 0.2, "power": 18, "unlock_pop": 0,
		"desc": "Colorful and full of pearls.",
		"loot": {"pearls": [150, 320], "crystals": [2, 6], "resources": [40, 90]}},
	{"id": "wreck", "name": "Sunken Ship", "minutes": 60, "danger": 0.35, "power": 26, "unlock_pop": 8,
		"desc": "An old wreck. Treasure and trouble.",
		"loot": {"pearls": [300, 600], "crystals": [5, 12], "crate": "common"}},
	{"id": "vents", "name": "Hydrothermal Vents", "minutes": 120, "danger": 0.5, "power": 34, "unlock_pop": 12,
		"desc": "Scalding water, rare minerals.",
		"loot": {"pearls": [500, 900], "crystals": [10, 25], "crate": "silver"}},
	{"id": "trench", "name": "Abyssal Trench", "minutes": 240, "danger": 0.7, "power": 45, "unlock_pop": 16,
		"desc": "The deepest dark. Legends live here.",
		"loot": {"pearls": [900, 1600], "crystals": [25, 50], "crate": "gold", "survivor": 0.35}},
]

## Шаблоны записей журнала экспедиции ({n} — имя члена экипажа).
const LOG_CALM := [
	"{n} spotted a school of glowing fish.", "The bathyscaphe hums along quietly.",
	"{n} hums an old sea shanty.", "A curious turtle follows the sub for a while.",
	"{n} sketches a strange coral formation.", "Sonar pings echo in the dark.",
]
const LOG_FIND := [
	"{n} found a pearl-filled clam!", "{n} pried open an old chest.",
	"{n} collected rare glowing minerals.", "The crew salvaged useful supplies.",
]
const LOG_DANGER := [
	"An anglerfish attacked! {n} fought it off.", "A pressure leak! {n} patched it up.",
	"{n} got tangled in kelp and scraped an arm.", "Strong currents rocked the sub. {n} bumped a head.",
]

## Ежедневные задания: event — что считаем, target — [мин, макс], reward.
const QUEST_POOL := [
	{"event": "collect_energy", "text": "Collect %d energy", "target": [60, 150], "reward": {"pearls": 120}, "xp": 40},
	{"event": "collect_oxygen", "text": "Collect %d oxygen", "target": [60, 150], "reward": {"pearls": 120}, "xp": 40},
	{"event": "collect_food", "text": "Collect %d food", "target": [60, 150], "reward": {"pearls": 120}, "xp": 40},
	{"event": "build", "text": "Build %d rooms", "target": [1, 2], "reward": {"crystals": 5}, "xp": 60},
	{"event": "upgrade", "text": "Upgrade %d rooms", "target": [1, 2], "reward": {"crystals": 5}, "xp": 60},
	{"event": "expedition", "text": "Send %d expeditions", "target": [1, 2], "reward": {"crystals": 8}, "xp": 80},
	{"event": "rush", "text": "Rush rooms %d times", "target": [2, 4], "reward": {"pearls": 150}, "xp": 40},
	{"event": "crate", "text": "Open %d crates", "target": [1, 2], "reward": {"pearls": 200}, "xp": 50},
	{"event": "level_up", "text": "Level up colonists %d times", "target": [1, 3], "reward": {"crystals": 5}, "xp": 60},
]
const QUESTS_PER_DAY := 3

## Сезонный пропуск: уровень каждые SEASON_XP_PER_TIER очков.
const SEASON_DAYS := 30
const SEASON_XP_PER_TIER := 100
const SEASON_TIERS := [
	{"free": {"pearls": 200}, "premium": {"crystals": 30}},
	{"free": {"crystals": 5}, "premium": {"crates": {"silver": 1}}},
	{"free": {"pearls": 300}, "premium": {"pearls": 1000}},
	{"free": {"crates": {"common": 1}}, "premium": {"crystals": 50}},
	{"free": {"pearls": 400}, "premium": {"colonist": "rare"}},
	{"free": {"crystals": 10}, "premium": {"crates": {"gold": 1}}},
	{"free": {"pearls": 500}, "premium": {"crystals": 80}},
	{"free": {"crates": {"silver": 1}}, "premium": {"pearls": 2500}},
	{"free": {"crystals": 15}, "premium": {"crates": {"gold": 1}}},
	{"free": {"crates": {"gold": 1}}, "premium": {"colonist": "legendary"}},
]

const FIRST_NAMES := [
	"Ava", "Ben", "Cora", "Dan", "Ella", "Finn", "Gina", "Hugo", "Iris", "Jack",
	"Kira", "Leo", "Maya", "Nate", "Olive", "Paul", "Quinn", "Rosa", "Sam", "Tess",
	"Uma", "Vic", "Wade", "Yara", "Zoe", "Max", "Nina", "Owen", "Lily", "Theo",
]
const LAST_NAMES := [
	"Wave", "Deep", "Reef", "Storm", "Marin", "Coral", "Tide", "Keel", "Drift",
	"Abyss", "Ray", "Pearl", "Surf", "Anchor", "Shell", "Kelp", "Brine", "Fathom",
]

static func room_width(type: String) -> int:
	return ROOMS[type]["width"]

static func room_slots(type: String, level: int) -> int:
	var base: int = ROOMS[type].get("slots", 0)
	if base == 0:
		return 0
	return base + level - 1

static func upgrade_cost(type: String, level: int) -> int:
	return int(ROOMS[type]["cost"] * (level + 0.5))

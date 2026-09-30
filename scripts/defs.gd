class_name Defs
extends RefCounted
## Статические данные игры: типы комнат, ресурсы, имена колонистов.

const GRID_COLS := 8
const MAX_DEPTH := 14
const MAX_LEVEL := 3

const RESOURCES := {
	"energy": {"name": "Энергия", "short": "Э", "color": Color(1.0, 0.82, 0.3)},
	"oxygen": {"name": "Кислород", "short": "O₂", "color": Color(0.35, 0.92, 1.0)},
	"food": {"name": "Еда", "short": "Е", "color": Color(0.5, 1.0, 0.55)},
	"pearls": {"name": "Жемчуг", "short": "Ж", "color": Color(1.0, 0.75, 0.95)},
}

const STATS := {
	"str": "Сила",
	"tech": "Техника",
	"bio": "Биология",
}

## width — ширина в клетках; slots — рабочих мест на 1 уровне;
## produces/stat/amount/cycle — производство; energy — расход энергии в секунду;
## unlock_pop — сколько колонистов нужно для открытия.
const ROOMS := {
	"airlock": {
		"name": "Шлюз", "width": 2, "cost": 0, "buildable": false, "slots": 0,
		"energy": 0.0, "color": Color(0.35, 0.4, 0.5), "icon": "⇅",
		"desc": "Вход в колонию. Здесь ждут новые колонисты.",
	},
	"elevator": {
		"name": "Лифт", "width": 1, "cost": 40, "buildable": true, "slots": 0,
		"energy": 0.0, "color": Color(0.25, 0.3, 0.38), "icon": "↕", "unlock_pop": 0,
		"desc": "Соединяет уровни. Строится над или под другим лифтом.",
	},
	"living": {
		"name": "Жилой отсек", "width": 2, "cost": 100, "buildable": true, "slots": 0,
		"capacity": 4, "energy": 0.05, "color": Color(0.75, 0.45, 0.9), "icon": "⌂",
		"unlock_pop": 0, "desc": "+4 места для колонистов за уровень.",
	},
	"reactor": {
		"name": "Реактор", "width": 2, "cost": 100, "buildable": true, "slots": 2,
		"produces": "energy", "stat": "str", "amount": 14.0, "cycle": 20.0,
		"energy": 0.0, "color": Color(1.0, 0.72, 0.2), "icon": "ϟ", "unlock_pop": 0,
		"desc": "Даёт энергию. Важна сила.",
	},
	"oxygen": {
		"name": "Генератор O₂", "width": 2, "cost": 100, "buildable": true, "slots": 2,
		"produces": "oxygen", "stat": "tech", "amount": 12.0, "cycle": 20.0,
		"energy": 0.12, "color": Color(0.3, 0.85, 1.0), "icon": "○", "unlock_pop": 0,
		"desc": "Добывает кислород из воды. Важна техника.",
	},
	"farm": {
		"name": "Ферма водорослей", "width": 2, "cost": 100, "buildable": true, "slots": 2,
		"produces": "food", "stat": "bio", "amount": 12.0, "cycle": 20.0,
		"energy": 0.12, "color": Color(0.4, 0.95, 0.45), "icon": "❦", "unlock_pop": 0,
		"desc": "Выращивает еду. Важна биология.",
	},
	"storage": {
		"name": "Склад", "width": 2, "cost": 150, "buildable": true, "slots": 0,
		"storage": 60.0, "energy": 0.05, "color": Color(0.6, 0.55, 0.45), "icon": "▦",
		"unlock_pop": 8, "desc": "+60 к запасу каждого ресурса за уровень.",
	},
	"pearl": {
		"name": "Жемчужная ферма", "width": 2, "cost": 250, "buildable": true, "slots": 2,
		"produces": "pearls", "stat": "bio", "amount": 25.0, "cycle": 45.0,
		"energy": 0.2, "color": Color(1.0, 0.6, 0.9), "icon": "◉", "unlock_pop": 10,
		"desc": "Выращивает жемчуг — валюту колонии.",
	},
	"medbay": {
		"name": "Медотсек", "width": 2, "cost": 200, "buildable": true, "slots": 2,
		"stat": "bio", "heal": true, "energy": 0.15, "color": Color(1.0, 0.4, 0.45),
		"icon": "✚", "unlock_pop": 12, "desc": "Лечит всех колонистов. Важна биология.",
	},
}

const FIRST_NAMES := [
	"Аня", "Борис", "Вера", "Глеб", "Даша", "Егор", "Женя", "Зоя", "Игорь", "Катя",
	"Лев", "Мила", "Ник", "Оля", "Павел", "Рита", "Семён", "Таня", "Уля", "Фёдор",
	"Юля", "Яна", "Марк", "Ева", "Тимур", "Лиза", "Артём", "Соня", "Макс", "Нина",
]
const LAST_NAMES := [
	"Волнов", "Глубин", "Рифов", "Штормов", "Морской", "Кораллов", "Прибой", "Донный",
	"Течёв", "Бездна", "Скатов", "Жемчугов", "Приливов", "Якорев", "Мидий",
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

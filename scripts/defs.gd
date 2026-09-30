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
	"science": {"name": "Science", "short": "S", "color": Color(0.75, 0.6, 1.0)},
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
	"lab": {
		"name": "Research Lab", "width": 2, "cost": 220, "buildable": true, "slots": 2,
		"produces": "science", "stat": "tech", "amount": 10.0, "cycle": 30.0,
		"energy": 0.18, "color": Color(0.7, 0.55, 1.0), "icon": "⚗", "unlock_pop": 6,
		"desc": "Produces science for research. Needs Tech.",
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
## Дополнительные записи журнала для конкретных зон.
const LOG_ZONE := {
	"kelp": ["{n} got lost in the kelp for a moment, then found the way back.", "Sea otters? This deep? {n} swears they waved.",
		"{n} harvested a bundle of sweet kelp.", "A seahorse hitched a ride on the hull."],
	"reef": ["{n} found a pearl the size of a fist!", "Parrotfish crunch coral all around the sub.",
		"{n} photographed a rare blue octopus.", "A reef shark circled twice, then lost interest."],
	"wreck": ["{n} found an old captain's log. The last page is torn out.", "The wreck groans. {n} decides not to go deeper.",
		"{n} pulled a rusty chest out of the cargo hold!", "Something moved in the dark hallway. {n} didn't wait to see what."],
	"vents": ["The water here is boiling. {n} keeps the sub steady.", "Giant tube worms sway around the vents.",
		"{n} scraped rare minerals off a black smoker.", "Yeti crabs! {n} counts at least forty of them."],
	"trench": ["Total darkness. Only the glow of the lure ahead...", "{n} hears singing through the hull. Whales? Something else?",
		"A shape bigger than the colony passed under the sub.", "{n} found ruins with carvings of the trident symbol."],
}
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

## Зоны глубины. Каждые 5 рядов — новая зона: больше добычи, но и больше бед.
const DEPTH_ZONES := [
	{"name": "Twilight Shelf", "from": 0, "bonus": 0.0, "crystal_chance": 0.0, "danger": 1.0, "research": "",
		"color": Color(0.3, 0.7, 0.9)},
	{"name": "Midnight Zone", "from": 5, "bonus": 0.3, "crystal_chance": 0.06, "danger": 1.5, "research": "deep_drilling",
		"color": Color(0.5, 0.4, 1.0)},
	{"name": "The Abyss", "from": 10, "bonus": 0.7, "crystal_chance": 0.14, "danger": 2.2, "research": "abyssal_engineering",
		"color": Color(1.0, 0.35, 0.5)},
]

## Дерево исследований. cost — наука, minutes — время, req — что нужно изучить раньше.
const RESEARCH := [
	{"id": "efficient_reactors", "tier": 1, "name": "Efficient Reactors", "desc": "+20% energy from reactors.", "cost": 40, "minutes": 2, "req": []},
	{"id": "hydroponics", "tier": 1, "name": "Hydroponics", "desc": "+20% food from farms.", "cost": 40, "minutes": 2, "req": []},
	{"id": "electrolysis", "tier": 1, "name": "Better Electrolysis", "desc": "+20% oxygen from generators.", "cost": 40, "minutes": 2, "req": []},
	{"id": "reinforced_hull", "tier": 1, "name": "Reinforced Hull", "desc": "Incidents happen 30% less often.", "cost": 60, "minutes": 3, "req": []},
	{"id": "training_programs", "tier": 2, "name": "Training Programs", "desc": "Colonists gain XP 50% faster.", "cost": 90, "minutes": 5, "req": ["hydroponics"]},
	{"id": "sonar_mapping", "tier": 2, "name": "Sonar Mapping", "desc": "Expeditions bring 25% more loot.", "cost": 100, "minutes": 5, "req": ["electrolysis"]},
	{"id": "fire_suppression", "tier": 2, "name": "Fire Suppression", "desc": "Incidents are handled twice as fast.", "cost": 100, "minutes": 5, "req": ["reinforced_hull"]},
	{"id": "deep_drilling", "tier": 2, "name": "Deep Drilling", "desc": "Build in the Midnight Zone (rows 6-10).", "cost": 150, "minutes": 8, "req": ["efficient_reactors", "reinforced_hull"]},
	{"id": "auto_collectors", "tier": 3, "name": "Auto-Collectors", "desc": "Rooms collect resources by themselves.", "cost": 250, "minutes": 15, "req": ["efficient_reactors", "hydroponics", "electrolysis"]},
	{"id": "medical_ai", "tier": 3, "name": "Medical AI", "desc": "Colonists heal 3 times faster.", "cost": 200, "minutes": 10, "req": ["training_programs"]},
	{"id": "bathyscaphe_engines", "tier": 3, "name": "Turbo Engines", "desc": "Expeditions are 30% shorter.", "cost": 220, "minutes": 12, "req": ["sonar_mapping"]},
	{"id": "storage_compression", "tier": 3, "name": "Compressed Storage", "desc": "+50% storage for all resources.", "cost": 200, "minutes": 10, "req": ["deep_drilling"]},
	{"id": "pearl_cultivation", "tier": 3, "name": "Pearl Cultivation", "desc": "+40% pearls from pearl farms.", "cost": 220, "minutes": 12, "req": ["hydroponics"]},
	{"id": "trader_beacon", "tier": 3, "name": "Trader Beacon", "desc": "Wandering traders visit twice as often.", "cost": 180, "minutes": 10, "req": ["sonar_mapping"]},
	{"id": "abyssal_engineering", "tier": 4, "name": "Abyssal Engineering", "desc": "Build in The Abyss (rows 11-14).", "cost": 400, "minutes": 25, "req": ["deep_drilling", "fire_suppression"]},
	{"id": "legendary_signal", "tier": 4, "name": "Legendary Signal", "desc": "10% of new arrivals are Rare colonists.", "cost": 350, "minutes": 20, "req": ["training_programs", "sonar_mapping"]},
	{"id": "fusion_core", "tier": 4, "name": "Fusion Core", "desc": "All rooms use 40% less energy.", "cost": 450, "minutes": 30, "req": ["auto_collectors", "storage_compression"]},
]

## Снаряжение: база предмета. stats — какие навыки усиливает.
const ITEMS := [
	{"id": "wrench", "kind": "tool", "name": "Wrench", "stats": ["str"]},
	{"id": "harpoon", "kind": "tool", "name": "Harpoon", "stats": ["str"]},
	{"id": "torch", "kind": "tool", "name": "Welding Torch", "stats": ["tech"]},
	{"id": "scanner", "kind": "tool", "name": "Bio Scanner", "stats": ["bio"]},
	{"id": "coral_knife", "kind": "tool", "name": "Coral Knife", "stats": ["bio"]},
	{"id": "reactor_suit", "kind": "suit", "name": "Reactor Suit", "stats": ["str"]},
	{"id": "engineer_suit", "kind": "suit", "name": "Engineer Suit", "stats": ["tech"]},
	{"id": "medic_suit", "kind": "suit", "name": "Medic Suit", "stats": ["bio"]},
	{"id": "explorer_suit", "kind": "suit", "name": "Explorer Suit", "stats": ["str", "tech", "bio"]},
	{"id": "diving_armor", "kind": "armor", "name": "Diving Armor", "stats": []},
	{"id": "shark_mesh", "kind": "armor", "name": "Shark Mesh", "stats": []},
	{"id": "heat_plate", "kind": "armor", "name": "Heat Shield Plate", "stats": []},
]
const ITEM_RARITY := {
	"common": {"name": "Common", "bonus": 1, "color": Color(0.8, 0.85, 0.9)},
	"rare": {"name": "Rare", "bonus": 2, "color": Color(0.4, 0.75, 1.0)},
	"legendary": {"name": "Legendary", "bonus": 4, "color": Color(1.0, 0.75, 0.25)},
}

## Сюжет: сообщения командира по рации. goal — [событие, сколько].
const STORY := [
	{"title": "Welcome, Overseer", "text": "Commander Reyes here. The surface is gone, and this colony is all we have. Collect what the reactor made to get started.", "goal": ["collect_energy", 10], "reward": {"pearls": 100}},
	{"title": "A Place to Sleep", "text": "More survivors are coming. Build Living Quarters so they have somewhere to rest.", "goal": ["build_living", 1], "reward": {"pearls": 150}},
	{"title": "Everyone Works", "text": "Idle hands won't keep us breathing. Drag a colonist into a room with free slots.", "goal": ["assign", 1], "reward": {"pearls": 100}},
	{"title": "Growing Colony", "text": "The beacon is working. Reach 8 colonists.", "goal": ["population", 8], "reward": {"crystals": 10}},
	{"title": "Into the Blue", "text": "Build a Sub Dock and send our first crew out. Who knows what's out there.", "goal": ["expedition", 1], "reward": {"crates": {"common": 1}}},
	{"title": "Knowledge Is Power", "text": "We need science. Build a Research Lab and finish any research.", "goal": ["research", 1], "reward": {"crystals": 15}},
	{"title": "Trouble Below", "text": "Fires, floods, things with teeth... Handle 3 incidents and keep everyone alive.", "goal": ["incident_resolved", 3], "reward": {"pearls": 400}},
	{"title": "Deeper", "text": "Our scans show warm vents in the Midnight Zone. Research Deep Drilling and build a room below row 5.", "goal": ["depth", 6], "reward": {"crystals": 25}},
	{"title": "The Wreck", "text": "Sonar found an old ship. Send an expedition to the Sunken Ship.", "goal": ["expedition_wreck", 1], "reward": {"crates": {"silver": 1}}},
	{"title": "A Real Home", "text": "Merge rooms: build a room right next to one of the same type and level. Reach 15 colonists.", "goal": ["population", 15], "reward": {"crystals": 30}},
	{"title": "Signal from the Abyss", "text": "Something is calling from the deep. Reach The Abyss (row 11).", "goal": ["depth", 11], "reward": {"crates": {"gold": 1}}},
	{"title": "Legend of the Trench", "text": "Send a crew to the Abyssal Trench. Bring back whatever sings down there.", "goal": ["expedition_trench", 1], "reward": {"crystals": 60, "colonist": "legendary"}},
]

## Достижения: stat — счётчик в Game.stats, tiers — пороги.
const ACHIEVEMENTS := [
	{"id": "pop", "name": "Colony Founder", "desc": "Reach %d colonists", "stat": "population", "tiers": [10, 20, 35], "reward": [10, 25, 50]},
	{"id": "builder", "name": "Master Builder", "desc": "Build %d rooms", "stat": "build", "tiers": [5, 15, 30], "reward": [10, 20, 40]},
	{"id": "collector", "name": "Harvester", "desc": "Collect from rooms %d times", "stat": "collect", "tiers": [50, 300, 1000], "reward": [10, 25, 50]},
	{"id": "explorer", "name": "Explorer", "desc": "Complete %d expeditions", "stat": "expedition_done", "tiers": [3, 15, 50], "reward": [15, 30, 60]},
	{"id": "firefighter", "name": "First Responder", "desc": "Handle %d incidents", "stat": "incident_resolved", "tiers": [5, 25, 75], "reward": [10, 25, 50]},
	{"id": "scientist", "name": "Scientist", "desc": "Finish %d research projects", "stat": "research", "tiers": [3, 8, 17], "reward": [15, 30, 60]},
	{"id": "deep", "name": "Deep Diver", "desc": "Build on row %d", "stat": "depth", "tiers": [5, 10, 14], "reward": [15, 30, 60]},
	{"id": "looter", "name": "Treasure Hunter", "desc": "Open %d crates", "stat": "crate", "tiers": [5, 20, 60], "reward": [10, 25, 50]},
	{"id": "trainer", "name": "Coach", "desc": "Level up colonists %d times", "stat": "level_up", "tiers": [10, 50, 150], "reward": [10, 25, 50]},
	{"id": "bubbles", "name": "Bubble Popper", "desc": "Pop %d treasure bubbles", "stat": "bubble", "tiers": [10, 50, 200], "reward": [10, 20, 40]},
]

## Еженедельные события: модификатор + цель с 3 наградами.
const WEEKLY := [
	{"name": "Pearl Week", "desc": "Pearl farms produce +50%. Collect pearls from rooms!", "mod": "pearl_week", "goal": "collect_pearls", "tiers": [300, 1200, 3000]},
	{"name": "Abyssal Tide", "desc": "Creatures attack more often, but handling incidents gives double pearls.", "mod": "tide", "goal": "incident_resolved", "tiers": [5, 15, 30]},
	{"name": "Harvest Festival", "desc": "Farms produce +50%. Collect food!", "mod": "harvest", "goal": "collect_food", "tiers": [500, 2000, 5000]},
	{"name": "Explorer's Season", "desc": "Expeditions bring +50% loot. Send expeditions!", "mod": "explorers", "goal": "expedition", "tiers": [3, 8, 15]},
]
const WEEKLY_REWARDS := [{"crystals": 15}, {"crates": {"silver": 1}}, {"crystals": 40, "crates": {"gold": 1}}]

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
